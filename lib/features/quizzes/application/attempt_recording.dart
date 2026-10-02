import 'package:flutter/foundation.dart';

import '../../../data/models/quiz_attempt.dart';
import '../../../data/repositories/attempt_repository.dart';
import '../../../data/repositories/mistake_repository.dart';
import '../domain/quiz_session.dart';

/// Saves a finished practice/mistakes run as a completed attempt and records
/// its graded answers in the Mistakes set. Returns the saved attempt.
Future<QuizAttempt> saveSessionAttempt({
  required AttemptRepository attempts,
  required MistakeRepository mistakes,
  required String quizId,
  required QuizSession session,
  required DateTime completedAt,
  AttemptMode mode = AttemptMode.practice,
  List<String>? questionIds,
}) async {
  final started = await attempts.start(
    quizId: quizId,
    total: session.length,
    mode: mode,
    questionIds: questionIds,
  );
  final saved = await attempts.save(
    session.toAttempt(started, completedAt: completedAt),
  );
  await recordAttemptMistakes(mistakes, saved);
  return saved;
}

/// `MistakeRepository.recordAttempt`, best effort: the attempt itself is
/// already saved, so a failure here must not be reported as a failed save
/// (and must not be retried, which would count answers twice).
Future<void> recordAttemptMistakes(
  MistakeRepository mistakes,
  QuizAttempt attempt,
) async {
  try {
    await mistakes.recordAttempt(attempt);
  } on Object catch (e) {
    debugPrint('Could not record mistakes: $e');
  }
}

/// Records graded answers of a run that is not saved as an attempt (e.g. a
/// "retry missed" round, or a self-grade after an exam). Best effort.
Future<void> recordAnswers(
  MistakeRepository mistakes,
  String quizId,
  Iterable<QuestionAnswer> answers,
) async {
  for (final a in answers) {
    final correct = a.isCorrect;
    if (correct == null) continue;
    try {
      await mistakes.recordAnswer(
        quizId: quizId,
        questionId: a.questionId,
        correct: correct,
      );
    } on Object catch (e) {
      debugPrint('Could not record mistake: $e');
    }
  }
}
