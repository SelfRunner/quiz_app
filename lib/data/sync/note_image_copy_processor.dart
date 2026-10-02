import '../local/image_cache.dart';
import '../models/outbox_op.dart';
import '../remote/remote_data_source.dart';

/// Completes the Storage half of `copy_note` / `copy_subject`.
///
/// The RPCs copy rows, rewrite `note-image://{src_owner}/{src_note}/{file}`
/// in `content_md` to `note-image://{me}/{new_note}/{file}` and queue one
/// `public.note_image_copies(bucket, from_path, to_path)` row per file
/// (`bucket` = `note-images` for note images, `attachments` for the files of
/// a copied subject). This processor copies each object within its bucket
/// (`storage.from(bucket).copy(from, to)`), copies locally cached bytes to
/// the new path, and deletes the row:
/// - on success, or when the target already exists (409),
/// - when the source is gone / no longer readable (any permanent error):
///   the blob then stays missing, by design (no data leak after revoke).
/// Network/transient errors leave the row for the next sync. Runs right
/// after a copy (ShareRepository) and on every sync (leftovers).
class NoteImageCopyProcessor {
  NoteImageCopyProcessor(
    this._remote,
    LocalImageCache imageCache, {
    LocalImageCache? attachmentCache,
  }) : _caches = {
         SyncTables.noteImagesBucket: imageCache,
         SyncTables.attachmentsBucket: ?attachmentCache,
       };

  final ImageRemoteDataSource _remote;
  final Map<String, LocalImageCache> _caches;
  Future<int>? _running;

  /// Processes all pending copies. Returns the number of rows completed.
  /// Concurrent calls join the running pass. Throws [RemoteException] for
  /// network/auth errors.
  Future<int> run() => _running ??= _run().whenComplete(() => _running = null);

  Future<int> _run() async {
    final copies = await _remote.pendingImageCopies();
    var done = 0;
    for (final copy in copies) {
      try {
        await _remote.copyImage(
          copy.fromPath,
          copy.toPath,
          bucket: copy.bucket,
        );
        final cache = _caches[copy.bucket];
        if (cache != null) {
          try {
            final cached = await cache.read(copy.fromPath);
            if (cached != null) await cache.write(copy.toPath, cached);
          } catch (_) {
            // Local cache is best effort; the copy is downloaded on demand.
          }
        }
      } on RemoteException catch (e) {
        switch (e.kind) {
          case RemoteErrorKind.network:
          case RemoteErrorKind.auth:
            rethrow;
          case RemoteErrorKind.transient:
          case RemoteErrorKind.dependency:
            continue; // Keep the row; retry on a later sync.
          case RemoteErrorKind.conflict:
          case RemoteErrorKind.permanent:
            break; // Already copied, or source gone/unreadable: drop row.
        }
      }
      await _remote.deleteImageCopy(copy.id);
      done++;
    }
    return done;
  }
}
