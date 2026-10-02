// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'share.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$Share {

 String get id; String get ownerId; String get recipientId; ShareResourceType get resourceType; String get resourceId; DateTime get createdAt;/// Joined profile of the recipient (select alias `recipient`), if loaded.
@JsonKey(includeToJson: false) Profile? get recipient;/// Joined profile of the owner (select alias `owner`), if loaded.
@JsonKey(includeToJson: false) Profile? get owner;/// Title of the shared resource, if the query joined it (UI convenience).
@JsonKey(includeToJson: false) String? get resourceTitle;
/// Create a copy of Share
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ShareCopyWith<Share> get copyWith => _$ShareCopyWithImpl<Share>(this as Share, _$identity);

  /// Serializes this Share to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as Share;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Share&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.ownerId, _this.ownerId) || other.ownerId == _this.ownerId)&&(identical(other.recipientId, _this.recipientId) || other.recipientId == _this.recipientId)&&(identical(other.resourceType, _this.resourceType) || other.resourceType == _this.resourceType)&&(identical(other.resourceId, _this.resourceId) || other.resourceId == _this.resourceId)&&(identical(other.createdAt, _this.createdAt) || other.createdAt == _this.createdAt)&&(identical(other.recipient, _this.recipient) || other.recipient == _this.recipient)&&(identical(other.owner, _this.owner) || other.owner == _this.owner)&&(identical(other.resourceTitle, _this.resourceTitle) || other.resourceTitle == _this.resourceTitle));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as Share;
  return Object.hash(runtimeType,_this.id,_this.ownerId,_this.recipientId,_this.resourceType,_this.resourceId,_this.createdAt,_this.recipient,_this.owner,_this.resourceTitle);
}

@override
String toString() {
  final _this = this as Share;
  return 'Share(id: ${_this.id}, ownerId: ${_this.ownerId}, recipientId: ${_this.recipientId}, resourceType: ${_this.resourceType}, resourceId: ${_this.resourceId}, createdAt: ${_this.createdAt}, recipient: ${_this.recipient}, owner: ${_this.owner}, resourceTitle: ${_this.resourceTitle})';
}


}

/// @nodoc
abstract mixin class $ShareCopyWith<$Res>  {
  factory $ShareCopyWith(Share value, $Res Function(Share) _then) = _$ShareCopyWithImpl;
@useResult
$Res call({
 String id, String ownerId, String recipientId, ShareResourceType resourceType, String resourceId, DateTime createdAt,@JsonKey(includeToJson: false) Profile? recipient,@JsonKey(includeToJson: false) Profile? owner,@JsonKey(includeToJson: false) String? resourceTitle
});


$ProfileCopyWith<$Res>? get recipient;$ProfileCopyWith<$Res>? get owner;

}
/// @nodoc
class _$ShareCopyWithImpl<$Res>
    implements $ShareCopyWith<$Res> {
  _$ShareCopyWithImpl(this._self, this._then);

  final Share _self;
  final $Res Function(Share) _then;

/// Create a copy of Share
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? ownerId = null,Object? recipientId = null,Object? resourceType = null,Object? resourceId = null,Object? createdAt = null,Object? recipient = freezed,Object? owner = freezed,Object? resourceTitle = freezed,}) {
  return _then(Share(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,ownerId: null == ownerId ? _self.ownerId : ownerId // ignore: cast_nullable_to_non_nullable
as String,recipientId: null == recipientId ? _self.recipientId : recipientId // ignore: cast_nullable_to_non_nullable
as String,resourceType: null == resourceType ? _self.resourceType : resourceType // ignore: cast_nullable_to_non_nullable
as ShareResourceType,resourceId: null == resourceId ? _self.resourceId : resourceId // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,recipient: freezed == recipient ? _self.recipient : recipient // ignore: cast_nullable_to_non_nullable
as Profile?,owner: freezed == owner ? _self.owner : owner // ignore: cast_nullable_to_non_nullable
as Profile?,resourceTitle: freezed == resourceTitle ? _self.resourceTitle : resourceTitle // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}
/// Create a copy of Share
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProfileCopyWith<$Res>? get recipient {
    if (_self.recipient == null) {
    return null;
  }

  return $ProfileCopyWith<$Res>(_self.recipient!, (value) {
    return _then(_self.copyWith(recipient: value));
  });
}/// Create a copy of Share
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProfileCopyWith<$Res>? get owner {
    if (_self.owner == null) {
    return null;
  }

  return $ProfileCopyWith<$Res>(_self.owner!, (value) {
    return _then(_self.copyWith(owner: value));
  });
}
}


/// Adds pattern-matching-related methods to [Share].
extension SharePatterns on Share {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Share value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Share() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Share value)  $default,){
final _that = this;
switch (_that) {
case _Share():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Share value)?  $default,){
final _that = this;
switch (_that) {
case _Share() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String ownerId,  String recipientId,  ShareResourceType resourceType,  String resourceId,  DateTime createdAt, @JsonKey(includeToJson: false)  Profile? recipient, @JsonKey(includeToJson: false)  Profile? owner, @JsonKey(includeToJson: false)  String? resourceTitle)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Share() when $default != null:
return $default(_that.id,_that.ownerId,_that.recipientId,_that.resourceType,_that.resourceId,_that.createdAt,_that.recipient,_that.owner,_that.resourceTitle);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String ownerId,  String recipientId,  ShareResourceType resourceType,  String resourceId,  DateTime createdAt, @JsonKey(includeToJson: false)  Profile? recipient, @JsonKey(includeToJson: false)  Profile? owner, @JsonKey(includeToJson: false)  String? resourceTitle)  $default,) {final _that = this;
switch (_that) {
case _Share():
return $default(_that.id,_that.ownerId,_that.recipientId,_that.resourceType,_that.resourceId,_that.createdAt,_that.recipient,_that.owner,_that.resourceTitle);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String ownerId,  String recipientId,  ShareResourceType resourceType,  String resourceId,  DateTime createdAt, @JsonKey(includeToJson: false)  Profile? recipient, @JsonKey(includeToJson: false)  Profile? owner, @JsonKey(includeToJson: false)  String? resourceTitle)?  $default,) {final _that = this;
switch (_that) {
case _Share() when $default != null:
return $default(_that.id,_that.ownerId,_that.recipientId,_that.resourceType,_that.resourceId,_that.createdAt,_that.recipient,_that.owner,_that.resourceTitle);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Share implements Share {
  const _Share({required this.id, required this.ownerId, required this.recipientId, required this.resourceType, required this.resourceId, required this.createdAt, @JsonKey(includeToJson: false) this.recipient, @JsonKey(includeToJson: false) this.owner, @JsonKey(includeToJson: false) this.resourceTitle});
  factory _Share.fromJson(Map<String, dynamic> json) => _$ShareFromJson(json);

@override final  String id;
@override final  String ownerId;
@override final  String recipientId;
@override final  ShareResourceType resourceType;
@override final  String resourceId;
@override final  DateTime createdAt;
/// Joined profile of the recipient (select alias `recipient`), if loaded.
@override@JsonKey(includeToJson: false) final  Profile? recipient;
/// Joined profile of the owner (select alias `owner`), if loaded.
@override@JsonKey(includeToJson: false) final  Profile? owner;
/// Title of the shared resource, if the query joined it (UI convenience).
@override@JsonKey(includeToJson: false) final  String? resourceTitle;

/// Create a copy of Share
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ShareCopyWith<_Share> get copyWith => __$ShareCopyWithImpl<_Share>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ShareToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _Share&&(identical(other.id, id) || other.id == id)&&(identical(other.ownerId, ownerId) || other.ownerId == ownerId)&&(identical(other.recipientId, recipientId) || other.recipientId == recipientId)&&(identical(other.resourceType, resourceType) || other.resourceType == resourceType)&&(identical(other.resourceId, resourceId) || other.resourceId == resourceId)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.recipient, recipient) || other.recipient == recipient)&&(identical(other.owner, owner) || other.owner == owner)&&(identical(other.resourceTitle, resourceTitle) || other.resourceTitle == resourceTitle));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,id,ownerId,recipientId,resourceType,resourceId,createdAt,recipient,owner,resourceTitle);
}

@override
String toString() {
    return 'Share(id: $id, ownerId: $ownerId, recipientId: $recipientId, resourceType: $resourceType, resourceId: $resourceId, createdAt: $createdAt, recipient: $recipient, owner: $owner, resourceTitle: $resourceTitle)';
}


}

/// @nodoc
abstract mixin class _$ShareCopyWith<$Res> implements $ShareCopyWith<$Res> {
  factory _$ShareCopyWith(_Share value, $Res Function(_Share) _then) = __$ShareCopyWithImpl;
@override @useResult
$Res call({
 String id, String ownerId, String recipientId, ShareResourceType resourceType, String resourceId, DateTime createdAt,@JsonKey(includeToJson: false) Profile? recipient,@JsonKey(includeToJson: false) Profile? owner,@JsonKey(includeToJson: false) String? resourceTitle
});


@override $ProfileCopyWith<$Res>? get recipient;@override $ProfileCopyWith<$Res>? get owner;

}
/// @nodoc
class __$ShareCopyWithImpl<$Res>
    implements _$ShareCopyWith<$Res> {
  __$ShareCopyWithImpl(this._self, this._then);

  final _Share _self;
  final $Res Function(_Share) _then;

/// Create a copy of Share
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? ownerId = null,Object? recipientId = null,Object? resourceType = null,Object? resourceId = null,Object? createdAt = null,Object? recipient = freezed,Object? owner = freezed,Object? resourceTitle = freezed,}) {
  return _then(_Share(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,ownerId: null == ownerId ? _self.ownerId : ownerId // ignore: cast_nullable_to_non_nullable
as String,recipientId: null == recipientId ? _self.recipientId : recipientId // ignore: cast_nullable_to_non_nullable
as String,resourceType: null == resourceType ? _self.resourceType : resourceType // ignore: cast_nullable_to_non_nullable
as ShareResourceType,resourceId: null == resourceId ? _self.resourceId : resourceId // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,recipient: freezed == recipient ? _self.recipient : recipient // ignore: cast_nullable_to_non_nullable
as Profile?,owner: freezed == owner ? _self.owner : owner // ignore: cast_nullable_to_non_nullable
as Profile?,resourceTitle: freezed == resourceTitle ? _self.resourceTitle : resourceTitle // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

/// Create a copy of Share
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProfileCopyWith<$Res>? get recipient {
    if (_self.recipient == null) {
    return null;
  }

  return $ProfileCopyWith<$Res>(_self.recipient!, (value) {
    return _then(_self.copyWith(recipient: value));
  });
}/// Create a copy of Share
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProfileCopyWith<$Res>? get owner {
    if (_self.owner == null) {
    return null;
  }

  return $ProfileCopyWith<$Res>(_self.owner!, (value) {
    return _then(_self.copyWith(owner: value));
  });
}
}

// dart format on
