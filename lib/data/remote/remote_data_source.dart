import 'dart:typed_data';

import '../local/sync_meta_store.dart';
import '../models/share.dart';

/// How a remote failure should be handled by sync / repositories.
enum RemoteErrorKind {
  /// No connectivity, DNS, socket, timeout. Retry later; nothing is dropped.
  network,

  /// Session missing/expired (JWT). Stop syncing until re-auth.
  auth,

  /// The server refused this request and will keep refusing it (RLS
  /// violation, constraint/validation error, 4xx). The op is dropped.
  permanent,

  /// Foreign-key violation: usually the parent row has not been pushed yet.
  /// The op is deferred to the end of the queue and retried.
  dependency,

  /// Unique violation (e.g. share already exists).
  conflict,

  /// Server-side/transient (5xx, timeouts in the DB, unknown). Retried with
  /// backoff up to a maximum number of attempts.
  transient,
}

/// Error raised by remote data sources. Converted to `AppException` by
/// repositories; interpreted by the sync engine.
class RemoteException implements Exception {
  const RemoteException(this.kind, this.message, {this.code, this.cause});

  final RemoteErrorKind kind;

  /// Diagnostic message (may contain server text; not necessarily user-safe).
  final String message;

  /// Postgres SQLSTATE / PostgREST code / HTTP status, when known.
  final String? code;
  final Object? cause;

  @override
  String toString() => 'RemoteException($kind, $code): $message';
}

/// Table access needed by the sync engine. Rows are raw Supabase JSON
/// (snake_case). Implementations throw [RemoteException].
abstract interface class SyncRemoteDataSource {
  /// Inserts or updates [row] (conflict on `id`). Returns the stored row
  /// (with the server `updated_at`), or null if not returned.
  Future<Map<String, dynamic>?> upsert(String table, Map<String, dynamic> row);

  /// One page of rows visible to the caller with
  /// `(updated_at, id) > (after.updatedAt, after.id)`, ordered by
  /// `updated_at, id` ascending. `after == null` starts at the beginning.
  Future<List<Map<String, dynamic>>> pullPage(
    String table, {
    PullCursor? after,
    required int limit,
  });

  /// Row by id, or null if it does not exist or is not visible.
  Future<Map<String, dynamic>?> fetchById(String table, String id);

  /// All visible rows where [column] equals [value] (used to backfill rows
  /// that became visible through a new share).
  Future<List<Map<String, dynamic>>> fetchWhere(
    String table,
    String column,
    String value,
  );

  /// The subset of [ids] that still exist and are visible to the caller.
  Future<Set<String>> fetchVisibleIds(String table, List<String> ids);

  /// Shares received by [userId] (resource type + id).
  Future<List<({ShareResourceType type, String resourceId})>> incomingShares(
    String userId,
  );
}

/// A pending Storage copy queued by the `copy_*` RPCs in
/// `public.note_image_copies` (owner = caller).
typedef NoteImageCopy = ({String id, String fromPath, String toPath});

/// `note-images` Storage access. Implementations throw [RemoteException].
abstract interface class ImageRemoteDataSource {
  Future<void> uploadImage(String path, Uint8List bytes, {String? contentType});
  Future<Uint8List> downloadImage(String path);
  Future<String> createSignedUrl(String path, Duration expiresIn);
  Future<void> removeImages(List<String> paths);

  /// Server-side copy within the bucket.
  Future<void> copyImage(String fromPath, String toPath);

  /// The caller's rows of `note_image_copies`, oldest first.
  Future<List<NoteImageCopy>> pendingImageCopies();

  /// Deletes one `note_image_copies` row.
  Future<void> deleteImageCopy(String id);
}

/// Sharing and RPCs. Implementations throw [RemoteException].
abstract interface class ShareRemoteDataSource {
  /// `find_user_by_email` RPC: `(id, displayName, email)` or null.
  Future<({String id, String? displayName, String? email})?> findUserByEmail(
    String email,
  );

  /// Inserts a share row and returns it.
  Future<Map<String, dynamic>> insertShare(Map<String, dynamic> row);

  /// Existing share for (type, resource, recipient), or null.
  Future<Map<String, dynamic>?> findShare({
    required ShareResourceType type,
    required String resourceId,
    required String recipientId,
  });

  Future<void> deleteShare(String shareId);

  /// Shares owned by [ownerId] for one resource, with the `recipient`
  /// profile embedded.
  Future<List<Map<String, dynamic>>> sharesForResource({
    required String ownerId,
    required ShareResourceType type,
    required String resourceId,
  });

  /// Shares whose recipient is [recipientId], with the `owner` profile
  /// embedded.
  Future<List<Map<String, dynamic>>> sharesForRecipient(String recipientId);

  /// Profiles by id (`profiles` rows visible to the caller).
  Future<List<Map<String, dynamic>>> fetchProfiles(List<String> ids);

  /// `title` column of a visible row, or null.
  Future<String?> fetchTitle(String table, String id);

  /// Calls `copy_subject` / `copy_note` / `copy_quiz`; returns the new id.
  Future<String> copyResource({
    required ShareResourceType type,
    required String resourceId,
    String? targetSubjectId,
    String? targetNoteId,
  });
}
