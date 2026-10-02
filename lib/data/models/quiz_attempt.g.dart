// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'quiz_attempt.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_QuestionAnswer _$QuestionAnswerFromJson(Map<String, dynamic> json) =>
    _QuestionAnswer(
      questionId: json['question_id'] as String,
      selectedIndices:
          (json['selected_indices'] as List<dynamic>?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          const <int>[],
      textAnswer: json['text_answer'] as String?,
      isCorrect: json['is_correct'] as bool?,
    );

Map<String, dynamic> _$QuestionAnswerToJson(_QuestionAnswer instance) =>
    <String, dynamic>{
      'question_id': instance.questionId,
      'selected_indices': instance.selectedIndices,
      'text_answer': instance.textAnswer,
      'is_correct': instance.isCorrect,
    };

_QuizAttempt _$QuizAttemptFromJson(Map<String, dynamic> json) => _QuizAttempt(
  id: json['id'] as String,
  quizId: json['quiz_id'] as String,
  ownerId: json['owner_id'] as String,
  answers:
      (json['answers'] as List<dynamic>?)
          ?.map((e) => QuestionAnswer.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const <QuestionAnswer>[],
  score: (json['score'] as num?)?.toDouble() ?? 0,
  total: (json['total'] as num?)?.toInt() ?? 0,
  startedAt: DateTime.parse(json['started_at'] as String),
  completedAt: json['completed_at'] == null
      ? null
      : DateTime.parse(json['completed_at'] as String),
  createdAt: DateTime.parse(json['created_at'] as String),
  updatedAt: DateTime.parse(json['updated_at'] as String),
  deletedAt: json['deleted_at'] == null
      ? null
      : DateTime.parse(json['deleted_at'] as String),
);

Map<String, dynamic> _$QuizAttemptToJson(_QuizAttempt instance) =>
    <String, dynamic>{
      'id': instance.id,
      'quiz_id': instance.quizId,
      'owner_id': instance.ownerId,
      'answers': instance.answers.map((e) => e.toJson()).toList(),
      'score': instance.score,
      'total': instance.total,
      'started_at': instance.startedAt.toIso8601String(),
      'completed_at': instance.completedAt?.toIso8601String(),
      'created_at': instance.createdAt.toIso8601String(),
      'updated_at': instance.updatedAt.toIso8601String(),
      'deleted_at': instance.deletedAt?.toIso8601String(),
    };
