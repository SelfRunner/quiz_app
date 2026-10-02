// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'outbox_op.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_OutboxOp _$OutboxOpFromJson(Map<String, dynamic> json) => _OutboxOp(
  id: json['id'] as String,
  table: json['table'] as String,
  op: $enumDecode(_$OutboxOpTypeEnumMap, json['op']),
  rowId: json['row_id'] as String,
  payload: json['payload'] as Map<String, dynamic>?,
  createdAt: DateTime.parse(json['created_at'] as String),
  attempts: (json['attempts'] as num?)?.toInt() ?? 0,
  lastError: json['last_error'] as String?,
);

Map<String, dynamic> _$OutboxOpToJson(_OutboxOp instance) => <String, dynamic>{
  'id': instance.id,
  'table': instance.table,
  'op': _$OutboxOpTypeEnumMap[instance.op]!,
  'row_id': instance.rowId,
  'payload': instance.payload,
  'created_at': instance.createdAt.toIso8601String(),
  'attempts': instance.attempts,
  'last_error': instance.lastError,
};

const _$OutboxOpTypeEnumMap = {
  OutboxOpType.upsert: 'upsert',
  OutboxOpType.delete: 'delete',
  OutboxOpType.uploadImage: 'upload_image',
  OutboxOpType.deleteImage: 'delete_image',
  OutboxOpType.uploadAttachment: 'upload_attachment',
  OutboxOpType.deleteAttachment: 'delete_attachment',
};
