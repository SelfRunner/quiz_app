import 'package:freezed_annotation/freezed_annotation.dart';

import 'question.dart';

part 'drafts.freezed.dart';
part 'drafts.g.dart';

/// AI output for one question (no id yet). Same JSON shape as [Question]
/// minus `id`.
@freezed
abstract class QuestionDraft with _$QuestionDraft {
  const QuestionDraft._();

  const factory QuestionDraft({
    required QuestionType type,
    required String prompt,
    @Default(<String>[]) List<String> options,
    @Default(<int>[]) List<int> correctIndices,
    String? answerText,
    String? explanation,
  }) = _QuestionDraft;

  factory QuestionDraft.fromJson(Map<String, dynamic> json) =>
      _$QuestionDraftFromJson(json);

  Question toQuestion(String id) => Question(
    id: id,
    type: type,
    prompt: prompt,
    options: options,
    correctIndices: correctIndices,
    answerText: answerText,
    explanation: explanation,
  );
}

/// AI output contract for quiz generation. Validated against
/// [quizDraftJsonSchema]; editable in the preview before saving.
@freezed
abstract class QuizDraft with _$QuizDraft {
  const QuizDraft._();

  const factory QuizDraft({
    required String title,
    String? description,
    @Default(<QuestionDraft>[]) List<QuestionDraft> questions,
  }) = _QuizDraft;

  factory QuizDraft.fromJson(Map<String, dynamic> json) =>
      _$QuizDraftFromJson(json);

  /// Assigns fresh ids to every question.
  List<Question> toQuestions(String Function() newId) => [
    for (final q in questions) q.toQuestion(newId()),
  ];
}

/// AI output contract for note generation. Validated against
/// [noteDraftJsonSchema].
@freezed
abstract class NoteDraft with _$NoteDraft {
  const factory NoteDraft({
    required String title,
    required String contentMarkdown,
  }) = _NoteDraft;

  factory NoteDraft.fromJson(Map<String, dynamic> json) =>
      _$NoteDraftFromJson(json);
}

/// JSON Schema for [QuizDraft] structured output.
///
/// Written to be accepted by strict structured-output modes: every property is
/// listed in `required`, optional values are nullable via `type: [.., 'null']`,
/// and `additionalProperties` is false. Providers may need to adapt it (e.g.
/// Gemini `responseSchema` uses `nullable: true`).
const Map<String, Object?> quizDraftJsonSchema = {
  r'$schema': 'https://json-schema.org/draft/2020-12/schema',
  'title': 'QuizDraft',
  'type': 'object',
  'additionalProperties': false,
  'required': ['title', 'description', 'questions'],
  'properties': {
    'title': {'type': 'string', 'description': 'Short quiz title.'},
    'description': {
      'type': ['string', 'null'],
      'description': 'One-sentence summary of the quiz.',
    },
    'questions': {
      'type': 'array',
      'minItems': 1,
      'items': {
        'type': 'object',
        'additionalProperties': false,
        'required': [
          'type',
          'prompt',
          'options',
          'correct_indices',
          'answer_text',
          'explanation',
        ],
        'properties': {
          'type': {
            'type': 'string',
            'enum': ['mcq_single', 'mcq_multi', 'true_false', 'short_answer'],
          },
          'prompt': {'type': 'string', 'description': 'The question text.'},
          'options': {
            'type': 'array',
            'items': {'type': 'string'},
            'description':
                "Answer options. ['True','False'] for true_false; "
                'empty for short_answer.',
          },
          'correct_indices': {
            'type': 'array',
            'items': {'type': 'integer', 'minimum': 0},
            'description':
                'Zero-based indices of correct options; exactly '
                'one for mcq_single/true_false, one or more for mcq_multi, '
                'empty for short_answer.',
          },
          'answer_text': {
            'type': ['string', 'null'],
            'description': 'Expected answer for short_answer, else null.',
          },
          'explanation': {
            'type': ['string', 'null'],
            'description': 'Why the answer is correct.',
          },
        },
      },
    },
  },
};

/// JSON Schema for [NoteDraft] structured output.
const Map<String, Object?> noteDraftJsonSchema = {
  r'$schema': 'https://json-schema.org/draft/2020-12/schema',
  'title': 'NoteDraft',
  'type': 'object',
  'additionalProperties': false,
  'required': ['title', 'content_markdown'],
  'properties': {
    'title': {'type': 'string', 'description': 'Short note title.'},
    'content_markdown': {
      'type': 'string',
      'description': 'The note body in GitHub-flavored Markdown.',
    },
  },
};
