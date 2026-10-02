// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'question.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Question _$QuestionFromJson(Map<String, dynamic> json) => _Question(
  id: json['id'] as String,
  type: $enumDecode(_$QuestionTypeEnumMap, json['type']),
  prompt: json['prompt'] as String,
  options:
      (json['options'] as List<dynamic>?)?.map((e) => e as String).toList() ??
      const <String>[],
  correctIndices:
      (json['correct_indices'] as List<dynamic>?)
          ?.map((e) => (e as num).toInt())
          .toList() ??
      const <int>[],
  answerText: json['answer_text'] as String?,
  explanation: json['explanation'] as String?,
);

Map<String, dynamic> _$QuestionToJson(_Question instance) => <String, dynamic>{
  'id': instance.id,
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
