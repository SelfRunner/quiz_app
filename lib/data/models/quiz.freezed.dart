// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'quiz.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$Quiz {

 String get id; String get subjectId; String? get noteId; String get ownerId; String get title; String? get description; QuizSource? get source; List<Question> get questions;/// Normalized tags (see `normalizeTags`), owner's values (Wave 3).
 List<String> get tags;/// Pinned to the top of lists (owner's value, Wave 3).
 bool get pinned; DateTime get createdAt; DateTime get updatedAt; DateTime? get deletedAt;
/// Create a copy of Quiz
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$QuizCopyWith<Quiz> get copyWith => _$QuizCopyWithImpl<Quiz>(this as Quiz, _$identity);

  /// Serializes this Quiz to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as Quiz;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Quiz&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.subjectId, _this.subjectId) || other.subjectId == _this.subjectId)&&(identical(other.noteId, _this.noteId) || other.noteId == _this.noteId)&&(identical(other.ownerId, _this.ownerId) || other.ownerId == _this.ownerId)&&(identical(other.title, _this.title) || other.title == _this.title)&&(identical(other.description, _this.description) || other.description == _this.description)&&(identical(other.source, _this.source) || other.source == _this.source)&&const DeepCollectionEquality().equals(other.questions, _this.questions)&&const DeepCollectionEquality().equals(other.tags, _this.tags)&&(identical(other.pinned, _this.pinned) || other.pinned == _this.pinned)&&(identical(other.createdAt, _this.createdAt) || other.createdAt == _this.createdAt)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt)&&(identical(other.deletedAt, _this.deletedAt) || other.deletedAt == _this.deletedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as Quiz;
  return Object.hash(runtimeType,_this.id,_this.subjectId,_this.noteId,_this.ownerId,_this.title,_this.description,_this.source,const DeepCollectionEquality().hash(_this.questions),const DeepCollectionEquality().hash(_this.tags),_this.pinned,_this.createdAt,_this.updatedAt,_this.deletedAt);
}

@override
String toString() {
  final _this = this as Quiz;
  return 'Quiz(id: ${_this.id}, subjectId: ${_this.subjectId}, noteId: ${_this.noteId}, ownerId: ${_this.ownerId}, title: ${_this.title}, description: ${_this.description}, source: ${_this.source}, questions: ${_this.questions}, tags: ${_this.tags}, pinned: ${_this.pinned}, createdAt: ${_this.createdAt}, updatedAt: ${_this.updatedAt}, deletedAt: ${_this.deletedAt})';
}


}

/// @nodoc
abstract mixin class $QuizCopyWith<$Res>  {
  factory $QuizCopyWith(Quiz value, $Res Function(Quiz) _then) = _$QuizCopyWithImpl;
@useResult
$Res call({
 String id, String subjectId, String? noteId, String ownerId, String title, String? description, QuizSource? source, List<Question> questions, List<String> tags, bool pinned, DateTime createdAt, DateTime updatedAt, DateTime? deletedAt
});


$QuizSourceCopyWith<$Res>? get source;

}
/// @nodoc
class _$QuizCopyWithImpl<$Res>
    implements $QuizCopyWith<$Res> {
  _$QuizCopyWithImpl(this._self, this._then);

  final Quiz _self;
  final $Res Function(Quiz) _then;

/// Create a copy of Quiz
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? subjectId = null,Object? noteId = freezed,Object? ownerId = null,Object? title = null,Object? description = freezed,Object? source = freezed,Object? questions = null,Object? tags = null,Object? pinned = null,Object? createdAt = null,Object? updatedAt = null,Object? deletedAt = freezed,}) {
  return _then(Quiz(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,subjectId: null == subjectId ? _self.subjectId : subjectId // ignore: cast_nullable_to_non_nullable
as String,noteId: freezed == noteId ? _self.noteId : noteId // ignore: cast_nullable_to_non_nullable
as String?,ownerId: null == ownerId ? _self.ownerId : ownerId // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,source: freezed == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as QuizSource?,questions: null == questions ? _self.questions : questions // ignore: cast_nullable_to_non_nullable
as List<Question>,tags: null == tags ? _self.tags : tags // ignore: cast_nullable_to_non_nullable
as List<String>,pinned: null == pinned ? _self.pinned : pinned // ignore: cast_nullable_to_non_nullable
as bool,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,deletedAt: freezed == deletedAt ? _self.deletedAt : deletedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}
/// Create a copy of Quiz
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$QuizSourceCopyWith<$Res>? get source {
    if (_self.source == null) {
    return null;
  }

  return $QuizSourceCopyWith<$Res>(_self.source!, (value) {
    return _then(_self.copyWith(source: value));
  });
}
}


/// Adds pattern-matching-related methods to [Quiz].
extension QuizPatterns on Quiz {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Quiz value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Quiz() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Quiz value)  $default,){
final _that = this;
switch (_that) {
case _Quiz():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Quiz value)?  $default,){
final _that = this;
switch (_that) {
case _Quiz() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String subjectId,  String? noteId,  String ownerId,  String title,  String? description,  QuizSource? source,  List<Question> questions,  List<String> tags,  bool pinned,  DateTime createdAt,  DateTime updatedAt,  DateTime? deletedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Quiz() when $default != null:
return $default(_that.id,_that.subjectId,_that.noteId,_that.ownerId,_that.title,_that.description,_that.source,_that.questions,_that.tags,_that.pinned,_that.createdAt,_that.updatedAt,_that.deletedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String subjectId,  String? noteId,  String ownerId,  String title,  String? description,  QuizSource? source,  List<Question> questions,  List<String> tags,  bool pinned,  DateTime createdAt,  DateTime updatedAt,  DateTime? deletedAt)  $default,) {final _that = this;
switch (_that) {
case _Quiz():
return $default(_that.id,_that.subjectId,_that.noteId,_that.ownerId,_that.title,_that.description,_that.source,_that.questions,_that.tags,_that.pinned,_that.createdAt,_that.updatedAt,_that.deletedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String subjectId,  String? noteId,  String ownerId,  String title,  String? description,  QuizSource? source,  List<Question> questions,  List<String> tags,  bool pinned,  DateTime createdAt,  DateTime updatedAt,  DateTime? deletedAt)?  $default,) {final _that = this;
switch (_that) {
case _Quiz() when $default != null:
return $default(_that.id,_that.subjectId,_that.noteId,_that.ownerId,_that.title,_that.description,_that.source,_that.questions,_that.tags,_that.pinned,_that.createdAt,_that.updatedAt,_that.deletedAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Quiz implements Quiz {
  const _Quiz({required this.id, required this.subjectId, this.noteId, required this.ownerId, required this.title, this.description, this.source,  List<Question> questions = const <Question>[],  List<String> tags = const <String>[], this.pinned = false, required this.createdAt, required this.updatedAt, this.deletedAt}): _questions = questions,_tags = tags;
  factory _Quiz.fromJson(Map<String, dynamic> json) => _$QuizFromJson(json);

@override final  String id;
@override final  String subjectId;
@override final  String? noteId;
@override final  String ownerId;
@override final  String title;
@override final  String? description;
@override final  QuizSource? source;
 final  List<Question> _questions;
@override@JsonKey() List<Question> get questions {
  if (_questions is EqualUnmodifiableListView) return _questions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_questions);
}

/// Normalized tags (see `normalizeTags`), owner's values (Wave 3).
 final  List<String> _tags;
/// Normalized tags (see `normalizeTags`), owner's values (Wave 3).
@override@JsonKey() List<String> get tags {
  if (_tags is EqualUnmodifiableListView) return _tags;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_tags);
}

/// Pinned to the top of lists (owner's value, Wave 3).
@override@JsonKey() final  bool pinned;
@override final  DateTime createdAt;
@override final  DateTime updatedAt;
@override final  DateTime? deletedAt;

/// Create a copy of Quiz
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$QuizCopyWith<_Quiz> get copyWith => __$QuizCopyWithImpl<_Quiz>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$QuizToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _Quiz&&(identical(other.id, id) || other.id == id)&&(identical(other.subjectId, subjectId) || other.subjectId == subjectId)&&(identical(other.noteId, noteId) || other.noteId == noteId)&&(identical(other.ownerId, ownerId) || other.ownerId == ownerId)&&(identical(other.title, title) || other.title == title)&&(identical(other.description, description) || other.description == description)&&(identical(other.source, source) || other.source == source)&&const DeepCollectionEquality().equals(other.questions, _questions)&&const DeepCollectionEquality().equals(other.tags, _tags)&&(identical(other.pinned, pinned) || other.pinned == pinned)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.deletedAt, deletedAt) || other.deletedAt == deletedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,id,subjectId,noteId,ownerId,title,description,source,const DeepCollectionEquality().hash(_questions),const DeepCollectionEquality().hash(_tags),pinned,createdAt,updatedAt,deletedAt);
}

@override
String toString() {
    return 'Quiz(id: $id, subjectId: $subjectId, noteId: $noteId, ownerId: $ownerId, title: $title, description: $description, source: $source, questions: $questions, tags: $tags, pinned: $pinned, createdAt: $createdAt, updatedAt: $updatedAt, deletedAt: $deletedAt)';
}


}

/// @nodoc
abstract mixin class _$QuizCopyWith<$Res> implements $QuizCopyWith<$Res> {
  factory _$QuizCopyWith(_Quiz value, $Res Function(_Quiz) _then) = __$QuizCopyWithImpl;
@override @useResult
$Res call({
 String id, String subjectId, String? noteId, String ownerId, String title, String? description, QuizSource? source, List<Question> questions, List<String> tags, bool pinned, DateTime createdAt, DateTime updatedAt, DateTime? deletedAt
});


@override $QuizSourceCopyWith<$Res>? get source;

}
/// @nodoc
class __$QuizCopyWithImpl<$Res>
    implements _$QuizCopyWith<$Res> {
  __$QuizCopyWithImpl(this._self, this._then);

  final _Quiz _self;
  final $Res Function(_Quiz) _then;

/// Create a copy of Quiz
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? subjectId = null,Object? noteId = freezed,Object? ownerId = null,Object? title = null,Object? description = freezed,Object? source = freezed,Object? questions = null,Object? tags = null,Object? pinned = null,Object? createdAt = null,Object? updatedAt = null,Object? deletedAt = freezed,}) {
  return _then(_Quiz(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,subjectId: null == subjectId ? _self.subjectId : subjectId // ignore: cast_nullable_to_non_nullable
as String,noteId: freezed == noteId ? _self.noteId : noteId // ignore: cast_nullable_to_non_nullable
as String?,ownerId: null == ownerId ? _self.ownerId : ownerId // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,source: freezed == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as QuizSource?,questions: null == questions ? _self._questions : questions // ignore: cast_nullable_to_non_nullable
as List<Question>,tags: null == tags ? _self._tags : tags // ignore: cast_nullable_to_non_nullable
as List<String>,pinned: null == pinned ? _self.pinned : pinned // ignore: cast_nullable_to_non_nullable
as bool,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,deletedAt: freezed == deletedAt ? _self.deletedAt : deletedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

/// Create a copy of Quiz
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$QuizSourceCopyWith<$Res>? get source {
    if (_self.source == null) {
    return null;
  }

  return $QuizSourceCopyWith<$Res>(_self.source!, (value) {
    return _then(_self.copyWith(source: value));
  });
}
}

// dart format on
