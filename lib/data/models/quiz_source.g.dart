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
);

Map<String, dynamic> _$QuizSourceToJson(_QuizSource instance) =>
    <String, dynamic>{
      'context_text': instance.contextText,
      'youtube_url': instance.youtubeUrl,
      'provider': instance.provider,
      'model': instance.model,
    };
