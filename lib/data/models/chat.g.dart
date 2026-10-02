// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chat.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Chat _$ChatFromJson(Map<String, dynamic> json) => _Chat(
  id: json['id'] as String,
  ownerId: json['owner_id'] as String,
  scopeType:
      $enumDecodeNullable(
        _$ChatScopeTypeEnumMap,
        json['scope_type'],
        unknownValue: ChatScopeType.general,
      ) ??
      ChatScopeType.general,
  scopeId: json['scope_id'] as String?,
  title: json['title'] as String? ?? '',
  provider: json['provider'] as String?,
  model: json['model'] as String?,
  createdAt: DateTime.parse(json['created_at'] as String),
  updatedAt: DateTime.parse(json['updated_at'] as String),
  deletedAt: json['deleted_at'] == null
      ? null
      : DateTime.parse(json['deleted_at'] as String),
);

Map<String, dynamic> _$ChatToJson(_Chat instance) => <String, dynamic>{
  'id': instance.id,
  'owner_id': instance.ownerId,
  'scope_type': _$ChatScopeTypeEnumMap[instance.scopeType]!,
  'scope_id': instance.scopeId,
  'title': instance.title,
  'provider': instance.provider,
  'model': instance.model,
  'created_at': instance.createdAt.toIso8601String(),
  'updated_at': instance.updatedAt.toIso8601String(),
  'deleted_at': instance.deletedAt?.toIso8601String(),
};

const _$ChatScopeTypeEnumMap = {
  ChatScopeType.subject: 'subject',
  ChatScopeType.note: 'note',
  ChatScopeType.attachment: 'attachment',
  ChatScopeType.general: 'general',
};

_ChatCitation _$ChatCitationFromJson(Map<String, dynamic> json) =>
    _ChatCitation(
      type: json['type'] as String,
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      snippet: json['snippet'] as String?,
    );

Map<String, dynamic> _$ChatCitationToJson(_ChatCitation instance) =>
    <String, dynamic>{
      'type': instance.type,
      'id': instance.id,
      'title': instance.title,
      'snippet': instance.snippet,
    };

_ChatMessage _$ChatMessageFromJson(Map<String, dynamic> json) => _ChatMessage(
  id: json['id'] as String,
  chatId: json['chat_id'] as String,
  ownerId: json['owner_id'] as String,
  role: $enumDecode(
    _$ChatRoleEnumMap,
    json['role'],
    unknownValue: ChatRole.system,
  ),
  content: json['content'] as String? ?? '',
  citations:
      (json['citations'] as List<dynamic>?)
          ?.map((e) => ChatCitation.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const <ChatCitation>[],
  createdAt: DateTime.parse(json['created_at'] as String),
  updatedAt: DateTime.parse(json['updated_at'] as String),
  deletedAt: json['deleted_at'] == null
      ? null
      : DateTime.parse(json['deleted_at'] as String),
);

Map<String, dynamic> _$ChatMessageToJson(_ChatMessage instance) =>
    <String, dynamic>{
      'id': instance.id,
      'chat_id': instance.chatId,
      'owner_id': instance.ownerId,
      'role': _$ChatRoleEnumMap[instance.role]!,
      'content': instance.content,
      'citations': instance.citations.map((e) => e.toJson()).toList(),
      'created_at': instance.createdAt.toIso8601String(),
      'updated_at': instance.updatedAt.toIso8601String(),
      'deleted_at': instance.deletedAt?.toIso8601String(),
    };

const _$ChatRoleEnumMap = {
  ChatRole.user: 'user',
  ChatRole.assistant: 'assistant',
  ChatRole.system: 'system',
};
