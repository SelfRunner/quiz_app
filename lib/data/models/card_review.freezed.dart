// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'card_review.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$CardReview {

 String get id;/// The reviewing user.
 String get ownerId; String get deckId;/// `Flashcard.id` within the deck.
 String get cardId;@JsonKey(unknownEnumValue: CardState.newCard) CardState get state; DateTime get dueAt; double get stability; double get difficulty; int get elapsedDays; int get scheduledDays; int get reps; int get lapses; DateTime? get lastReviewAt; DateTime get createdAt; DateTime get updatedAt; DateTime? get deletedAt;
/// Create a copy of CardReview
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CardReviewCopyWith<CardReview> get copyWith => _$CardReviewCopyWithImpl<CardReview>(this as CardReview, _$identity);

  /// Serializes this CardReview to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as CardReview;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CardReview&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.ownerId, _this.ownerId) || other.ownerId == _this.ownerId)&&(identical(other.deckId, _this.deckId) || other.deckId == _this.deckId)&&(identical(other.cardId, _this.cardId) || other.cardId == _this.cardId)&&(identical(other.state, _this.state) || other.state == _this.state)&&(identical(other.dueAt, _this.dueAt) || other.dueAt == _this.dueAt)&&(identical(other.stability, _this.stability) || other.stability == _this.stability)&&(identical(other.difficulty, _this.difficulty) || other.difficulty == _this.difficulty)&&(identical(other.elapsedDays, _this.elapsedDays) || other.elapsedDays == _this.elapsedDays)&&(identical(other.scheduledDays, _this.scheduledDays) || other.scheduledDays == _this.scheduledDays)&&(identical(other.reps, _this.reps) || other.reps == _this.reps)&&(identical(other.lapses, _this.lapses) || other.lapses == _this.lapses)&&(identical(other.lastReviewAt, _this.lastReviewAt) || other.lastReviewAt == _this.lastReviewAt)&&(identical(other.createdAt, _this.createdAt) || other.createdAt == _this.createdAt)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt)&&(identical(other.deletedAt, _this.deletedAt) || other.deletedAt == _this.deletedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as CardReview;
  return Object.hash(runtimeType,_this.id,_this.ownerId,_this.deckId,_this.cardId,_this.state,_this.dueAt,_this.stability,_this.difficulty,_this.elapsedDays,_this.scheduledDays,_this.reps,_this.lapses,_this.lastReviewAt,_this.createdAt,_this.updatedAt,_this.deletedAt);
}

@override
String toString() {
  final _this = this as CardReview;
  return 'CardReview(id: ${_this.id}, ownerId: ${_this.ownerId}, deckId: ${_this.deckId}, cardId: ${_this.cardId}, state: ${_this.state}, dueAt: ${_this.dueAt}, stability: ${_this.stability}, difficulty: ${_this.difficulty}, elapsedDays: ${_this.elapsedDays}, scheduledDays: ${_this.scheduledDays}, reps: ${_this.reps}, lapses: ${_this.lapses}, lastReviewAt: ${_this.lastReviewAt}, createdAt: ${_this.createdAt}, updatedAt: ${_this.updatedAt}, deletedAt: ${_this.deletedAt})';
}


}

/// @nodoc
abstract mixin class $CardReviewCopyWith<$Res>  {
  factory $CardReviewCopyWith(CardReview value, $Res Function(CardReview) _then) = _$CardReviewCopyWithImpl;
@useResult
$Res call({
 String id, String ownerId, String deckId, String cardId,@JsonKey(unknownEnumValue: CardState.newCard) CardState state, DateTime dueAt, double stability, double difficulty, int elapsedDays, int scheduledDays, int reps, int lapses, DateTime? lastReviewAt, DateTime createdAt, DateTime updatedAt, DateTime? deletedAt
});




}
/// @nodoc
class _$CardReviewCopyWithImpl<$Res>
    implements $CardReviewCopyWith<$Res> {
  _$CardReviewCopyWithImpl(this._self, this._then);

  final CardReview _self;
  final $Res Function(CardReview) _then;

/// Create a copy of CardReview
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? ownerId = null,Object? deckId = null,Object? cardId = null,Object? state = null,Object? dueAt = null,Object? stability = null,Object? difficulty = null,Object? elapsedDays = null,Object? scheduledDays = null,Object? reps = null,Object? lapses = null,Object? lastReviewAt = freezed,Object? createdAt = null,Object? updatedAt = null,Object? deletedAt = freezed,}) {
  return _then(CardReview(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,ownerId: null == ownerId ? _self.ownerId : ownerId // ignore: cast_nullable_to_non_nullable
as String,deckId: null == deckId ? _self.deckId : deckId // ignore: cast_nullable_to_non_nullable
as String,cardId: null == cardId ? _self.cardId : cardId // ignore: cast_nullable_to_non_nullable
as String,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as CardState,dueAt: null == dueAt ? _self.dueAt : dueAt // ignore: cast_nullable_to_non_nullable
as DateTime,stability: null == stability ? _self.stability : stability // ignore: cast_nullable_to_non_nullable
as double,difficulty: null == difficulty ? _self.difficulty : difficulty // ignore: cast_nullable_to_non_nullable
as double,elapsedDays: null == elapsedDays ? _self.elapsedDays : elapsedDays // ignore: cast_nullable_to_non_nullable
as int,scheduledDays: null == scheduledDays ? _self.scheduledDays : scheduledDays // ignore: cast_nullable_to_non_nullable
as int,reps: null == reps ? _self.reps : reps // ignore: cast_nullable_to_non_nullable
as int,lapses: null == lapses ? _self.lapses : lapses // ignore: cast_nullable_to_non_nullable
as int,lastReviewAt: freezed == lastReviewAt ? _self.lastReviewAt : lastReviewAt // ignore: cast_nullable_to_non_nullable
as DateTime?,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,deletedAt: freezed == deletedAt ? _self.deletedAt : deletedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

}


/// Adds pattern-matching-related methods to [CardReview].
extension CardReviewPatterns on CardReview {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _CardReview value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _CardReview() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _CardReview value)  $default,){
final _that = this;
switch (_that) {
case _CardReview():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _CardReview value)?  $default,){
final _that = this;
switch (_that) {
case _CardReview() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String ownerId,  String deckId,  String cardId, @JsonKey(unknownEnumValue: CardState.newCard)  CardState state,  DateTime dueAt,  double stability,  double difficulty,  int elapsedDays,  int scheduledDays,  int reps,  int lapses,  DateTime? lastReviewAt,  DateTime createdAt,  DateTime updatedAt,  DateTime? deletedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _CardReview() when $default != null:
return $default(_that.id,_that.ownerId,_that.deckId,_that.cardId,_that.state,_that.dueAt,_that.stability,_that.difficulty,_that.elapsedDays,_that.scheduledDays,_that.reps,_that.lapses,_that.lastReviewAt,_that.createdAt,_that.updatedAt,_that.deletedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String ownerId,  String deckId,  String cardId, @JsonKey(unknownEnumValue: CardState.newCard)  CardState state,  DateTime dueAt,  double stability,  double difficulty,  int elapsedDays,  int scheduledDays,  int reps,  int lapses,  DateTime? lastReviewAt,  DateTime createdAt,  DateTime updatedAt,  DateTime? deletedAt)  $default,) {final _that = this;
switch (_that) {
case _CardReview():
return $default(_that.id,_that.ownerId,_that.deckId,_that.cardId,_that.state,_that.dueAt,_that.stability,_that.difficulty,_that.elapsedDays,_that.scheduledDays,_that.reps,_that.lapses,_that.lastReviewAt,_that.createdAt,_that.updatedAt,_that.deletedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String ownerId,  String deckId,  String cardId, @JsonKey(unknownEnumValue: CardState.newCard)  CardState state,  DateTime dueAt,  double stability,  double difficulty,  int elapsedDays,  int scheduledDays,  int reps,  int lapses,  DateTime? lastReviewAt,  DateTime createdAt,  DateTime updatedAt,  DateTime? deletedAt)?  $default,) {final _that = this;
switch (_that) {
case _CardReview() when $default != null:
return $default(_that.id,_that.ownerId,_that.deckId,_that.cardId,_that.state,_that.dueAt,_that.stability,_that.difficulty,_that.elapsedDays,_that.scheduledDays,_that.reps,_that.lapses,_that.lastReviewAt,_that.createdAt,_that.updatedAt,_that.deletedAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _CardReview extends CardReview {
  const _CardReview({required this.id, required this.ownerId, required this.deckId, required this.cardId, @JsonKey(unknownEnumValue: CardState.newCard) this.state = CardState.newCard, required this.dueAt, this.stability = 0, this.difficulty = 0, this.elapsedDays = 0, this.scheduledDays = 0, this.reps = 0, this.lapses = 0, this.lastReviewAt, required this.createdAt, required this.updatedAt, this.deletedAt}): super._();
  factory _CardReview.fromJson(Map<String, dynamic> json) => _$CardReviewFromJson(json);

@override final  String id;
/// The reviewing user.
@override final  String ownerId;
@override final  String deckId;
/// `Flashcard.id` within the deck.
@override final  String cardId;
@override@JsonKey(unknownEnumValue: CardState.newCard) final  CardState state;
@override final  DateTime dueAt;
@override@JsonKey() final  double stability;
@override@JsonKey() final  double difficulty;
@override@JsonKey() final  int elapsedDays;
@override@JsonKey() final  int scheduledDays;
@override@JsonKey() final  int reps;
@override@JsonKey() final  int lapses;
@override final  DateTime? lastReviewAt;
@override final  DateTime createdAt;
@override final  DateTime updatedAt;
@override final  DateTime? deletedAt;

/// Create a copy of CardReview
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$CardReviewCopyWith<_CardReview> get copyWith => __$CardReviewCopyWithImpl<_CardReview>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$CardReviewToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _CardReview&&(identical(other.id, id) || other.id == id)&&(identical(other.ownerId, ownerId) || other.ownerId == ownerId)&&(identical(other.deckId, deckId) || other.deckId == deckId)&&(identical(other.cardId, cardId) || other.cardId == cardId)&&(identical(other.state, state) || other.state == state)&&(identical(other.dueAt, dueAt) || other.dueAt == dueAt)&&(identical(other.stability, stability) || other.stability == stability)&&(identical(other.difficulty, difficulty) || other.difficulty == difficulty)&&(identical(other.elapsedDays, elapsedDays) || other.elapsedDays == elapsedDays)&&(identical(other.scheduledDays, scheduledDays) || other.scheduledDays == scheduledDays)&&(identical(other.reps, reps) || other.reps == reps)&&(identical(other.lapses, lapses) || other.lapses == lapses)&&(identical(other.lastReviewAt, lastReviewAt) || other.lastReviewAt == lastReviewAt)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.deletedAt, deletedAt) || other.deletedAt == deletedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,id,ownerId,deckId,cardId,state,dueAt,stability,difficulty,elapsedDays,scheduledDays,reps,lapses,lastReviewAt,createdAt,updatedAt,deletedAt);
}

@override
String toString() {
    return 'CardReview(id: $id, ownerId: $ownerId, deckId: $deckId, cardId: $cardId, state: $state, dueAt: $dueAt, stability: $stability, difficulty: $difficulty, elapsedDays: $elapsedDays, scheduledDays: $scheduledDays, reps: $reps, lapses: $lapses, lastReviewAt: $lastReviewAt, createdAt: $createdAt, updatedAt: $updatedAt, deletedAt: $deletedAt)';
}


}

/// @nodoc
abstract mixin class _$CardReviewCopyWith<$Res> implements $CardReviewCopyWith<$Res> {
  factory _$CardReviewCopyWith(_CardReview value, $Res Function(_CardReview) _then) = __$CardReviewCopyWithImpl;
@override @useResult
$Res call({
 String id, String ownerId, String deckId, String cardId,@JsonKey(unknownEnumValue: CardState.newCard) CardState state, DateTime dueAt, double stability, double difficulty, int elapsedDays, int scheduledDays, int reps, int lapses, DateTime? lastReviewAt, DateTime createdAt, DateTime updatedAt, DateTime? deletedAt
});




}
/// @nodoc
class __$CardReviewCopyWithImpl<$Res>
    implements _$CardReviewCopyWith<$Res> {
  __$CardReviewCopyWithImpl(this._self, this._then);

  final _CardReview _self;
  final $Res Function(_CardReview) _then;

/// Create a copy of CardReview
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? ownerId = null,Object? deckId = null,Object? cardId = null,Object? state = null,Object? dueAt = null,Object? stability = null,Object? difficulty = null,Object? elapsedDays = null,Object? scheduledDays = null,Object? reps = null,Object? lapses = null,Object? lastReviewAt = freezed,Object? createdAt = null,Object? updatedAt = null,Object? deletedAt = freezed,}) {
  return _then(_CardReview(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,ownerId: null == ownerId ? _self.ownerId : ownerId // ignore: cast_nullable_to_non_nullable
as String,deckId: null == deckId ? _self.deckId : deckId // ignore: cast_nullable_to_non_nullable
as String,cardId: null == cardId ? _self.cardId : cardId // ignore: cast_nullable_to_non_nullable
as String,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as CardState,dueAt: null == dueAt ? _self.dueAt : dueAt // ignore: cast_nullable_to_non_nullable
as DateTime,stability: null == stability ? _self.stability : stability // ignore: cast_nullable_to_non_nullable
as double,difficulty: null == difficulty ? _self.difficulty : difficulty // ignore: cast_nullable_to_non_nullable
as double,elapsedDays: null == elapsedDays ? _self.elapsedDays : elapsedDays // ignore: cast_nullable_to_non_nullable
as int,scheduledDays: null == scheduledDays ? _self.scheduledDays : scheduledDays // ignore: cast_nullable_to_non_nullable
as int,reps: null == reps ? _self.reps : reps // ignore: cast_nullable_to_non_nullable
as int,lapses: null == lapses ? _self.lapses : lapses // ignore: cast_nullable_to_non_nullable
as int,lastReviewAt: freezed == lastReviewAt ? _self.lastReviewAt : lastReviewAt // ignore: cast_nullable_to_non_nullable
as DateTime?,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,deletedAt: freezed == deletedAt ? _self.deletedAt : deletedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}

// dart format on
