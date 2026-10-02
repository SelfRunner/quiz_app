// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'card_review.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_CardReview _$CardReviewFromJson(Map<String, dynamic> json) => _CardReview(
  id: json['id'] as String,
  ownerId: json['owner_id'] as String,
  deckId: json['deck_id'] as String,
  cardId: json['card_id'] as String,
  state:
      $enumDecodeNullable(
        _$CardStateEnumMap,
        json['state'],
        unknownValue: CardState.newCard,
      ) ??
      CardState.newCard,
  dueAt: DateTime.parse(json['due_at'] as String),
  stability: (json['stability'] as num?)?.toDouble() ?? 0,
  difficulty: (json['difficulty'] as num?)?.toDouble() ?? 0,
  elapsedDays: (json['elapsed_days'] as num?)?.toInt() ?? 0,
  scheduledDays: (json['scheduled_days'] as num?)?.toInt() ?? 0,
  reps: (json['reps'] as num?)?.toInt() ?? 0,
  lapses: (json['lapses'] as num?)?.toInt() ?? 0,
  lastReviewAt: json['last_review_at'] == null
      ? null
      : DateTime.parse(json['last_review_at'] as String),
  createdAt: DateTime.parse(json['created_at'] as String),
  updatedAt: DateTime.parse(json['updated_at'] as String),
  deletedAt: json['deleted_at'] == null
      ? null
      : DateTime.parse(json['deleted_at'] as String),
);

Map<String, dynamic> _$CardReviewToJson(_CardReview instance) =>
    <String, dynamic>{
      'id': instance.id,
      'owner_id': instance.ownerId,
      'deck_id': instance.deckId,
      'card_id': instance.cardId,
      'state': _$CardStateEnumMap[instance.state]!,
      'due_at': instance.dueAt.toIso8601String(),
      'stability': instance.stability,
      'difficulty': instance.difficulty,
      'elapsed_days': instance.elapsedDays,
      'scheduled_days': instance.scheduledDays,
      'reps': instance.reps,
      'lapses': instance.lapses,
      'last_review_at': instance.lastReviewAt?.toIso8601String(),
      'created_at': instance.createdAt.toIso8601String(),
      'updated_at': instance.updatedAt.toIso8601String(),
      'deleted_at': instance.deletedAt?.toIso8601String(),
    };

const _$CardStateEnumMap = {
  CardState.newCard: 0,
  CardState.learning: 1,
  CardState.review: 2,
  CardState.relearning: 3,
};
