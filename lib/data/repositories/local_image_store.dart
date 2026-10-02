import 'dart:collection';
import 'dart:typed_data';

import '../../core/errors/app_exception.dart';
import '../models/models.dart';
import '../remote/remote_data_source.dart';
import 'image_store.dart';
import 'repository_support.dart';

/// [ImageStore] that saves images locally first and uploads them through
/// the outbox.
///
/// Markdown references images as `note-image://{owner}/{note}/{uuid}.{ext}`
/// (`NoteImageRef.markdownUrl`). [load] resolves a reference to bytes:
/// in-memory LRU -> local cache (files on native, Hive on web) -> download
/// from Storage (then cached). [signedUrl] is available for widgets that
/// need a network URL.
class LocalImageStore implements ImageStore {
  LocalImageStore(
    this._ctx,
    this._remote, {
    this.memoryCacheSize = 32,
    this.signedUrlTtl = const Duration(hours: 1),
  });

  final DataContext _ctx;
  final ImageRemoteDataSource _remote;
  final int memoryCacheSize;
  final Duration signedUrlTtl;

  final LinkedHashMap<String, Uint8List> _memory =
      LinkedHashMap<String, Uint8List>();
  final Map<String, ({String url, DateTime expiresAt})> _signed = {};
  String? _cacheUser;

  static const Map<String, String> _mimeTypes = {
    'png': 'image/png',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'gif': 'image/gif',
    'webp': 'image/webp',
    'bmp': 'image/bmp',
    'svg': 'image/svg+xml',
    'heic': 'image/heic',
  };

  static String _normalizeExtension(String extension) {
    final ext = extension
        .toLowerCase()
        .replaceFirst(RegExp(r'^\.'), '')
        .replaceAll(RegExp('[^a-z0-9]'), '');
    return ext.isEmpty ? 'png' : ext;
  }

  static String contentTypeFor(String fileName) {
    final dot = fileName.lastIndexOf('.');
    final ext = dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();
    return _mimeTypes[ext] ?? 'application/octet-stream';
  }

  @override
  Future<NoteImageRef> saveNoteImage({
    required String noteId,
    required Uint8List bytes,
    required String extension,
  }) async {
    final userId = _ctx.requireUserId();
    _resetIfUserChanged();
    if (bytes.isEmpty) {
      throw const ValidationException('The image is empty.');
    }
    final note = _ctx.requireLive(_ctx.db.notes, noteId, 'note');
    _ctx.ensureOwned(note, userId, 'note');
    final ref = NoteImageRef(
      ownerId: userId,
      noteId: noteId,
      fileName: '${_ctx.newId()}.${_normalizeExtension(extension)}',
    );
    try {
      await _ctx.db.images.write(ref.storagePath, bytes);
    } catch (e, st) {
      throw StorageException(
        'Could not save the image on this device.',
        cause: e,
        stackTrace: st,
      );
    }
    _remember(ref.storagePath, bytes);
    await _ctx.db.outbox.enqueue(
      table: SyncTables.noteImagesBucket,
      op: OutboxOpType.uploadImage,
      rowId: ref.storagePath,
      payload: {
        'content_type': contentTypeFor(ref.fileName),
        'note_id': noteId,
      },
    );
    return ref;
  }

  @override
  Future<Uint8List?> load(NoteImageRef ref) async {
    _resetIfUserChanged();
    final path = ref.storagePath;
    final cached = _memory.remove(path);
    if (cached != null) {
      _memory[path] = cached; // Mark as most recently used.
      return cached;
    }
    try {
      final local = await _ctx.db.images.read(path);
      if (local != null) {
        _remember(path, local);
        return local;
      }
    } catch (_) {
      // Fall through to download.
    }
    try {
      final bytes = await _remote.downloadImage(path);
      _remember(path, bytes);
      try {
        await _ctx.db.images.write(path, bytes);
      } catch (_) {}
      return bytes;
    } on RemoteException {
      return null;
    }
  }

  /// Short-lived signed URL for [ref] (cached until shortly before expiry).
  /// Returns null when offline or not accessible.
  Future<String?> signedUrl(NoteImageRef ref) async {
    _resetIfUserChanged();
    final path = ref.storagePath;
    final now = _ctx.clock();
    final hit = _signed[path];
    if (hit != null &&
        hit.expiresAt.isAfter(now.add(const Duration(minutes: 5)))) {
      return hit.url;
    }
    try {
      final url = await _remote.createSignedUrl(path, signedUrlTtl);
      _signed[path] = (url: url, expiresAt: now.add(signedUrlTtl));
      return url;
    } on RemoteException {
      return null;
    }
  }

  @override
  Future<void> delete(NoteImageRef ref) async {
    final userId = _ctx.requireUserId();
    if (ref.ownerId != userId) {
      throw const PermissionDeniedException(
        'This image belongs to a shared note and is read-only.',
      );
    }
    _memory.remove(ref.storagePath);
    _signed.remove(ref.storagePath);
    await _ctx.queueImageDeletion(ref);
  }

  void _remember(String path, Uint8List bytes) {
    _memory.remove(path);
    _memory[path] = bytes;
    while (_memory.length > memoryCacheSize) {
      _memory.remove(_memory.keys.first);
    }
  }

  void _resetIfUserChanged() {
    final user = _ctx.currentUserId;
    if (user != _cacheUser) {
      _memory.clear();
      _signed.clear();
      _cacheUser = user;
    }
  }
}
