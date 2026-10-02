// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'quiz_source.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_QuizSource _$QuizSourceFromJson(Map<String, dynamic> json) => _QuizSource(
  contextText: json['context_text'] as String?,
  youtubeUrl: json['youtube_url'] as String?,
  provider: json['provider'] as String?,
  model: json['model'] as String?,
  notes:
      (json['notes'] as List<dynamic>?)
          ?.map((e) => QuizSourceRef.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const <QuizSourceRef>[],
  attachments:
      (json['attachments'] as List<dynamic>?)
          ?.map((e) => QuizSourceRef.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const <QuizSourceRef>[],
);

Map<String, dynamic> _$QuizSourceToJson(_QuizSource instance) =>
    <String, dynamic>{
      'context_text': instance.contextText,
      'youtube_url': instance.youtubeUrl,
      'provider': instance.provider,
      'model': instance.model,
      'notes': instance.notes.map((e) => e.toJson()).toList(),
      'attachments': instance.attachments.map((e) => e.toJson()).toList(),
    };

_QuizSourceRef _$QuizSourceRefFromJson(Map<String, dynamic> json) =>
    _QuizSourceRef(id: json['id'] as String, name: json['name'] as String);

Map<String, dynamic> _$QuizSourceRefToJson(_QuizSourceRef instance) =>
    <String, dynamic>{'id': instance.id, 'name': instance.name};
