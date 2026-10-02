// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'mistake.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$Mistake {

 String get id; String get ownerId; String get quizId;/// `Question.id` within the quiz.
 String get questionId; int get wrongCount; int get correctStreak; DateTime? get lastWrongAt;/// Set when mastered; null = still in the Mistakes set.
 DateTime? get resolvedAt; DateTime get createdAt; DateTime get updatedAt; DateTime? get deletedAt;
/// Create a copy of Mistake
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MistakeCopyWith<Mistake> get copyWith => _$MistakeCopyWithImpl<Mistake>(this as Mistake, _$identity);

  /// Serializes this Mistake to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as Mistake;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Mistake&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.ownerId, _this.ownerId) || other.ownerId == _this.ownerId)&&(identical(other.quizId, _this.quizId) || other.quizId == _this.quizId)&&(identical(other.questionId, _this.questionId) || other.questionId == _this.questionId)&&(identical(other.wrongCount, _this.wrongCount) || other.wrongCount == _this.wrongCount)&&(identical(other.correctStreak, _this.correctStreak) || other.correctStreak == _this.correctStreak)&&(identical(other.lastWrongAt, _this.lastWrongAt) || other.lastWrongAt == _this.lastWrongAt)&&(identical(other.resolvedAt, _this.resolvedAt) || other.resolvedAt == _this.resolvedAt)&&(identical(other.createdAt, _this.createdAt) || other.createdAt == _this.createdAt)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt)&&(identical(other.deletedAt, _this.deletedAt) || other.deletedAt == _this.deletedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as Mistake;
  return Object.hash(runtimeType,_this.id,_this.ownerId,_this.quizId,_this.questionId,_this.wrongCount,_this.correctStreak,_this.lastWrongAt,_this.resolvedAt,_this.createdAt,_this.updatedAt,_this.deletedAt);
}

@override
String toString() {
  final _this = this as Mistake;
  return 'Mistake(id: ${_this.id}, ownerId: ${_this.ownerId}, quizId: ${_this.quizId}, questionId: ${_this.questionId}, wrongCount: ${_this.wrongCount}, correctStreak: ${_this.correctStreak}, lastWrongAt: ${_this.lastWrongAt}, resolvedAt: ${_this.resolvedAt}, createdAt: ${_this.createdAt}, updatedAt: ${_this.updatedAt}, deletedAt: ${_this.deletedAt})';
}


}

/// @nodoc
abstract mixin class $MistakeCopyWith<$Res>  {
  factory $MistakeCopyWith(Mistake value, $Res Function(Mistake) _then) = _$MistakeCopyWithImpl;
@useResult
$Res call({
 String id, String ownerId, String quizId, String questionId, int wrongCount, int correctStreak, DateTime? lastWrongAt, DateTime? resolvedAt, DateTime createdAt, DateTime updatedAt, DateTime? deletedAt
});




}
/// @nodoc
class _$MistakeCopyWithImpl<$Res>
    implements $MistakeCopyWith<$Res> {
  _$MistakeCopyWithImpl(this._self, this._then);

  final Mistake _self;
  final $Res Function(Mistake) _then;

/// Create a copy of Mistake
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? ownerId = null,Object? quizId = null,Object? questionId = null,Object? wrongCount = null,Object? correctStreak = null,Object? lastWrongAt = freezed,Object? resolvedAt = freezed,Object? createdAt = null,Object? updatedAt = null,Object? deletedAt = freezed,}) {
  return _then(Mistake(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,ownerId: null == ownerId ? _self.ownerId : ownerId // ignore: cast_nullable_to_non_nullable
as String,quizId: null == quizId ? _self.quizId : quizId // ignore: cast_nullable_to_non_nullable
as String,questionId: null == questionId ? _self.questionId : questionId // ignore: cast_nullable_to_non_nullable
as String,wrongCount: null == wrongCount ? _self.wrongCount : wrongCount // ignore: cast_nullable_to_non_nullable
as int,correctStreak: null == correctStreak ? _self.correctStreak : correctStreak // ignore: cast_nullable_to_non_nullable
as int,lastWrongAt: freezed == lastWrongAt ? _self.lastWrongAt : lastWrongAt // ignore: cast_nullable_to_non_nullable
as DateTime?,resolvedAt: freezed == resolvedAt ? _self.resolvedAt : resolvedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,deletedAt: freezed == deletedAt ? _self.deletedAt : deletedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

}


/// Adds pattern-matching-related methods to [Mistake].
extension MistakePatterns on Mistake {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Mistake value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Mistake() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Mistake value)  $default,){
final _that = this;
switch (_that) {
case _Mistake():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Mistake value)?  $default,){
final _that = this;
switch (_that) {
case _Mistake() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String ownerId,  String quizId,  String questionId,  int wrongCount,  int correctStreak,  DateTime? lastWrongAt,  DateTime? resolvedAt,  DateTime createdAt,  DateTime updatedAt,  DateTime? deletedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Mistake() when $default != null:
return $default(_that.id,_that.ownerId,_that.quizId,_that.questionId,_that.wrongCount,_that.correctStreak,_that.lastWrongAt,_that.resolvedAt,_that.createdAt,_that.updatedAt,_that.deletedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String ownerId,  String quizId,  String questionId,  int wrongCount,  int correctStreak,  DateTime? lastWrongAt,  DateTime? resolvedAt,  DateTime createdAt,  DateTime updatedAt,  DateTime? deletedAt)  $default,) {final _that = this;
switch (_that) {
case _Mistake():
return $default(_that.id,_that.ownerId,_that.quizId,_that.questionId,_that.wrongCount,_that.correctStreak,_that.lastWrongAt,_that.resolvedAt,_that.createdAt,_that.updatedAt,_that.deletedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String ownerId,  String quizId,  String questionId,  int wrongCount,  int correctStreak,  DateTime? lastWrongAt,  DateTime? resolvedAt,  DateTime createdAt,  DateTime updatedAt,  DateTime? deletedAt)?  $default,) {final _that = this;
switch (_that) {
case _Mistake() when $default != null:
return $default(_that.id,_that.ownerId,_that.quizId,_that.questionId,_that.wrongCount,_that.correctStreak,_that.lastWrongAt,_that.resolvedAt,_that.createdAt,_that.updatedAt,_that.deletedAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Mistake extends Mistake {
  const _Mistake({required this.id, required this.ownerId, required this.quizId, required this.questionId, this.wrongCount = 0, this.correctStreak = 0, this.lastWrongAt, this.resolvedAt, required this.createdAt, required this.updatedAt, this.deletedAt}): super._();
  factory _Mistake.fromJson(Map<String, dynamic> json) => _$MistakeFromJson(json);

@override final  String id;
@override final  String ownerId;
@override final  String quizId;
/// `Question.id` within the quiz.
@override final  String questionId;
@override@JsonKey() final  int wrongCount;
@override@JsonKey() final  int correctStreak;
@override final  DateTime? lastWrongAt;
/// Set when mastered; null = still in the Mistakes set.
@override final  DateTime? resolvedAt;
@override final  DateTime createdAt;
@override final  DateTime updatedAt;
@override final  DateTime? deletedAt;

/// Create a copy of Mistake
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$MistakeCopyWith<_Mistake> get copyWith => __$MistakeCopyWithImpl<_Mistake>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$MistakeToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _Mistake&&(identical(other.id, id) || other.id == id)&&(identical(other.ownerId, ownerId) || other.ownerId == ownerId)&&(identical(other.quizId, quizId) || other.quizId == quizId)&&(identical(other.questionId, questionId) || other.questionId == questionId)&&(identical(other.wrongCount, wrongCount) || other.wrongCount == wrongCount)&&(identical(other.correctStreak, correctStreak) || other.correctStreak == correctStreak)&&(identical(other.lastWrongAt, lastWrongAt) || other.lastWrongAt == lastWrongAt)&&(identical(other.resolvedAt, resolvedAt) || other.resolvedAt == resolvedAt)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.deletedAt, deletedAt) || other.deletedAt == deletedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,id,ownerId,quizId,questionId,wrongCount,correctStreak,lastWrongAt,resolvedAt,createdAt,updatedAt,deletedAt);
}

@override
String toString() {
    return 'Mistake(id: $id, ownerId: $ownerId, quizId: $quizId, questionId: $questionId, wrongCount: $wrongCount, correctStreak: $correctStreak, lastWrongAt: $lastWrongAt, resolvedAt: $resolvedAt, createdAt: $createdAt, updatedAt: $updatedAt, deletedAt: $deletedAt)';
}


}

/// @nodoc
abstract mixin class _$MistakeCopyWith<$Res> implements $MistakeCopyWith<$Res> {
  factory _$MistakeCopyWith(_Mistake value, $Res Function(_Mistake) _then) = __$MistakeCopyWithImpl;
@override @useResult
$Res call({
 String id, String ownerId, String quizId, String questionId, int wrongCount, int correctStreak, DateTime? lastWrongAt, DateTime? resolvedAt, DateTime createdAt, DateTime updatedAt, DateTime? deletedAt
});




}
/// @nodoc
class __$MistakeCopyWithImpl<$Res>
    implements _$MistakeCopyWith<$Res> {
  __$MistakeCopyWithImpl(this._self, this._then);

  final _Mistake _self;
  final $Res Function(_Mistake) _then;

/// Create a copy of Mistake
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? ownerId = null,Object? quizId = null,Object? questionId = null,Object? wrongCount = null,Object? correctStreak = null,Object? lastWrongAt = freezed,Object? resolvedAt = freezed,Object? createdAt = null,Object? updatedAt = null,Object? deletedAt = freezed,}) {
  return _then(_Mistake(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,ownerId: null == ownerId ? _self.ownerId : ownerId // ignore: cast_nullable_to_non_nullable
as String,quizId: null == quizId ? _self.quizId : quizId // ignore: cast_nullable_to_non_nullable
as String,questionId: null == questionId ? _self.questionId : questionId // ignore: cast_nullable_to_non_nullable
as String,wrongCount: null == wrongCount ? _self.wrongCount : wrongCount // ignore: cast_nullable_to_non_nullable
as int,correctStreak: null == correctStreak ? _self.correctStreak : correctStreak // ignore: cast_nullable_to_non_nullable
as int,lastWrongAt: freezed == lastWrongAt ? _self.lastWrongAt : lastWrongAt // ignore: cast_nullable_to_non_nullable
as DateTime?,resolvedAt: freezed == resolvedAt ? _self.resolvedAt : resolvedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,deletedAt: freezed == deletedAt ? _self.deletedAt : deletedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}

// dart format on
