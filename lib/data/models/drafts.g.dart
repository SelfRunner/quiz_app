// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'drafts.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_QuestionDraft _$QuestionDraftFromJson(Map<String, dynamic> json) =>
    _QuestionDraft(
      type: $enumDecode(_$QuestionTypeEnumMap, json['type']),
      prompt: json['prompt'] as String,
      options:
          (json['options'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const <String>[],
      correctIndices:
          (json['correct_indices'] as List<dynamic>?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          const <int>[],
      answerText: json['answer_text'] as String?,
      explanation: json['explanation'] as String?,
    );

Map<String, dynamic> _$QuestionDraftToJson(_QuestionDraft instance) =>
    <String, dynamic>{
      'type': _$QuestionTypeEnumMap[instance.type]!,
      'prompt': instance.prompt,
      'options': instance.options,
      'correct_indices': instance.correctIndices,
      'answer_text': instance.answerText,
      'explanation': instance.explanation,
    };

const _$QuestionTypeEnumMap = {
  QuestionType.mcqSingle: 'mcq_single',
  QuestionType.mcqMulti: 'mcq_multi',
  QuestionType.trueFalse: 'true_false',
  QuestionType.shortAnswer: 'short_answer',
};

_QuizDraft _$QuizDraftFromJson(Map<String, dynamic> json) => _QuizDraft(
  title: json['title'] as String,
  description: json['description'] as String?,
  questions:
      (json['questions'] as List<dynamic>?)
          ?.map((e) => QuestionDraft.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const <QuestionDraft>[],
);

Map<String, dynamic> _$QuizDraftToJson(_QuizDraft instance) =>
    <String, dynamic>{
      'title': instance.title,
      'description': instance.description,
      'questions': instance.questions.map((e) => e.toJson()).toList(),
    };

_NoteDraft _$NoteDraftFromJson(Map<String, dynamic> json) => _NoteDraft(
  title: json['title'] as String,
  contentMarkdown: json['content_markdown'] as String,
);

Map<String, dynamic> _$NoteDraftToJson(_NoteDraft instance) =>
    <String, dynamic>{
      'title': instance.title,
      'content_markdown': instance.contentMarkdown,
    };
