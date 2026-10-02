// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'chat.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$Chat {

 String get id; String get ownerId;@JsonKey(unknownEnumValue: ChatScopeType.general) ChatScopeType get scopeType; String? get scopeId; String get title;/// AI provider (`LlmProviderId.wireName`) and model used.
 String? get provider; String? get model; DateTime get createdAt; DateTime get updatedAt; DateTime? get deletedAt;
/// Create a copy of Chat
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ChatCopyWith<Chat> get copyWith => _$ChatCopyWithImpl<Chat>(this as Chat, _$identity);

  /// Serializes this Chat to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as Chat;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Chat&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.ownerId, _this.ownerId) || other.ownerId == _this.ownerId)&&(identical(other.scopeType, _this.scopeType) || other.scopeType == _this.scopeType)&&(identical(other.scopeId, _this.scopeId) || other.scopeId == _this.scopeId)&&(identical(other.title, _this.title) || other.title == _this.title)&&(identical(other.provider, _this.provider) || other.provider == _this.provider)&&(identical(other.model, _this.model) || other.model == _this.model)&&(identical(other.createdAt, _this.createdAt) || other.createdAt == _this.createdAt)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt)&&(identical(other.deletedAt, _this.deletedAt) || other.deletedAt == _this.deletedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as Chat;
  return Object.hash(runtimeType,_this.id,_this.ownerId,_this.scopeType,_this.scopeId,_this.title,_this.provider,_this.model,_this.createdAt,_this.updatedAt,_this.deletedAt);
}

@override
String toString() {
  final _this = this as Chat;
  return 'Chat(id: ${_this.id}, ownerId: ${_this.ownerId}, scopeType: ${_this.scopeType}, scopeId: ${_this.scopeId}, title: ${_this.title}, provider: ${_this.provider}, model: ${_this.model}, createdAt: ${_this.createdAt}, updatedAt: ${_this.updatedAt}, deletedAt: ${_this.deletedAt})';
}


}

/// @nodoc
abstract mixin class $ChatCopyWith<$Res>  {
  factory $ChatCopyWith(Chat value, $Res Function(Chat) _then) = _$ChatCopyWithImpl;
@useResult
$Res call({
 String id, String ownerId,@JsonKey(unknownEnumValue: ChatScopeType.general) ChatScopeType scopeType, String? scopeId, String title, String? provider, String? model, DateTime createdAt, DateTime updatedAt, DateTime? deletedAt
});




}
/// @nodoc
class _$ChatCopyWithImpl<$Res>
    implements $ChatCopyWith<$Res> {
  _$ChatCopyWithImpl(this._self, this._then);

  final Chat _self;
  final $Res Function(Chat) _then;

/// Create a copy of Chat
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? ownerId = null,Object? scopeType = null,Object? scopeId = freezed,Object? title = null,Object? provider = freezed,Object? model = freezed,Object? createdAt = null,Object? updatedAt = null,Object? deletedAt = freezed,}) {
  return _then(Chat(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,ownerId: null == ownerId ? _self.ownerId : ownerId // ignore: cast_nullable_to_non_nullable
as String,scopeType: null == scopeType ? _self.scopeType : scopeType // ignore: cast_nullable_to_non_nullable
as ChatScopeType,scopeId: freezed == scopeId ? _self.scopeId : scopeId // ignore: cast_nullable_to_non_nullable
as String?,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,provider: freezed == provider ? _self.provider : provider // ignore: cast_nullable_to_non_nullable
as String?,model: freezed == model ? _self.model : model // ignore: cast_nullable_to_non_nullable
as String?,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,deletedAt: freezed == deletedAt ? _self.deletedAt : deletedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

}


/// Adds pattern-matching-related methods to [Chat].
extension ChatPatterns on Chat {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Chat value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Chat() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Chat value)  $default,){
final _that = this;
switch (_that) {
case _Chat():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Chat value)?  $default,){
final _that = this;
switch (_that) {
case _Chat() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String ownerId, @JsonKey(unknownEnumValue: ChatScopeType.general)  ChatScopeType scopeType,  String? scopeId,  String title,  String? provider,  String? model,  DateTime createdAt,  DateTime updatedAt,  DateTime? deletedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Chat() when $default != null:
return $default(_that.id,_that.ownerId,_that.scopeType,_that.scopeId,_that.title,_that.provider,_that.model,_that.createdAt,_that.updatedAt,_that.deletedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String ownerId, @JsonKey(unknownEnumValue: ChatScopeType.general)  ChatScopeType scopeType,  String? scopeId,  String title,  String? provider,  String? model,  DateTime createdAt,  DateTime updatedAt,  DateTime? deletedAt)  $default,) {final _that = this;
switch (_that) {
case _Chat():
return $default(_that.id,_that.ownerId,_that.scopeType,_that.scopeId,_that.title,_that.provider,_that.model,_that.createdAt,_that.updatedAt,_that.deletedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String ownerId, @JsonKey(unknownEnumValue: ChatScopeType.general)  ChatScopeType scopeType,  String? scopeId,  String title,  String? provider,  String? model,  DateTime createdAt,  DateTime updatedAt,  DateTime? deletedAt)?  $default,) {final _that = this;
switch (_that) {
case _Chat() when $default != null:
return $default(_that.id,_that.ownerId,_that.scopeType,_that.scopeId,_that.title,_that.provider,_that.model,_that.createdAt,_that.updatedAt,_that.deletedAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Chat implements Chat {
  const _Chat({required this.id, required this.ownerId, @JsonKey(unknownEnumValue: ChatScopeType.general) this.scopeType = ChatScopeType.general, this.scopeId, this.title = '', this.provider, this.model, required this.createdAt, required this.updatedAt, this.deletedAt});
  factory _Chat.fromJson(Map<String, dynamic> json) => _$ChatFromJson(json);

@override final  String id;
@override final  String ownerId;
@override@JsonKey(unknownEnumValue: ChatScopeType.general) final  ChatScopeType scopeType;
@override final  String? scopeId;
@override@JsonKey() final  String title;
/// AI provider (`LlmProviderId.wireName`) and model used.
@override final  String? provider;
@override final  String? model;
@override final  DateTime createdAt;
@override final  DateTime updatedAt;
@override final  DateTime? deletedAt;

/// Create a copy of Chat
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ChatCopyWith<_Chat> get copyWith => __$ChatCopyWithImpl<_Chat>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ChatToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _Chat&&(identical(other.id, id) || other.id == id)&&(identical(other.ownerId, ownerId) || other.ownerId == ownerId)&&(identical(other.scopeType, scopeType) || other.scopeType == scopeType)&&(identical(other.scopeId, scopeId) || other.scopeId == scopeId)&&(identical(other.title, title) || other.title == title)&&(identical(other.provider, provider) || other.provider == provider)&&(identical(other.model, model) || other.model == model)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.deletedAt, deletedAt) || other.deletedAt == deletedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,id,ownerId,scopeType,scopeId,title,provider,model,createdAt,updatedAt,deletedAt);
}

@override
String toString() {
    return 'Chat(id: $id, ownerId: $ownerId, scopeType: $scopeType, scopeId: $scopeId, title: $title, provider: $provider, model: $model, createdAt: $createdAt, updatedAt: $updatedAt, deletedAt: $deletedAt)';
}


}

/// @nodoc
abstract mixin class _$ChatCopyWith<$Res> implements $ChatCopyWith<$Res> {
  factory _$ChatCopyWith(_Chat value, $Res Function(_Chat) _then) = __$ChatCopyWithImpl;
@override @useResult
$Res call({
 String id, String ownerId,@JsonKey(unknownEnumValue: ChatScopeType.general) ChatScopeType scopeType, String? scopeId, String title, String? provider, String? model, DateTime createdAt, DateTime updatedAt, DateTime? deletedAt
});




}
/// @nodoc
class __$ChatCopyWithImpl<$Res>
    implements _$ChatCopyWith<$Res> {
  __$ChatCopyWithImpl(this._self, this._then);

  final _Chat _self;
  final $Res Function(_Chat) _then;

/// Create a copy of Chat
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? ownerId = null,Object? scopeType = null,Object? scopeId = freezed,Object? title = null,Object? provider = freezed,Object? model = freezed,Object? createdAt = null,Object? updatedAt = null,Object? deletedAt = freezed,}) {
  return _then(_Chat(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,ownerId: null == ownerId ? _self.ownerId : ownerId // ignore: cast_nullable_to_non_nullable
as String,scopeType: null == scopeType ? _self.scopeType : scopeType // ignore: cast_nullable_to_non_nullable
as ChatScopeType,scopeId: freezed == scopeId ? _self.scopeId : scopeId // ignore: cast_nullable_to_non_nullable
as String?,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,provider: freezed == provider ? _self.provider : provider // ignore: cast_nullable_to_non_nullable
as String?,model: freezed == model ? _self.model : model // ignore: cast_nullable_to_non_nullable
as String?,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,deletedAt: freezed == deletedAt ? _self.deletedAt : deletedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}


/// @nodoc
mixin _$ChatCitation {

 String get type; String get id; String get title; String? get snippet;
/// Create a copy of ChatCitation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ChatCitationCopyWith<ChatCitation> get copyWith => _$ChatCitationCopyWithImpl<ChatCitation>(this as ChatCitation, _$identity);

  /// Serializes this ChatCitation to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as ChatCitation;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ChatCitation&&(identical(other.type, _this.type) || other.type == _this.type)&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.title, _this.title) || other.title == _this.title)&&(identical(other.snippet, _this.snippet) || other.snippet == _this.snippet));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as ChatCitation;
  return Object.hash(runtimeType,_this.type,_this.id,_this.title,_this.snippet);
}

@override
String toString() {
  final _this = this as ChatCitation;
  return 'ChatCitation(type: ${_this.type}, id: ${_this.id}, title: ${_this.title}, snippet: ${_this.snippet})';
}


}

/// @nodoc
abstract mixin class $ChatCitationCopyWith<$Res>  {
  factory $ChatCitationCopyWith(ChatCitation value, $Res Function(ChatCitation) _then) = _$ChatCitationCopyWithImpl;
@useResult
$Res call({
 String type, String id, String title, String? snippet
});




}
/// @nodoc
class _$ChatCitationCopyWithImpl<$Res>
    implements $ChatCitationCopyWith<$Res> {
  _$ChatCitationCopyWithImpl(this._self, this._then);

  final ChatCitation _self;
  final $Res Function(ChatCitation) _then;

/// Create a copy of ChatCitation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? type = null,Object? id = null,Object? title = null,Object? snippet = freezed,}) {
  return _then(ChatCitation(
type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String,id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,snippet: freezed == snippet ? _self.snippet : snippet // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [ChatCitation].
extension ChatCitationPatterns on ChatCitation {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ChatCitation value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ChatCitation() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ChatCitation value)  $default,){
final _that = this;
switch (_that) {
case _ChatCitation():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ChatCitation value)?  $default,){
final _that = this;
switch (_that) {
case _ChatCitation() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String type,  String id,  String title,  String? snippet)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ChatCitation() when $default != null:
return $default(_that.type,_that.id,_that.title,_that.snippet);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String type,  String id,  String title,  String? snippet)  $default,) {final _that = this;
switch (_that) {
case _ChatCitation():
return $default(_that.type,_that.id,_that.title,_that.snippet);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String type,  String id,  String title,  String? snippet)?  $default,) {final _that = this;
switch (_that) {
case _ChatCitation() when $default != null:
return $default(_that.type,_that.id,_that.title,_that.snippet);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ChatCitation implements ChatCitation {
  const _ChatCitation({required this.type, required this.id, this.title = '', this.snippet});
  factory _ChatCitation.fromJson(Map<String, dynamic> json) => _$ChatCitationFromJson(json);

@override final  String type;
@override final  String id;
@override@JsonKey() final  String title;
@override final  String? snippet;

/// Create a copy of ChatCitation
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ChatCitationCopyWith<_ChatCitation> get copyWith => __$ChatCitationCopyWithImpl<_ChatCitation>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ChatCitationToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ChatCitation&&(identical(other.type, type) || other.type == type)&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.snippet, snippet) || other.snippet == snippet));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,type,id,title,snippet);
}

@override
String toString() {
    return 'ChatCitation(type: $type, id: $id, title: $title, snippet: $snippet)';
}


}

/// @nodoc
abstract mixin class _$ChatCitationCopyWith<$Res> implements $ChatCitationCopyWith<$Res> {
  factory _$ChatCitationCopyWith(_ChatCitation value, $Res Function(_ChatCitation) _then) = __$ChatCitationCopyWithImpl;
@override @useResult
$Res call({
 String type, String id, String title, String? snippet
});




}
/// @nodoc
class __$ChatCitationCopyWithImpl<$Res>
    implements _$ChatCitationCopyWith<$Res> {
  __$ChatCitationCopyWithImpl(this._self, this._then);

  final _ChatCitation _self;
  final $Res Function(_ChatCitation) _then;

/// Create a copy of ChatCitation
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? type = null,Object? id = null,Object? title = null,Object? snippet = freezed,}) {
  return _then(_ChatCitation(
type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String,id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,snippet: freezed == snippet ? _self.snippet : snippet // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}


/// @nodoc
mixin _$ChatMessage {

 String get id; String get chatId; String get ownerId;@JsonKey(unknownEnumValue: ChatRole.system) ChatRole get role; String get content; List<ChatCitation> get citations; DateTime get createdAt; DateTime get updatedAt; DateTime? get deletedAt;
/// Create a copy of ChatMessage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ChatMessageCopyWith<ChatMessage> get copyWith => _$ChatMessageCopyWithImpl<ChatMessage>(this as ChatMessage, _$identity);

  /// Serializes this ChatMessage to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as ChatMessage;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ChatMessage&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.chatId, _this.chatId) || other.chatId == _this.chatId)&&(identical(other.ownerId, _this.ownerId) || other.ownerId == _this.ownerId)&&(identical(other.role, _this.role) || other.role == _this.role)&&(identical(other.content, _this.content) || other.content == _this.content)&&const DeepCollectionEquality().equals(other.citations, _this.citations)&&(identical(other.createdAt, _this.createdAt) || other.createdAt == _this.createdAt)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt)&&(identical(other.deletedAt, _this.deletedAt) || other.deletedAt == _this.deletedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as ChatMessage;
  return Object.hash(runtimeType,_this.id,_this.chatId,_this.ownerId,_this.role,_this.content,const DeepCollectionEquality().hash(_this.citations),_this.createdAt,_this.updatedAt,_this.deletedAt);
}

@override
String toString() {
  final _this = this as ChatMessage;
  return 'ChatMessage(id: ${_this.id}, chatId: ${_this.chatId}, ownerId: ${_this.ownerId}, role: ${_this.role}, content: ${_this.content}, citations: ${_this.citations}, createdAt: ${_this.createdAt}, updatedAt: ${_this.updatedAt}, deletedAt: ${_this.deletedAt})';
}


}

/// @nodoc
abstract mixin class $ChatMessageCopyWith<$Res>  {
  factory $ChatMessageCopyWith(ChatMessage value, $Res Function(ChatMessage) _then) = _$ChatMessageCopyWithImpl;
@useResult
$Res call({
 String id, String chatId, String ownerId,@JsonKey(unknownEnumValue: ChatRole.system) ChatRole role, String content, List<ChatCitation> citations, DateTime createdAt, DateTime updatedAt, DateTime? deletedAt
});




}
/// @nodoc
class _$ChatMessageCopyWithImpl<$Res>
    implements $ChatMessageCopyWith<$Res> {
  _$ChatMessageCopyWithImpl(this._self, this._then);

  final ChatMessage _self;
  final $Res Function(ChatMessage) _then;

/// Create a copy of ChatMessage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? chatId = null,Object? ownerId = null,Object? role = null,Object? content = null,Object? citations = null,Object? createdAt = null,Object? updatedAt = null,Object? deletedAt = freezed,}) {
  return _then(ChatMessage(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,chatId: null == chatId ? _self.chatId : chatId // ignore: cast_nullable_to_non_nullable
as String,ownerId: null == ownerId ? _self.ownerId : ownerId // ignore: cast_nullable_to_non_nullable
as String,role: null == role ? _self.role : role // ignore: cast_nullable_to_non_nullable
as ChatRole,content: null == content ? _self.content : content // ignore: cast_nullable_to_non_nullable
as String,citations: null == citations ? _self.citations : citations // ignore: cast_nullable_to_non_nullable
as List<ChatCitation>,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,deletedAt: freezed == deletedAt ? _self.deletedAt : deletedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

}


/// Adds pattern-matching-related methods to [ChatMessage].
extension ChatMessagePatterns on ChatMessage {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ChatMessage value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ChatMessage() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ChatMessage value)  $default,){
final _that = this;
switch (_that) {
case _ChatMessage():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ChatMessage value)?  $default,){
final _that = this;
switch (_that) {
case _ChatMessage() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String chatId,  String ownerId, @JsonKey(unknownEnumValue: ChatRole.system)  ChatRole role,  String content,  List<ChatCitation> citations,  DateTime createdAt,  DateTime updatedAt,  DateTime? deletedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ChatMessage() when $default != null:
return $default(_that.id,_that.chatId,_that.ownerId,_that.role,_that.content,_that.citations,_that.createdAt,_that.updatedAt,_that.deletedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String chatId,  String ownerId, @JsonKey(unknownEnumValue: ChatRole.system)  ChatRole role,  String content,  List<ChatCitation> citations,  DateTime createdAt,  DateTime updatedAt,  DateTime? deletedAt)  $default,) {final _that = this;
switch (_that) {
case _ChatMessage():
return $default(_that.id,_that.chatId,_that.ownerId,_that.role,_that.content,_that.citations,_that.createdAt,_that.updatedAt,_that.deletedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String chatId,  String ownerId, @JsonKey(unknownEnumValue: ChatRole.system)  ChatRole role,  String content,  List<ChatCitation> citations,  DateTime createdAt,  DateTime updatedAt,  DateTime? deletedAt)?  $default,) {final _that = this;
switch (_that) {
case _ChatMessage() when $default != null:
return $default(_that.id,_that.chatId,_that.ownerId,_that.role,_that.content,_that.citations,_that.createdAt,_that.updatedAt,_that.deletedAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ChatMessage implements ChatMessage {
  const _ChatMessage({required this.id, required this.chatId, required this.ownerId, @JsonKey(unknownEnumValue: ChatRole.system) required this.role, this.content = '',  List<ChatCitation> citations = const <ChatCitation>[], required this.createdAt, required this.updatedAt, this.deletedAt}): _citations = citations;
  factory _ChatMessage.fromJson(Map<String, dynamic> json) => _$ChatMessageFromJson(json);

@override final  String id;
@override final  String chatId;
@override final  String ownerId;
@override@JsonKey(unknownEnumValue: ChatRole.system) final  ChatRole role;
@override@JsonKey() final  String content;
 final  List<ChatCitation> _citations;
@override@JsonKey() List<ChatCitation> get citations {
  if (_citations is EqualUnmodifiableListView) return _citations;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_citations);
}

@override final  DateTime createdAt;
@override final  DateTime updatedAt;
@override final  DateTime? deletedAt;

/// Create a copy of ChatMessage
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ChatMessageCopyWith<_ChatMessage> get copyWith => __$ChatMessageCopyWithImpl<_ChatMessage>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ChatMessageToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ChatMessage&&(identical(other.id, id) || other.id == id)&&(identical(other.chatId, chatId) || other.chatId == chatId)&&(identical(other.ownerId, ownerId) || other.ownerId == ownerId)&&(identical(other.role, role) || other.role == role)&&(identical(other.content, content) || other.content == content)&&const DeepCollectionEquality().equals(other.citations, _citations)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.deletedAt, deletedAt) || other.deletedAt == deletedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,id,chatId,ownerId,role,content,const DeepCollectionEquality().hash(_citations),createdAt,updatedAt,deletedAt);
}

@override
String toString() {
    return 'ChatMessage(id: $id, chatId: $chatId, ownerId: $ownerId, role: $role, content: $content, citations: $citations, createdAt: $createdAt, updatedAt: $updatedAt, deletedAt: $deletedAt)';
}


}

/// @nodoc
abstract mixin class _$ChatMessageCopyWith<$Res> implements $ChatMessageCopyWith<$Res> {
  factory _$ChatMessageCopyWith(_ChatMessage value, $Res Function(_ChatMessage) _then) = __$ChatMessageCopyWithImpl;
@override @useResult
$Res call({
 String id, String chatId, String ownerId,@JsonKey(unknownEnumValue: ChatRole.system) ChatRole role, String content, List<ChatCitation> citations, DateTime createdAt, DateTime updatedAt, DateTime? deletedAt
});




}
/// @nodoc
class __$ChatMessageCopyWithImpl<$Res>
    implements _$ChatMessageCopyWith<$Res> {
  __$ChatMessageCopyWithImpl(this._self, this._then);

  final _ChatMessage _self;
  final $Res Function(_ChatMessage) _then;

/// Create a copy of ChatMessage
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? chatId = null,Object? ownerId = null,Object? role = null,Object? content = null,Object? citations = null,Object? createdAt = null,Object? updatedAt = null,Object? deletedAt = freezed,}) {
  return _then(_ChatMessage(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,chatId: null == chatId ? _self.chatId : chatId // ignore: cast_nullable_to_non_nullable
as String,ownerId: null == ownerId ? _self.ownerId : ownerId // ignore: cast_nullable_to_non_nullable
as String,role: null == role ? _self.role : role // ignore: cast_nullable_to_non_nullable
as ChatRole,content: null == content ? _self.content : content // ignore: cast_nullable_to_non_nullable
as String,citations: null == citations ? _self._citations : citations // ignore: cast_nullable_to_non_nullable
as List<ChatCitation>,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,deletedAt: freezed == deletedAt ? _self.deletedAt : deletedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}

// dart format on
