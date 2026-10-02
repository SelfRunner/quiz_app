import 'dart:async';
import 'dart:typed_data';

import '../../core/errors/app_exception.dart';
import '../models/models.dart';
import '../remote/remote_data_source.dart';
import 'attachment_repository.dart';
import 'repository_support.dart';

/// Hive-backed [AttachmentRepository]: rows through the outbox, blobs in
/// `db.attachmentFiles` + the `attachments` Storage bucket.
class LocalAttachmentRepository implements AttachmentRepository {
  LocalAttachmentRepository(this._ctx, this._remote);

  final DataContext _ctx;
  final ImageRemoteDataSource _remote;
  final Map<String, Future<Uint8List>> _downloads = {};

  static const String _bucket = SyncTables.attachmentsBucket;

  static int _newestFirst(Attachment a, Attachment b) {
    final c = b.createdAt.compareTo(a.createdAt);
    return c != 0 ? c : a.id.compareTo(b.id);
  }

  @override
  Stream<List<Attachment>> watchBySubject(String subjectId) => _ctx
      .db
      .attachments
      .watchWhere((a) => a.subjectId == subjectId, compare: _newestFirst);

  @override
  Stream<List<Attachment>> watchAllAccessible() {
    // Re-evaluated on attachment changes; the subject check reads the
    // subjects box, so also re-emit when subjects change.
    final subjects = _ctx.db.subjects;
    bool test(Attachment a) => subjects.getLive(a.subjectId) != null;
    return _mergeTriggers(
      _ctx.db.attachments.watchWhere(test, compare: _newestFirst),
      subjects.box.watch(),
      () => _ctx.db.attachments.where(test, compare: _newestFirst),
    );
  }

  @override
  Stream<Attachment?> watchById(String id) => _ctx.db.attachments.watchById(id);

  @override
  Future<Attachment?> getById(String id) async =>
      _ctx.db.attachments.getLive(id);

  @override
  Future<Attachment> add({
    required String subjectId,
    required String name,
    String? mimeType,
    required Uint8List bytes,
    String? extractedText,
  }) async {
    final userId = _ctx.requireUserId();
    final subject = _ctx.requireLive(_ctx.db.subjects, subjectId, 'subject');
    _ctx.ensureOwned(subject, userId, 'subject');
    final displayName = _displayName(name, fallback: 'file');
    if (bytes.isEmpty) {
      throw ValidationException('"$displayName" is empty.');
    }
    if (bytes.length > AttachmentRepository.maxSizeBytes) {
      throw ValidationException(
        '"$displayName" is too large (${_megabytes(bytes.length)} MB). '
        'Files can be at most '
        '${AttachmentRepository.maxSizeBytes ~/ (1024 * 1024)} MB.',
      );
    }
    final mime = _mime(mimeType) ?? mimeTypeForFileName(displayName);
    final id = _ctx.newId();
    final now = _ctx.clock();
    final attachment = Attachment(
      id: id,
      subjectId: subjectId,
      ownerId: userId,
      name: displayName,
      mimeType: mime,
      sizeBytes: bytes.length,
      kind: AttachmentKind.detect(fileName: displayName, mimeType: mime),
      storagePath: Attachment.buildStoragePath(
        ownerId: userId,
        subjectId: subjectId,
        id: id,
        fileName: displayName,
      ),
      extractedText: _text(extractedText),
      createdAt: now,
      updatedAt: now,
    );
    try {
      await _ctx.db.attachmentFiles.write(attachment.storagePath, bytes);
    } catch (e, st) {
      throw StorageException(
        'Could not save "$displayName" on this device.',
        cause: e,
        stackTrace: st,
      );
    }
    // Blob upload first, row second (FIFO): recipients should not see a
    // row whose blob is missing.
    await _ctx.db.outbox.enqueue(
      table: _bucket,
      op: OutboxOpType.uploadAttachment,
      rowId: attachment.storagePath,
      payload: {
        'attachment_id': id,
        'content_type': mime ?? 'application/octet-stream',
      },
    );
    await _ctx.save(_ctx.db.attachments, attachment);
    return attachment;
  }

  @override
  Future<Attachment> update(Attachment attachment) async {
    final userId = _ctx.requireUserId();
    final existing = _ctx.requireLive(
      _ctx.db.attachments,
      attachment.id,
      'file',
    );
    _ctx.ensureOwned(existing, userId, 'file');
    final name = _displayName(attachment.name);
    if (name.isEmpty) {
      throw const ValidationException('Please enter a file name.');
    }
    final next = existing.copyWith(
      name: name,
      mimeType: _mime(attachment.mimeType),
      kind: attachment.kind,
      extractedText: _text(attachment.extractedText),
      updatedAt: _ctx.clock(),
    );
    await _ctx.save(_ctx.db.attachments, next);
    return next;
  }

  @override
  Future<Attachment> rename(String id, String name) async {
    final existing = _ctx.requireLive(_ctx.db.attachments, id, 'file');
    return update(existing.copyWith(name: name));
  }

  @override
  Future<void> delete(String id) async {
    final userId = _ctx.requireUserId();
    final existing = _ctx.db.attachments.getLive(id);
    if (existing == null) return;
    _ctx.ensureOwned(existing, userId, 'file');
    await _ctx.deleteAttachment(existing);
  }

  @override
  Future<Uint8List> getBytes(Attachment attachment) async {
    final path = attachment.storagePath;
    try {
      final local = await _ctx.db.attachmentFiles.read(path);
      if (local != null) return local;
    } catch (_) {
      // Fall through to download.
    }
    // (The callback must not return the removed future: whenComplete would
    // wait for it, i.e. for itself.)
    return _downloads[path] ??= _download(attachment).whenComplete(() {
      _downloads.remove(path);
    });
  }

  Future<Uint8List> _download(Attachment attachment) async {
    final path = attachment.storagePath;
    final Uint8List bytes;
    try {
      bytes = await _remote.downloadImage(path, bucket: _bucket);
    } on RemoteException catch (e) {
      throw switch (e.kind) {
        RemoteErrorKind.network => NetworkException(
          "You're offline. Connect to the internet to open this file.",
          cause: e,
        ),
        RemoteErrorKind.auth => AppAuthException(
          'Your session has expired. Please sign in again.',
          cause: e,
        ),
        RemoteErrorKind.transient => UnknownException(
          'Could not download the file. Please try again.',
          cause: e,
        ),
        _ => NotFoundException(
          "This file isn't available. It may have been removed or unshared, "
          "or it hasn't finished uploading yet.",
          cause: e,
        ),
      };
    }
    // Only cache while the row is still known locally (not purged by a
    // revoke that raced with the download).
    if (_ctx.db.attachments.get(attachment.id) != null) {
      try {
        await _ctx.db.attachmentFiles.write(path, bytes);
      } catch (_) {}
    }
    return bytes;
  }

  @override
  Future<bool> isCached(Attachment attachment) async {
    try {
      return await _ctx.db.attachmentFiles.read(attachment.storagePath) != null;
    } catch (_) {
      return false;
    }
  }

  @override
  Stream<AttachmentUploadState> watchUpload(Attachment attachment) {
    final path = attachment.storagePath;
    AttachmentUploadState current() {
      final op = _ctx.db.outbox.pendingFor(
        _bucket,
        path,
        op: OutboxOpType.uploadAttachment,
      );
      if (op == null) return AttachmentUploadState.done;
      if (_ctx.db.transfers.isActive(path)) {
        return AttachmentUploadState(
          AttachmentUploadPhase.uploading,
          attempts: op.attempts,
        );
      }
      if (op.lastError != null) {
        return AttachmentUploadState(
          AttachmentUploadPhase.retrying,
          error: op.lastError,
          attempts: op.attempts,
        );
      }
      return const AttachmentUploadState(AttachmentUploadPhase.queued);
    }

    return _mergeTriggers(
      Stream.value(current()),
      _ctx.db.outbox.box.watch(),
      current,
      extra: _ctx.db.transfers.changes,
    );
  }

  // ---------------------------------------------------------------------------

  /// Emits [initial]'s values, plus [query] whenever [trigger] (or [extra])
  /// fires; consecutive duplicates are dropped.
  static Stream<T> _mergeTriggers<T>(
    Stream<T> initial,
    Stream<Object?> trigger,
    T Function() query, {
    Stream<Object?>? extra,
  }) {
    late final StreamController<T> controller;
    final subs = <StreamSubscription<Object?>>[];
    Timer? pending;
    var hasLast = false;
    late T last;

    void push(T value) {
      if (controller.isClosed) return;
      if (hasLast && _equal(last, value)) return;
      hasLast = true;
      last = value;
      controller.add(value);
    }

    void requery() {
      pending ??= Timer(Duration.zero, () {
        pending = null;
        try {
          push(query());
        } catch (e, st) {
          if (!controller.isClosed) controller.addError(e, st);
        }
      });
    }

    controller = StreamController<T>(
      onListen: () {
        subs
          ..add(initial.listen(push, onError: controller.addError))
          ..add(trigger.listen((_) => requery()));
        if (extra != null) subs.add(extra.listen((_) => requery()));
      },
      onCancel: () async {
        pending?.cancel();
        for (final s in subs) {
          await s.cancel();
        }
      },
    );
    return controller.stream;
  }

  static bool _equal(Object? a, Object? b) {
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (a[i] != b[i]) return false;
      }
      return true;
    }
    return a == b;
  }

  static String _displayName(String name, {String fallback = ''}) {
    var n = name.split(RegExp(r'[/\\]')).last.trim();
    if (n.isEmpty) n = fallback;
    return _truncate(n, Attachment.maxNameLength);
  }

  static String? _mime(String? mimeType) {
    final m = mimeType?.trim();
    if (m == null || m.isEmpty || m.length > 255) return null;
    return m;
  }

  static String? _text(String? text) {
    if (text == null || text.isEmpty) return null;
    return _truncate(text, Attachment.maxExtractedTextLength);
  }

  /// At most [max] UTF-16 units, never ending in half a surrogate pair.
  static String _truncate(String s, int max) {
    if (s.length <= max) return s;
    var end = max;
    final last = s.codeUnitAt(end - 1);
    if (last >= 0xD800 && last <= 0xDBFF) end--;
    return s.substring(0, end);
  }

  static String _megabytes(int bytes) =>
      (bytes / (1024 * 1024)).toStringAsFixed(1);
}
