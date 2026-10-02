// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'attachment.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Attachment _$AttachmentFromJson(Map<String, dynamic> json) => _Attachment(
  id: json['id'] as String,
  subjectId: json['subject_id'] as String,
  ownerId: json['owner_id'] as String,
  name: json['name'] as String,
  mimeType: json['mime_type'] as String?,
  sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
  kind:
      $enumDecodeNullable(
        _$AttachmentKindEnumMap,
        json['kind'],
        unknownValue: AttachmentKind.other,
      ) ??
      AttachmentKind.other,
  storagePath: json['storage_path'] as String,
  extractedText: json['extracted_text'] as String?,
  createdAt: DateTime.parse(json['created_at'] as String),
  updatedAt: DateTime.parse(json['updated_at'] as String),
  deletedAt: json['deleted_at'] == null
      ? null
      : DateTime.parse(json['deleted_at'] as String),
);

Map<String, dynamic> _$AttachmentToJson(_Attachment instance) =>
    <String, dynamic>{
      'id': instance.id,
      'subject_id': instance.subjectId,
      'owner_id': instance.ownerId,
      'name': instance.name,
      'mime_type': instance.mimeType,
      'size_bytes': instance.sizeBytes,
      'kind': _$AttachmentKindEnumMap[instance.kind]!,
      'storage_path': instance.storagePath,
      'extracted_text': instance.extractedText,
      'created_at': instance.createdAt.toIso8601String(),
      'updated_at': instance.updatedAt.toIso8601String(),
      'deleted_at': instance.deletedAt?.toIso8601String(),
    };

const _$AttachmentKindEnumMap = {
  AttachmentKind.pdf: 'pdf',
  AttachmentKind.image: 'image',
  AttachmentKind.text: 'text',
  AttachmentKind.docx: 'docx',
  AttachmentKind.audio: 'audio',
  AttachmentKind.video: 'video',
  AttachmentKind.other: 'other',
};
