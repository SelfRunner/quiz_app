/// Common shape of every entity synced through the outbox.
///
/// - [id]: client-generated UUID v4.
/// - [ownerId]: `auth.users.id` of the owner (for attempts: the user who took
///   the quiz).
/// - [updatedAt]: set by the client on write and overwritten server-side by a
///   trigger; the sync pull cursor is based on it.
/// - [deletedAt]: soft-delete tombstone. Deleted rows stay in Hive/Supabase and
///   are filtered out of `watch*` streams.
abstract interface class Syncable {
  String get id;
  String get ownerId;
  DateTime get createdAt;
  DateTime get updatedAt;
  DateTime? get deletedAt;

  /// snake_case JSON identical to the Supabase row.
  Map<String, dynamic> toJson();
}

extension SyncableX on Syncable {
  bool get isDeleted => deletedAt != null;

  /// Whether [userId] owns this row (and may edit it). Rows owned by someone
  /// else are shared with the current user and are read-only.
  bool isOwnedBy(String? userId) => userId != null && ownerId == userId;
}
