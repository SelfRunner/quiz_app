import 'package:freezed_annotation/freezed_annotation.dart';

import 'syncable.dart';

part 'quiz_attempt.freezed.dart';
part 'quiz_attempt.g.dart';

/// The user's answer to one question within an attempt.
@freezed
abstract class QuestionAnswer with _$QuestionAnswer {
  const factory QuestionAnswer({
    required String questionId,

    /// Selected option indices (MCQ / true-false).
    @Default(<int>[]) List<int> selectedIndices,

    /// Typed answer (short answer); optional for self-graded flashcards.
    String? textAnswer,

    /// Auto-graded for option questions; self-graded for short answer.
    /// Null = not answered / not graded yet.
    bool? isCorrect,
  }) = _QuestionAnswer;

  factory QuestionAnswer.fromJson(Map<String, dynamic> json) =>
      _$QuestionAnswerFromJson(json);
}

/// Row of `public.quiz_attempts`. Visible only to [ownerId] (the user who took
/// the quiz). Also works for quizzes shared with the user.
@freezed
abstract class QuizAttempt with _$QuizAttempt implements Syncable {
  const factory QuizAttempt({
    required String id,
    required String quizId,

    /// The attempting user (column `owner_id`).
    required String ownerId,
    @Default(<QuestionAnswer>[]) List<QuestionAnswer> answers,

    /// Number of correct answers (double to allow partial credit later).
    @Default(0) double score,

    /// Number of questions in the quiz at attempt time.
    @Default(0) int total,
    required DateTime startedAt,

    /// Null while in progress.
    DateTime? completedAt,
    required DateTime createdAt,
    required DateTime updatedAt,
    DateTime? deletedAt,
  }) = _QuizAttempt;

  factory QuizAttempt.fromJson(Map<String, dynamic> json) =>
      _$QuizAttemptFromJson(json);
}
