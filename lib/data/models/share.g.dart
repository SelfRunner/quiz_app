// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'share.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Share _$ShareFromJson(Map<String, dynamic> json) => _Share(
  id: json['id'] as String,
  ownerId: json['owner_id'] as String,
  recipientId: json['recipient_id'] as String,
  resourceType: $enumDecode(_$ShareResourceTypeEnumMap, json['resource_type']),
  resourceId: json['resource_id'] as String,
  createdAt: DateTime.parse(json['created_at'] as String),
  recipient: json['recipient'] == null
      ? null
      : Profile.fromJson(json['recipient'] as Map<String, dynamic>),
  owner: json['owner'] == null
      ? null
      : Profile.fromJson(json['owner'] as Map<String, dynamic>),
  resourceTitle: json['resource_title'] as String?,
);

Map<String, dynamic> _$ShareToJson(_Share instance) => <String, dynamic>{
  'id': instance.id,
  'owner_id': instance.ownerId,
  'recipient_id': instance.recipientId,
  'resource_type': _$ShareResourceTypeEnumMap[instance.resourceType]!,
  'resource_id': instance.resourceId,
  'created_at': instance.createdAt.toIso8601String(),
};

const _$ShareResourceTypeEnumMap = {
  ShareResourceType.subject: 'subject',
  ShareResourceType.note: 'note',
  ShareResourceType.quiz: 'quiz',
};
