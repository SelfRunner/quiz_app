import '../models/subject.dart';

/// Local-first access to subjects. Reads come from Hive; writes go to Hive and
/// the outbox, then sync pushes them. Streams emit immediately and again on
/// every local change; soft-deleted rows are excluded.
abstract interface class SubjectRepository {
  /// Subjects owned by the current user, sorted by title (case-insensitive).
  Stream<List<Subject>> watchAll();

  /// Any locally cached subject (own or shared). Emits null if missing or
  /// deleted.
  Stream<Subject?> watchById(String id);

  Future<Subject?> getById(String id);

  /// Creates a subject owned by the current user (id/timestamps generated).
  Future<Subject> create({
    required String title,
    String? description,
    int? color,
  });

  /// Saves changes (bumps `updatedAt`). Throws `PermissionDeniedException`
  /// if the subject is not owned by the current user.
  Future<Subject> update(Subject subject);

  /// Soft-deletes the subject and its notes, quizzes (cascade, locally and
  /// via outbox).
  Future<void> delete(String id);
}
