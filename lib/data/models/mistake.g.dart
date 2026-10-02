// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mistake.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Mistake _$MistakeFromJson(Map<String, dynamic> json) => _Mistake(
  id: json['id'] as String,
  ownerId: json['owner_id'] as String,
  quizId: json['quiz_id'] as String,
  questionId: json['question_id'] as String,
  wrongCount: (json['wrong_count'] as num?)?.toInt() ?? 0,
  correctStreak: (json['correct_streak'] as num?)?.toInt() ?? 0,
  lastWrongAt: json['last_wrong_at'] == null
      ? null
      : DateTime.parse(json['last_wrong_at'] as String),
  resolvedAt: json['resolved_at'] == null
      ? null
      : DateTime.parse(json['resolved_at'] as String),
  createdAt: DateTime.parse(json['created_at'] as String),
  updatedAt: DateTime.parse(json['updated_at'] as String),
  deletedAt: json['deleted_at'] == null
      ? null
      : DateTime.parse(json['deleted_at'] as String),
);

Map<String, dynamic> _$MistakeToJson(_Mistake instance) => <String, dynamic>{
  'id': instance.id,
  'owner_id': instance.ownerId,
  'quiz_id': instance.quizId,
  'question_id': instance.questionId,
  'wrong_count': instance.wrongCount,
  'correct_streak': instance.correctStreak,
  'last_wrong_at': instance.lastWrongAt?.toIso8601String(),
  'resolved_at': instance.resolvedAt?.toIso8601String(),
  'created_at': instance.createdAt.toIso8601String(),
  'updated_at': instance.updatedAt.toIso8601String(),
  'deleted_at': instance.deletedAt?.toIso8601String(),
};
