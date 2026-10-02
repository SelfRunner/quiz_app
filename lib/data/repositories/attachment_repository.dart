import 'dart:typed_data';

import '../models/attachment.dart';

/// Where an attachment's blob upload stands (coarse: the Storage client does
/// not report byte progress).
enum AttachmentUploadPhase {
  /// Waiting in the outbox (offline, or queued behind other changes).
  queued,

  /// The sync engine is uploading it right now.
  uploading,

  /// The last attempt failed (see [AttachmentUploadState.error]); it is
  /// retried automatically.
  retrying,

  /// Nothing pending: uploaded (or not ours to upload, e.g. shared files).
  done,
}

/// Upload state of one attachment (see [AttachmentRepository.watchUpload]).
class AttachmentUploadState {
  const AttachmentUploadState(this.phase, {this.error, this.attempts = 0});

  static const AttachmentUploadState done = AttachmentUploadState(
    AttachmentUploadPhase.done,
  );

  final AttachmentUploadPhase phase;

  /// Diagnostic message of the last failed attempt (not necessarily
  /// user-safe; show a generic text).
  final String? error;
  final int attempts;

  bool get isPending => phase != AttachmentUploadPhase.done;

  @override
  bool operator ==(Object other) =>
      other is AttachmentUploadState &&
      other.phase == phase &&
      other.error == error &&
      other.attempts == attempts;

  @override
  int get hashCode => Object.hash(phase, error, attempts);

  @override
  String toString() => 'AttachmentUploadState($phase, attempts: $attempts)';
}

/// Files attached to subjects ("Files" library), local-first.
///
/// Bytes are stored on the device first (files on native, a lazy Hive box on
/// web), the blob upload to the `attachments` bucket is queued *before* the
/// row upsert, and the row is only pushed after its blob is uploaded.
/// Streams exclude soft-deleted rows. Attachments of shared subjects are
/// read-only (`PermissionDeniedException`).
abstract interface class AttachmentRepository {
  /// Storage limit per file (50 MiB).
  static const int maxSizeBytes = Attachment.maxSizeBytes;

  /// Live attachments of [subjectId] (own or shared), newest first.
  Stream<List<Attachment>> watchBySubject(String subjectId);

  /// Every live attachment the user can read (own + shared subjects) whose
  /// subject is known locally, newest first. For pickers.
  Stream<List<Attachment>> watchAllAccessible();

  Stream<Attachment?> watchById(String id);

  Future<Attachment?> getById(String id);

  /// Adds a file to [subjectId] (must be owned by the current user).
  ///
  /// [name] is the original file name (shown in the UI; its extension drives
  /// [AttachmentKind] detection). [mimeType] defaults to a guess from the
  /// extension. [extractedText] (txt/md/docx text extracted by the caller) is
  /// truncated to [Attachment.maxExtractedTextLength] chars.
  ///
  /// Throws `ValidationException` for empty files or files larger than
  /// [maxSizeBytes], `PermissionDeniedException` for shared subjects,
  /// `NotFoundException` for missing subjects, `StorageException` when the
  /// bytes cannot be stored locally. Works offline.
  Future<Attachment> add({
    required String subjectId,
    required String name,
    String? mimeType,
    required Uint8List bytes,
    String? extractedText,
  });

  /// Saves the mutable fields of [attachment]: `name`, `mimeType`, `kind`,
  /// `extractedText`. Everything else is taken from the stored row.
  Future<Attachment> update(Attachment attachment);

  Future<Attachment> rename(String id, String name);

  /// Soft-deletes the row (tombstone pushed first), then removes the blob
  /// from Storage; local bytes are dropped immediately. Idempotent.
  Future<void> delete(String id);

  /// The file's bytes: local cache, else downloaded (with a cache-busting
  /// query parameter) and cached. Throws `NetworkException` when offline and
  /// not cached, `NotFoundException` when the blob is unavailable (revoked,
  /// deleted, not uploaded or copied yet), `AppAuthException` when signed
  /// out / session expired.
  Future<Uint8List> getBytes(Attachment attachment);

  /// Whether the bytes are available on this device without a download.
  Future<bool> isCached(Attachment attachment);

  /// Upload state of [attachment]'s blob; emits on listen and on change.
  Stream<AttachmentUploadState> watchUpload(Attachment attachment);
}
