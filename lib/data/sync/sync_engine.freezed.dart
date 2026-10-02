// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'sync_engine.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$SyncStatus {

 SyncState get state; DateTime? get lastSyncedAt;/// Number of ops waiting in the outbox.
 int get pendingOps;/// Message of the last error when [state] is [SyncState.error].
 String? get error;/// Outbox ops that keep failing with transient (5xx/unknown) errors and
/// have reached the attempt threshold. They are never dropped; sync keeps
/// retrying them with capped backoff.
 int get stuckOps;/// Changes the server rejected permanently whose content is kept locally
/// (`DefaultSyncEngine.rejectedChanges`) until dismissed.
 int get rejectedChanges;/// The server database is older than the app (schema-cache errors such
/// as PGRST204/PGRST205: missing column/table/function). Affected
/// changes stay queued (never dropped) and affected tables are retried
/// on every sync until the migration has been applied. [state] is
/// [SyncState.error] and [error] contains [serverOutdatedMessage].
 bool get serverOutdated;/// Tables (or Storage buckets / RPCs) the server could not serve in the
/// last cycle because its schema is out of date, sorted. Other tables
/// still sync normally.
 List<String> get unavailableTables;
/// Create a copy of SyncStatus
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SyncStatusCopyWith<SyncStatus> get copyWith => _$SyncStatusCopyWithImpl<SyncStatus>(this as SyncStatus, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SyncStatus;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SyncStatus&&(identical(other.state, _this.state) || other.state == _this.state)&&(identical(other.lastSyncedAt, _this.lastSyncedAt) || other.lastSyncedAt == _this.lastSyncedAt)&&(identical(other.pendingOps, _this.pendingOps) || other.pendingOps == _this.pendingOps)&&(identical(other.error, _this.error) || other.error == _this.error)&&(identical(other.stuckOps, _this.stuckOps) || other.stuckOps == _this.stuckOps)&&(identical(other.rejectedChanges, _this.rejectedChanges) || other.rejectedChanges == _this.rejectedChanges)&&(identical(other.serverOutdated, _this.serverOutdated) || other.serverOutdated == _this.serverOutdated)&&const DeepCollectionEquality().equals(other.unavailableTables, _this.unavailableTables));
}


@override
int get hashCode {
  final _this = this as SyncStatus;
  return Object.hash(runtimeType,_this.state,_this.lastSyncedAt,_this.pendingOps,_this.error,_this.stuckOps,_this.rejectedChanges,_this.serverOutdated,const DeepCollectionEquality().hash(_this.unavailableTables));
}

@override
String toString() {
  final _this = this as SyncStatus;
  return 'SyncStatus(state: ${_this.state}, lastSyncedAt: ${_this.lastSyncedAt}, pendingOps: ${_this.pendingOps}, error: ${_this.error}, stuckOps: ${_this.stuckOps}, rejectedChanges: ${_this.rejectedChanges}, serverOutdated: ${_this.serverOutdated}, unavailableTables: ${_this.unavailableTables})';
}


}

/// @nodoc
abstract mixin class $SyncStatusCopyWith<$Res>  {
  factory $SyncStatusCopyWith(SyncStatus value, $Res Function(SyncStatus) _then) = _$SyncStatusCopyWithImpl;
@useResult
$Res call({
 SyncState state, DateTime? lastSyncedAt, int pendingOps, String? error, int stuckOps, int rejectedChanges, bool serverOutdated, List<String> unavailableTables
});




}
/// @nodoc
class _$SyncStatusCopyWithImpl<$Res>
    implements $SyncStatusCopyWith<$Res> {
  _$SyncStatusCopyWithImpl(this._self, this._then);

  final SyncStatus _self;
  final $Res Function(SyncStatus) _then;

/// Create a copy of SyncStatus
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? state = null,Object? lastSyncedAt = freezed,Object? pendingOps = null,Object? error = freezed,Object? stuckOps = null,Object? rejectedChanges = null,Object? serverOutdated = null,Object? unavailableTables = null,}) {
  return _then(SyncStatus(
state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as SyncState,lastSyncedAt: freezed == lastSyncedAt ? _self.lastSyncedAt : lastSyncedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,pendingOps: null == pendingOps ? _self.pendingOps : pendingOps // ignore: cast_nullable_to_non_nullable
as int,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,stuckOps: null == stuckOps ? _self.stuckOps : stuckOps // ignore: cast_nullable_to_non_nullable
as int,rejectedChanges: null == rejectedChanges ? _self.rejectedChanges : rejectedChanges // ignore: cast_nullable_to_non_nullable
as int,serverOutdated: null == serverOutdated ? _self.serverOutdated : serverOutdated // ignore: cast_nullable_to_non_nullable
as bool,unavailableTables: null == unavailableTables ? _self.unavailableTables : unavailableTables // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}

}


/// Adds pattern-matching-related methods to [SyncStatus].
extension SyncStatusPatterns on SyncStatus {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SyncStatus value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SyncStatus() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SyncStatus value)  $default,){
final _that = this;
switch (_that) {
case _SyncStatus():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SyncStatus value)?  $default,){
final _that = this;
switch (_that) {
case _SyncStatus() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( SyncState state,  DateTime? lastSyncedAt,  int pendingOps,  String? error,  int stuckOps,  int rejectedChanges,  bool serverOutdated,  List<String> unavailableTables)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SyncStatus() when $default != null:
return $default(_that.state,_that.lastSyncedAt,_that.pendingOps,_that.error,_that.stuckOps,_that.rejectedChanges,_that.serverOutdated,_that.unavailableTables);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( SyncState state,  DateTime? lastSyncedAt,  int pendingOps,  String? error,  int stuckOps,  int rejectedChanges,  bool serverOutdated,  List<String> unavailableTables)  $default,) {final _that = this;
switch (_that) {
case _SyncStatus():
return $default(_that.state,_that.lastSyncedAt,_that.pendingOps,_that.error,_that.stuckOps,_that.rejectedChanges,_that.serverOutdated,_that.unavailableTables);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( SyncState state,  DateTime? lastSyncedAt,  int pendingOps,  String? error,  int stuckOps,  int rejectedChanges,  bool serverOutdated,  List<String> unavailableTables)?  $default,) {final _that = this;
switch (_that) {
case _SyncStatus() when $default != null:
return $default(_that.state,_that.lastSyncedAt,_that.pendingOps,_that.error,_that.stuckOps,_that.rejectedChanges,_that.serverOutdated,_that.unavailableTables);case _:
  return null;

}
}

}

/// @nodoc


class _SyncStatus implements SyncStatus {
  const _SyncStatus({this.state = SyncState.idle, this.lastSyncedAt, this.pendingOps = 0, this.error, this.stuckOps = 0, this.rejectedChanges = 0, this.serverOutdated = false,  List<String> unavailableTables = const <String>[]}): _unavailableTables = unavailableTables;
  

@override@JsonKey() final  SyncState state;
@override final  DateTime? lastSyncedAt;
/// Number of ops waiting in the outbox.
@override@JsonKey() final  int pendingOps;
/// Message of the last error when [state] is [SyncState.error].
@override final  String? error;
/// Outbox ops that keep failing with transient (5xx/unknown) errors and
/// have reached the attempt threshold. They are never dropped; sync keeps
/// retrying them with capped backoff.
@override@JsonKey() final  int stuckOps;
/// Changes the server rejected permanently whose content is kept locally
/// (`DefaultSyncEngine.rejectedChanges`) until dismissed.
@override@JsonKey() final  int rejectedChanges;
/// The server database is older than the app (schema-cache errors such
/// as PGRST204/PGRST205: missing column/table/function). Affected
/// changes stay queued (never dropped) and affected tables are retried
/// on every sync until the migration has been applied. [state] is
/// [SyncState.error] and [error] contains [serverOutdatedMessage].
@override@JsonKey() final  bool serverOutdated;
/// Tables (or Storage buckets / RPCs) the server could not serve in the
/// last cycle because its schema is out of date, sorted. Other tables
/// still sync normally.
 final  List<String> _unavailableTables;
/// Tables (or Storage buckets / RPCs) the server could not serve in the
/// last cycle because its schema is out of date, sorted. Other tables
/// still sync normally.
@override@JsonKey() List<String> get unavailableTables {
  if (_unavailableTables is EqualUnmodifiableListView) return _unavailableTables;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_unavailableTables);
}


/// Create a copy of SyncStatus
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SyncStatusCopyWith<_SyncStatus> get copyWith => __$SyncStatusCopyWithImpl<_SyncStatus>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SyncStatus&&(identical(other.state, state) || other.state == state)&&(identical(other.lastSyncedAt, lastSyncedAt) || other.lastSyncedAt == lastSyncedAt)&&(identical(other.pendingOps, pendingOps) || other.pendingOps == pendingOps)&&(identical(other.error, error) || other.error == error)&&(identical(other.stuckOps, stuckOps) || other.stuckOps == stuckOps)&&(identical(other.rejectedChanges, rejectedChanges) || other.rejectedChanges == rejectedChanges)&&(identical(other.serverOutdated, serverOutdated) || other.serverOutdated == serverOutdated)&&const DeepCollectionEquality().equals(other.unavailableTables, _unavailableTables));
}


@override
int get hashCode {
    return Object.hash(runtimeType,state,lastSyncedAt,pendingOps,error,stuckOps,rejectedChanges,serverOutdated,const DeepCollectionEquality().hash(_unavailableTables));
}

@override
String toString() {
    return 'SyncStatus(state: $state, lastSyncedAt: $lastSyncedAt, pendingOps: $pendingOps, error: $error, stuckOps: $stuckOps, rejectedChanges: $rejectedChanges, serverOutdated: $serverOutdated, unavailableTables: $unavailableTables)';
}


}

/// @nodoc
abstract mixin class _$SyncStatusCopyWith<$Res> implements $SyncStatusCopyWith<$Res> {
  factory _$SyncStatusCopyWith(_SyncStatus value, $Res Function(_SyncStatus) _then) = __$SyncStatusCopyWithImpl;
@override @useResult
$Res call({
 SyncState state, DateTime? lastSyncedAt, int pendingOps, String? error, int stuckOps, int rejectedChanges, bool serverOutdated, List<String> unavailableTables
});




}
/// @nodoc
class __$SyncStatusCopyWithImpl<$Res>
    implements _$SyncStatusCopyWith<$Res> {
  __$SyncStatusCopyWithImpl(this._self, this._then);

  final _SyncStatus _self;
  final $Res Function(_SyncStatus) _then;

/// Create a copy of SyncStatus
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? state = null,Object? lastSyncedAt = freezed,Object? pendingOps = null,Object? error = freezed,Object? stuckOps = null,Object? rejectedChanges = null,Object? serverOutdated = null,Object? unavailableTables = null,}) {
  return _then(_SyncStatus(
state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as SyncState,lastSyncedAt: freezed == lastSyncedAt ? _self.lastSyncedAt : lastSyncedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,pendingOps: null == pendingOps ? _self.pendingOps : pendingOps // ignore: cast_nullable_to_non_nullable
as int,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,stuckOps: null == stuckOps ? _self.stuckOps : stuckOps // ignore: cast_nullable_to_non_nullable
as int,rejectedChanges: null == rejectedChanges ? _self.rejectedChanges : rejectedChanges // ignore: cast_nullable_to_non_nullable
as int,serverOutdated: null == serverOutdated ? _self.serverOutdated : serverOutdated // ignore: cast_nullable_to_non_nullable
as bool,unavailableTables: null == unavailableTables ? _self._unavailableTables : unavailableTables // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}


}

// dart format on
