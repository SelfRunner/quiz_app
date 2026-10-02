/// Exam-mode helpers (pure): question pools, grading, scoring and timing.
library;

import 'dart:math' as math;

import 'package:meta/meta.dart';

import '../data/models/question.dart';
import '../data/models/quiz.dart';
import '../data/models/quiz_attempt.dart';

/// A random pool of [count] questions from [questions] (all of them, in
/// random order, when [count] is null or >= the number of questions).
/// Deterministic for a given [random] (e.g. `Random(seed)` in tests).
List<Question> selectQuestionPool(
  List<Question> questions, {
  int? count,
  math.Random? random,
}) {
  final shuffled = [...questions]..shuffle(random ?? math.Random());
  if (count == null || count >= shuffled.length) return shuffled;
  return shuffled.take(math.max(0, count)).toList();
}

/// The questions served in [attempt], in order: `attempt.questionIds`
/// resolved against [quiz] (ids no longer in the quiz are skipped), or all
/// questions when the attempt has no pool.
List<Question> questionsForAttempt(Quiz quiz, QuizAttempt attempt) {
  final ids = attempt.questionIds;
  if (ids == null) return quiz.questions;
  final byId = {for (final q in quiz.questions) q.id: q};
  return [for (final id in ids) ?byId[id]];
}

/// Auto-grade of an option answer: exact set match of the selected option
/// indices. Short answers are self-graded: returns `answer.isCorrect`.
/// Null when not answered / not graded.
bool? gradeAnswer(Question question, QuestionAnswer? answer) {
  if (answer == null) return null;
  if (question.type == QuestionType.shortAnswer) return answer.isCorrect;
  if (answer.selectedIndices.isEmpty) return null;
  final selected = answer.selectedIndices.toSet();
  final correct = question.correctIndices.toSet();
  return selected.length == correct.length && selected.containsAll(correct);
}

/// Score of a set of answers.
@immutable
class ExamScore {
  const ExamScore({
    required this.correct,
    required this.total,
    required this.answered,
    required this.ungraded,
  });

  /// Correct answers.
  final int correct;

  /// Questions served.
  final int total;

  /// Questions with a graded answer.
  final int answered;

  /// Short answers awaiting self-grading.
  final int ungraded;

  /// Questions without any answer (counted as wrong in [fraction]).
  int get unanswered => total - answered - ungraded;

  /// 0..1 (`correct / total`), 0 for an empty exam.
  double get fraction => total == 0 ? 0 : correct / total;

  /// Whole percent.
  int get percent => (fraction * 100).round();

  @override
  bool operator ==(Object other) =>
      other is ExamScore &&
      other.correct == correct &&
      other.total == total &&
      other.answered == answered &&
      other.ungraded == ungraded;

  @override
  int get hashCode => Object.hash(correct, total, answered, ungraded);

  @override
  String toString() => 'ExamScore($correct/$total, ungraded: $ungraded)';
}

/// Grades every answer of [questions] (re-grading option questions from the
/// selection) and returns the answers with `isCorrect` set plus the score.
/// Unanswered questions get no answer entry and count as wrong.
({List<QuestionAnswer> answers, ExamScore score}) scoreExam(
  List<Question> questions,
  Iterable<QuestionAnswer> answers,
) {
  final byId = {for (final a in answers) a.questionId: a};
  final graded = <QuestionAnswer>[];
  var correct = 0, answered = 0, ungraded = 0;
  for (final q in questions) {
    final a = byId[q.id];
    if (a == null) continue;
    final grade = gradeAnswer(q, a);
    final hasInput =
        a.selectedIndices.isNotEmpty ||
        (a.textAnswer?.trim().isNotEmpty ?? false) ||
        a.isCorrect != null;
    if (grade == null) {
      if (hasInput && q.type == QuestionType.shortAnswer) ungraded++;
      graded.add(a.copyWith(isCorrect: null));
      continue;
    }
    answered++;
    if (grade) correct++;
    graded.add(a.copyWith(isCorrect: grade));
  }
  return (
    answers: graded,
    score: ExamScore(
      correct: correct,
      total: questions.length,
      answered: answered,
      ungraded: ungraded,
    ),
  );
}

/// Time left in a timed attempt at [now] (never negative); null when
/// untimed.
Duration? examTimeRemaining(QuizAttempt attempt, DateTime now) {
  final limit = attempt.timeLimitSeconds;
  if (limit == null) return null;
  final end = attempt.startedAt.add(Duration(seconds: limit));
  final left = end.difference(now);
  return left.isNegative ? Duration.zero : left;
}

/// Whether a timed attempt ran out of time at [now].
bool isExamExpired(QuizAttempt attempt, DateTime now) =>
    examTimeRemaining(attempt, now) == Duration.zero;

/// Seconds spent between start and [completedAt], capped at the time limit.
int examDurationSeconds(QuizAttempt attempt, DateTime completedAt) {
  final spent = math.max(
    0,
    completedAt.difference(attempt.startedAt).inSeconds,
  );
  final limit = attempt.timeLimitSeconds;
  return limit == null ? spent : math.min(spent, limit);
}

/// [attempt] completed at [now] with graded [answers]: score, completion
/// time and duration set (ready for `AttemptRepository.save`).
QuizAttempt completeExam(
  QuizAttempt attempt, {
  required List<Question> questions,
  required Iterable<QuestionAnswer> answers,
  required DateTime now,
}) {
  final result = scoreExam(questions, answers);
  return attempt.copyWith(
    answers: result.answers,
    score: result.score.correct.toDouble(),
    total: questions.length,
    completedAt: now,
    durationSeconds: examDurationSeconds(attempt, now),
  );
}
