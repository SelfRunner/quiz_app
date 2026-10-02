// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'note.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$Note {

 String get id; String get subjectId; String get ownerId; String get title; String get contentMd;/// Normalized tags (see `normalizeTags`), owner's values (Wave 3).
 List<String> get tags;/// Pinned to the top of lists (owner's value, Wave 3).
 bool get pinned; DateTime get createdAt; DateTime get updatedAt; DateTime? get deletedAt;
/// Create a copy of Note
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NoteCopyWith<Note> get copyWith => _$NoteCopyWithImpl<Note>(this as Note, _$identity);

  /// Serializes this Note to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as Note;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Note&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.subjectId, _this.subjectId) || other.subjectId == _this.subjectId)&&(identical(other.ownerId, _this.ownerId) || other.ownerId == _this.ownerId)&&(identical(other.title, _this.title) || other.title == _this.title)&&(identical(other.contentMd, _this.contentMd) || other.contentMd == _this.contentMd)&&const DeepCollectionEquality().equals(other.tags, _this.tags)&&(identical(other.pinned, _this.pinned) || other.pinned == _this.pinned)&&(identical(other.createdAt, _this.createdAt) || other.createdAt == _this.createdAt)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt)&&(identical(other.deletedAt, _this.deletedAt) || other.deletedAt == _this.deletedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as Note;
  return Object.hash(runtimeType,_this.id,_this.subjectId,_this.ownerId,_this.title,_this.contentMd,const DeepCollectionEquality().hash(_this.tags),_this.pinned,_this.createdAt,_this.updatedAt,_this.deletedAt);
}

@override
String toString() {
  final _this = this as Note;
  return 'Note(id: ${_this.id}, subjectId: ${_this.subjectId}, ownerId: ${_this.ownerId}, title: ${_this.title}, contentMd: ${_this.contentMd}, tags: ${_this.tags}, pinned: ${_this.pinned}, createdAt: ${_this.createdAt}, updatedAt: ${_this.updatedAt}, deletedAt: ${_this.deletedAt})';
}


}

/// @nodoc
abstract mixin class $NoteCopyWith<$Res>  {
  factory $NoteCopyWith(Note value, $Res Function(Note) _then) = _$NoteCopyWithImpl;
@useResult
$Res call({
 String id, String subjectId, String ownerId, String title, String contentMd, List<String> tags, bool pinned, DateTime createdAt, DateTime updatedAt, DateTime? deletedAt
});




}
/// @nodoc
class _$NoteCopyWithImpl<$Res>
    implements $NoteCopyWith<$Res> {
  _$NoteCopyWithImpl(this._self, this._then);

  final Note _self;
  final $Res Function(Note) _then;

/// Create a copy of Note
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? subjectId = null,Object? ownerId = null,Object? title = null,Object? contentMd = null,Object? tags = null,Object? pinned = null,Object? createdAt = null,Object? updatedAt = null,Object? deletedAt = freezed,}) {
  return _then(Note(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,subjectId: null == subjectId ? _self.subjectId : subjectId // ignore: cast_nullable_to_non_nullable
as String,ownerId: null == ownerId ? _self.ownerId : ownerId // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,contentMd: null == contentMd ? _self.contentMd : contentMd // ignore: cast_nullable_to_non_nullable
as String,tags: null == tags ? _self.tags : tags // ignore: cast_nullable_to_non_nullable
as List<String>,pinned: null == pinned ? _self.pinned : pinned // ignore: cast_nullable_to_non_nullable
as bool,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,deletedAt: freezed == deletedAt ? _self.deletedAt : deletedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

}


/// Adds pattern-matching-related methods to [Note].
extension NotePatterns on Note {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Note value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Note() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Note value)  $default,){
final _that = this;
switch (_that) {
case _Note():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Note value)?  $default,){
final _that = this;
switch (_that) {
case _Note() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String subjectId,  String ownerId,  String title,  String contentMd,  List<String> tags,  bool pinned,  DateTime createdAt,  DateTime updatedAt,  DateTime? deletedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Note() when $default != null:
return $default(_that.id,_that.subjectId,_that.ownerId,_that.title,_that.contentMd,_that.tags,_that.pinned,_that.createdAt,_that.updatedAt,_that.deletedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String subjectId,  String ownerId,  String title,  String contentMd,  List<String> tags,  bool pinned,  DateTime createdAt,  DateTime updatedAt,  DateTime? deletedAt)  $default,) {final _that = this;
switch (_that) {
case _Note():
return $default(_that.id,_that.subjectId,_that.ownerId,_that.title,_that.contentMd,_that.tags,_that.pinned,_that.createdAt,_that.updatedAt,_that.deletedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String subjectId,  String ownerId,  String title,  String contentMd,  List<String> tags,  bool pinned,  DateTime createdAt,  DateTime updatedAt,  DateTime? deletedAt)?  $default,) {final _that = this;
switch (_that) {
case _Note() when $default != null:
return $default(_that.id,_that.subjectId,_that.ownerId,_that.title,_that.contentMd,_that.tags,_that.pinned,_that.createdAt,_that.updatedAt,_that.deletedAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Note implements Note {
  const _Note({required this.id, required this.subjectId, required this.ownerId, required this.title, this.contentMd = '',  List<String> tags = const <String>[], this.pinned = false, required this.createdAt, required this.updatedAt, this.deletedAt}): _tags = tags;
  factory _Note.fromJson(Map<String, dynamic> json) => _$NoteFromJson(json);

@override final  String id;
@override final  String subjectId;
@override final  String ownerId;
@override final  String title;
@override@JsonKey() final  String contentMd;
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

/// Create a copy of Note
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$NoteCopyWith<_Note> get copyWith => __$NoteCopyWithImpl<_Note>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$NoteToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _Note&&(identical(other.id, id) || other.id == id)&&(identical(other.subjectId, subjectId) || other.subjectId == subjectId)&&(identical(other.ownerId, ownerId) || other.ownerId == ownerId)&&(identical(other.title, title) || other.title == title)&&(identical(other.contentMd, contentMd) || other.contentMd == contentMd)&&const DeepCollectionEquality().equals(other.tags, _tags)&&(identical(other.pinned, pinned) || other.pinned == pinned)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.deletedAt, deletedAt) || other.deletedAt == deletedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,id,subjectId,ownerId,title,contentMd,const DeepCollectionEquality().hash(_tags),pinned,createdAt,updatedAt,deletedAt);
}

@override
String toString() {
    return 'Note(id: $id, subjectId: $subjectId, ownerId: $ownerId, title: $title, contentMd: $contentMd, tags: $tags, pinned: $pinned, createdAt: $createdAt, updatedAt: $updatedAt, deletedAt: $deletedAt)';
}


}

/// @nodoc
abstract mixin class _$NoteCopyWith<$Res> implements $NoteCopyWith<$Res> {
  factory _$NoteCopyWith(_Note value, $Res Function(_Note) _then) = __$NoteCopyWithImpl;
@override @useResult
$Res call({
 String id, String subjectId, String ownerId, String title, String contentMd, List<String> tags, bool pinned, DateTime createdAt, DateTime updatedAt, DateTime? deletedAt
});




}
/// @nodoc
class __$NoteCopyWithImpl<$Res>
    implements _$NoteCopyWith<$Res> {
  __$NoteCopyWithImpl(this._self, this._then);

  final _Note _self;
  final $Res Function(_Note) _then;

/// Create a copy of Note
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? subjectId = null,Object? ownerId = null,Object? title = null,Object? contentMd = null,Object? tags = null,Object? pinned = null,Object? createdAt = null,Object? updatedAt = null,Object? deletedAt = freezed,}) {
  return _then(_Note(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,subjectId: null == subjectId ? _self.subjectId : subjectId // ignore: cast_nullable_to_non_nullable
as String,ownerId: null == ownerId ? _self.ownerId : ownerId // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,contentMd: null == contentMd ? _self.contentMd : contentMd // ignore: cast_nullable_to_non_nullable
as String,tags: null == tags ? _self._tags : tags // ignore: cast_nullable_to_non_nullable
as List<String>,pinned: null == pinned ? _self.pinned : pinned // ignore: cast_nullable_to_non_nullable
as bool,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,deletedAt: freezed == deletedAt ? _self.deletedAt : deletedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}

// dart format on
