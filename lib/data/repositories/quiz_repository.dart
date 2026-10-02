import '../models/question.dart';
import '../models/quiz.dart';
import '../models/quiz_source.dart';

/// Local-first access to quizzes (same semantics as `SubjectRepository`).
abstract interface class QuizRepository {
  /// All quizzes in [subjectId], including those attached to a note,
  /// sorted by `updatedAt` desc.
  Stream<List<Quiz>> watchBySubject(String subjectId);

  /// Quizzes attached to [noteId].
  Stream<List<Quiz>> watchByNote(String noteId);

  Stream<Quiz?> watchById(String id);

  Future<Quiz?> getById(String id);

  Future<Quiz> create({
    required String subjectId,
    String? noteId,
    required String title,
    String? description,
    List<Question> questions = const [],
    QuizSource? source,
  });

  /// Throws `PermissionDeniedException` if not owned by the current user.
  Future<Quiz> update(Quiz quiz);

  Future<void> delete(String id);
}
