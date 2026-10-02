// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'outbox_op.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$OutboxOp {

 String get id;/// Table name (`SyncTables.*`) or storage bucket for image ops.
 String get table; OutboxOpType get op; String get rowId;/// Full row JSON for upserts; op-specific data otherwise.
 Map<String, dynamic>? get payload; DateTime get createdAt; int get attempts; String? get lastError;
/// Create a copy of OutboxOp
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$OutboxOpCopyWith<OutboxOp> get copyWith => _$OutboxOpCopyWithImpl<OutboxOp>(this as OutboxOp, _$identity);

  /// Serializes this OutboxOp to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as OutboxOp;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is OutboxOp&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.table, _this.table) || other.table == _this.table)&&(identical(other.op, _this.op) || other.op == _this.op)&&(identical(other.rowId, _this.rowId) || other.rowId == _this.rowId)&&const DeepCollectionEquality().equals(other.payload, _this.payload)&&(identical(other.createdAt, _this.createdAt) || other.createdAt == _this.createdAt)&&(identical(other.attempts, _this.attempts) || other.attempts == _this.attempts)&&(identical(other.lastError, _this.lastError) || other.lastError == _this.lastError));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as OutboxOp;
  return Object.hash(runtimeType,_this.id,_this.table,_this.op,_this.rowId,const DeepCollectionEquality().hash(_this.payload),_this.createdAt,_this.attempts,_this.lastError);
}

@override
String toString() {
  final _this = this as OutboxOp;
  return 'OutboxOp(id: ${_this.id}, table: ${_this.table}, op: ${_this.op}, rowId: ${_this.rowId}, payload: ${_this.payload}, createdAt: ${_this.createdAt}, attempts: ${_this.attempts}, lastError: ${_this.lastError})';
}


}

/// @nodoc
abstract mixin class $OutboxOpCopyWith<$Res>  {
  factory $OutboxOpCopyWith(OutboxOp value, $Res Function(OutboxOp) _then) = _$OutboxOpCopyWithImpl;
@useResult
$Res call({
 String id, String table, OutboxOpType op, String rowId, Map<String, dynamic>? payload, DateTime createdAt, int attempts, String? lastError
});




}
/// @nodoc
class _$OutboxOpCopyWithImpl<$Res>
    implements $OutboxOpCopyWith<$Res> {
  _$OutboxOpCopyWithImpl(this._self, this._then);

  final OutboxOp _self;
  final $Res Function(OutboxOp) _then;

/// Create a copy of OutboxOp
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? table = null,Object? op = null,Object? rowId = null,Object? payload = freezed,Object? createdAt = null,Object? attempts = null,Object? lastError = freezed,}) {
  return _then(OutboxOp(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,table: null == table ? _self.table : table // ignore: cast_nullable_to_non_nullable
as String,op: null == op ? _self.op : op // ignore: cast_nullable_to_non_nullable
as OutboxOpType,rowId: null == rowId ? _self.rowId : rowId // ignore: cast_nullable_to_non_nullable
as String,payload: freezed == payload ? _self.payload : payload // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>?,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,attempts: null == attempts ? _self.attempts : attempts // ignore: cast_nullable_to_non_nullable
as int,lastError: freezed == lastError ? _self.lastError : lastError // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [OutboxOp].
extension OutboxOpPatterns on OutboxOp {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _OutboxOp value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _OutboxOp() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _OutboxOp value)  $default,){
final _that = this;
switch (_that) {
case _OutboxOp():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _OutboxOp value)?  $default,){
final _that = this;
switch (_that) {
case _OutboxOp() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String table,  OutboxOpType op,  String rowId,  Map<String, dynamic>? payload,  DateTime createdAt,  int attempts,  String? lastError)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _OutboxOp() when $default != null:
return $default(_that.id,_that.table,_that.op,_that.rowId,_that.payload,_that.createdAt,_that.attempts,_that.lastError);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String table,  OutboxOpType op,  String rowId,  Map<String, dynamic>? payload,  DateTime createdAt,  int attempts,  String? lastError)  $default,) {final _that = this;
switch (_that) {
case _OutboxOp():
return $default(_that.id,_that.table,_that.op,_that.rowId,_that.payload,_that.createdAt,_that.attempts,_that.lastError);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String table,  OutboxOpType op,  String rowId,  Map<String, dynamic>? payload,  DateTime createdAt,  int attempts,  String? lastError)?  $default,) {final _that = this;
switch (_that) {
case _OutboxOp() when $default != null:
return $default(_that.id,_that.table,_that.op,_that.rowId,_that.payload,_that.createdAt,_that.attempts,_that.lastError);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _OutboxOp implements OutboxOp {
  const _OutboxOp({required this.id, required this.table, required this.op, required this.rowId,  Map<String, dynamic>? payload, required this.createdAt, this.attempts = 0, this.lastError}): _payload = payload;
  factory _OutboxOp.fromJson(Map<String, dynamic> json) => _$OutboxOpFromJson(json);

@override final  String id;
/// Table name (`SyncTables.*`) or storage bucket for image ops.
@override final  String table;
@override final  OutboxOpType op;
@override final  String rowId;
/// Full row JSON for upserts; op-specific data otherwise.
 final  Map<String, dynamic>? _payload;
/// Full row JSON for upserts; op-specific data otherwise.
@override Map<String, dynamic>? get payload {
  final value = _payload;
  if (value == null) return null;
  if (_payload is EqualUnmodifiableMapView) return _payload;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}

@override final  DateTime createdAt;
@override@JsonKey() final  int attempts;
@override final  String? lastError;

/// Create a copy of OutboxOp
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$OutboxOpCopyWith<_OutboxOp> get copyWith => __$OutboxOpCopyWithImpl<_OutboxOp>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$OutboxOpToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _OutboxOp&&(identical(other.id, id) || other.id == id)&&(identical(other.table, table) || other.table == table)&&(identical(other.op, op) || other.op == op)&&(identical(other.rowId, rowId) || other.rowId == rowId)&&const DeepCollectionEquality().equals(other.payload, _payload)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.attempts, attempts) || other.attempts == attempts)&&(identical(other.lastError, lastError) || other.lastError == lastError));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,id,table,op,rowId,const DeepCollectionEquality().hash(_payload),createdAt,attempts,lastError);
}

@override
String toString() {
    return 'OutboxOp(id: $id, table: $table, op: $op, rowId: $rowId, payload: $payload, createdAt: $createdAt, attempts: $attempts, lastError: $lastError)';
}


}

/// @nodoc
abstract mixin class _$OutboxOpCopyWith<$Res> implements $OutboxOpCopyWith<$Res> {
  factory _$OutboxOpCopyWith(_OutboxOp value, $Res Function(_OutboxOp) _then) = __$OutboxOpCopyWithImpl;
@override @useResult
$Res call({
 String id, String table, OutboxOpType op, String rowId, Map<String, dynamic>? payload, DateTime createdAt, int attempts, String? lastError
});




}
/// @nodoc
class __$OutboxOpCopyWithImpl<$Res>
    implements _$OutboxOpCopyWith<$Res> {
  __$OutboxOpCopyWithImpl(this._self, this._then);

  final _OutboxOp _self;
  final $Res Function(_OutboxOp) _then;

/// Create a copy of OutboxOp
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? table = null,Object? op = null,Object? rowId = null,Object? payload = freezed,Object? createdAt = null,Object? attempts = null,Object? lastError = freezed,}) {
  return _then(_OutboxOp(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,table: null == table ? _self.table : table // ignore: cast_nullable_to_non_nullable
as String,op: null == op ? _self.op : op // ignore: cast_nullable_to_non_nullable
as OutboxOpType,rowId: null == rowId ? _self.rowId : rowId // ignore: cast_nullable_to_non_nullable
as String,payload: freezed == payload ? _self._payload : payload // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>?,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,attempts: null == attempts ? _self.attempts : attempts // ignore: cast_nullable_to_non_nullable
as int,lastError: freezed == lastError ? _self.lastError : lastError // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
