import '../models/quiz_attempt.dart';

/// Local-first access to the current user's quiz attempts.
abstract interface class AttemptRepository {
  /// Current user's attempts for [quizId], newest `startedAt` first.
  Stream<List<QuizAttempt>> watchByQuiz(String quizId);

  Stream<QuizAttempt?> watchById(String id);

  Future<QuizAttempt?> getById(String id);

  /// Creates a new in-progress attempt (`completedAt == null`, empty answers,
  /// `total` = question count).
  Future<QuizAttempt> start({required String quizId, required int total});

  /// Upserts an attempt (answers, score, completion). Bumps `updatedAt`.
  Future<QuizAttempt> save(QuizAttempt attempt);

  Future<void> delete(String id);
}
