import 'package:freezed_annotation/freezed_annotation.dart';

part 'question.freezed.dart';
part 'question.g.dart';

/// Question kinds. JSON values are the wire format used in Supabase
/// (`quizzes.questions` jsonb) and in AI output.
enum QuestionType {
  /// Exactly one correct option. `correctIndices.length == 1`.
  @JsonValue('mcq_single')
  mcqSingle,

  /// One or more correct options. `correctIndices.length >= 1`.
  @JsonValue('mcq_multi')
  mcqMulti,

  /// `options == ['True', 'False']`, `correctIndices` is `[0]` or `[1]`.
  @JsonValue('true_false')
  trueFalse,

  /// Free text / flashcard, self-graded. `options` and `correctIndices` are
  /// empty; the expected answer is in `answerText`.
  @JsonValue('short_answer')
  shortAnswer;

  /// Wire value (matches the `@JsonValue`).
  String get wireName => switch (this) {
    QuestionType.mcqSingle => 'mcq_single',
    QuestionType.mcqMulti => 'mcq_multi',
    QuestionType.trueFalse => 'true_false',
    QuestionType.shortAnswer => 'short_answer',
  };

  bool get hasOptions => this != QuestionType.shortAnswer;
}

/// A question embedded in `Quiz.questions`.
@freezed
abstract class Question with _$Question {
  const factory Question({
    /// Client-generated UUID; stable so attempts can reference it.
    required String id,
    required QuestionType type,
    required String prompt,
    @Default(<String>[]) List<String> options,

    /// Zero-based indices into [options].
    @Default(<int>[]) List<int> correctIndices,

    /// Expected answer for [QuestionType.shortAnswer] (optional otherwise).
    String? answerText,
    String? explanation,
  }) = _Question;

  factory Question.fromJson(Map<String, dynamic> json) =>
      _$QuestionFromJson(json);
}
