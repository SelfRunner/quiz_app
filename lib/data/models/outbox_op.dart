import 'package:freezed_annotation/freezed_annotation.dart';

part 'outbox_op.freezed.dart';
part 'outbox_op.g.dart';

enum OutboxOpType {
  /// Insert-or-update [OutboxOp.payload] into [OutboxOp.table].
  /// Soft deletes are upserts with `deleted_at` set.
  @JsonValue('upsert')
  upsert,

  /// Hard delete of [OutboxOp.rowId] (reserved; entities use soft delete).
  @JsonValue('delete')
  delete,

  /// Upload a locally saved image to Storage. `table` is the bucket
  /// (`SyncTables.noteImagesBucket`), `rowId` the storage path.
  @JsonValue('upload_image')
  uploadImage,

  /// Remove an image from Storage. `rowId` is the storage path.
  @JsonValue('delete_image')
  deleteImage,
}

/// A pending local write waiting to be pushed to Supabase, processed FIFO by
/// `createdAt`.
@freezed
abstract class OutboxOp with _$OutboxOp {
  const factory OutboxOp({
    required String id,

    /// Table name (`SyncTables.*`) or storage bucket for image ops.
    required String table,
    required OutboxOpType op,
    required String rowId,

    /// Full row JSON for upserts; op-specific data otherwise.
    Map<String, dynamic>? payload,
    required DateTime createdAt,
    @Default(0) int attempts,
    String? lastError,
  }) = _OutboxOp;

  factory OutboxOp.fromJson(Map<String, dynamic> json) =>
      _$OutboxOpFromJson(json);
}

/// Supabase table / bucket names used by sync.
abstract final class SyncTables {
  static const String subjects = 'subjects';
  static const String notes = 'notes';
  static const String quizzes = 'quizzes';
  static const String quizAttempts = 'quiz_attempts';
  static const String shares = 'shares';
  static const String profiles = 'profiles';

  /// Storage bucket for note images.
  static const String noteImagesBucket = 'note-images';

  /// Tables pulled by the sync engine, in dependency order.
  static const List<String> synced = [subjects, notes, quizzes, quizAttempts];
}
