import '../models/note.dart';

/// Local-first access to notes (same semantics as `SubjectRepository`).
abstract interface class NoteRepository {
  /// Notes in [subjectId] (own or shared), sorted by `updatedAt` desc.
  Stream<List<Note>> watchBySubject(String subjectId);

  /// Every live note the user can read: own notes and notes shared with
  /// them (directly or through a shared subject), `updatedAt` desc. For the
  /// note picker; filter with `searchNotes` (note_search.dart).
  Stream<List<Note>> watchAllAccessible();

  Stream<Note?> watchById(String id);

  Future<Note?> getById(String id);

  Future<Note> create({
    required String subjectId,
    required String title,
    String contentMd = '',
  });

  /// Throws `PermissionDeniedException` if not owned by the current user.
  Future<Note> update(Note note);

  /// Soft-deletes the note and its quizzes; queues deletion of its images.
  Future<void> delete(String id);
}
