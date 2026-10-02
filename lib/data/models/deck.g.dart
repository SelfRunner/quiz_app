// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'deck.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Flashcard _$FlashcardFromJson(Map<String, dynamic> json) => _Flashcard(
  id: json['id'] as String,
  front: json['front'] as String,
  back: json['back'] as String,
  hint: json['hint'] as String?,
);

Map<String, dynamic> _$FlashcardToJson(_Flashcard instance) =>
    <String, dynamic>{
      'id': instance.id,
      'front': instance.front,
      'back': instance.back,
      'hint': instance.hint,
    };

_Deck _$DeckFromJson(Map<String, dynamic> json) => _Deck(
  id: json['id'] as String,
  subjectId: json['subject_id'] as String,
  noteId: json['note_id'] as String?,
  ownerId: json['owner_id'] as String,
  title: json['title'] as String,
  description: json['description'] as String?,
  source: json['source'] == null
      ? null
      : QuizSource.fromJson(json['source'] as Map<String, dynamic>),
  cards:
      (json['cards'] as List<dynamic>?)
          ?.map((e) => Flashcard.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const <Flashcard>[],
  createdAt: DateTime.parse(json['created_at'] as String),
  updatedAt: DateTime.parse(json['updated_at'] as String),
  deletedAt: json['deleted_at'] == null
      ? null
      : DateTime.parse(json['deleted_at'] as String),
);

Map<String, dynamic> _$DeckToJson(_Deck instance) => <String, dynamic>{
  'id': instance.id,
  'subject_id': instance.subjectId,
  'note_id': instance.noteId,
  'owner_id': instance.ownerId,
  'title': instance.title,
  'description': instance.description,
  'source': instance.source?.toJson(),
  'cards': instance.cards.map((e) => e.toJson()).toList(),
  'created_at': instance.createdAt.toIso8601String(),
  'updated_at': instance.updatedAt.toIso8601String(),
  'deleted_at': instance.deletedAt?.toIso8601String(),
};
