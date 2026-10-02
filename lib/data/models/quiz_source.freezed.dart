// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'quiz_source.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$QuizSource {

/// Pasted text (possibly truncated).
 String? get contextText; String? get youtubeUrl;/// `LlmProviderId.wireName`, e.g. `gemini`.
 String? get provider; String? get model;/// Notes used as source material (id + title at generation time).
 List<QuizSourceRef> get notes;/// Subject attachments used as source material (id + file name).
 List<QuizSourceRef> get attachments;
/// Create a copy of QuizSource
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$QuizSourceCopyWith<QuizSource> get copyWith => _$QuizSourceCopyWithImpl<QuizSource>(this as QuizSource, _$identity);

  /// Serializes this QuizSource to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as QuizSource;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is QuizSource&&(identical(other.contextText, _this.contextText) || other.contextText == _this.contextText)&&(identical(other.youtubeUrl, _this.youtubeUrl) || other.youtubeUrl == _this.youtubeUrl)&&(identical(other.provider, _this.provider) || other.provider == _this.provider)&&(identical(other.model, _this.model) || other.model == _this.model)&&const DeepCollectionEquality().equals(other.notes, _this.notes)&&const DeepCollectionEquality().equals(other.attachments, _this.attachments));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as QuizSource;
  return Object.hash(runtimeType,_this.contextText,_this.youtubeUrl,_this.provider,_this.model,const DeepCollectionEquality().hash(_this.notes),const DeepCollectionEquality().hash(_this.attachments));
}

@override
String toString() {
  final _this = this as QuizSource;
  return 'QuizSource(contextText: ${_this.contextText}, youtubeUrl: ${_this.youtubeUrl}, provider: ${_this.provider}, model: ${_this.model}, notes: ${_this.notes}, attachments: ${_this.attachments})';
}


}

/// @nodoc
abstract mixin class $QuizSourceCopyWith<$Res>  {
  factory $QuizSourceCopyWith(QuizSource value, $Res Function(QuizSource) _then) = _$QuizSourceCopyWithImpl;
@useResult
$Res call({
 String? contextText, String? youtubeUrl, String? provider, String? model, List<QuizSourceRef> notes, List<QuizSourceRef> attachments
});




}
/// @nodoc
class _$QuizSourceCopyWithImpl<$Res>
    implements $QuizSourceCopyWith<$Res> {
  _$QuizSourceCopyWithImpl(this._self, this._then);

  final QuizSource _self;
  final $Res Function(QuizSource) _then;

/// Create a copy of QuizSource
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? contextText = freezed,Object? youtubeUrl = freezed,Object? provider = freezed,Object? model = freezed,Object? notes = null,Object? attachments = null,}) {
  return _then(QuizSource(
contextText: freezed == contextText ? _self.contextText : contextText // ignore: cast_nullable_to_non_nullable
as String?,youtubeUrl: freezed == youtubeUrl ? _self.youtubeUrl : youtubeUrl // ignore: cast_nullable_to_non_nullable
as String?,provider: freezed == provider ? _self.provider : provider // ignore: cast_nullable_to_non_nullable
as String?,model: freezed == model ? _self.model : model // ignore: cast_nullable_to_non_nullable
as String?,notes: null == notes ? _self.notes : notes // ignore: cast_nullable_to_non_nullable
as List<QuizSourceRef>,attachments: null == attachments ? _self.attachments : attachments // ignore: cast_nullable_to_non_nullable
as List<QuizSourceRef>,
  ));
}

}


/// Adds pattern-matching-related methods to [QuizSource].
extension QuizSourcePatterns on QuizSource {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _QuizSource value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _QuizSource() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _QuizSource value)  $default,){
final _that = this;
switch (_that) {
case _QuizSource():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _QuizSource value)?  $default,){
final _that = this;
switch (_that) {
case _QuizSource() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String? contextText,  String? youtubeUrl,  String? provider,  String? model,  List<QuizSourceRef> notes,  List<QuizSourceRef> attachments)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _QuizSource() when $default != null:
return $default(_that.contextText,_that.youtubeUrl,_that.provider,_that.model,_that.notes,_that.attachments);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String? contextText,  String? youtubeUrl,  String? provider,  String? model,  List<QuizSourceRef> notes,  List<QuizSourceRef> attachments)  $default,) {final _that = this;
switch (_that) {
case _QuizSource():
return $default(_that.contextText,_that.youtubeUrl,_that.provider,_that.model,_that.notes,_that.attachments);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String? contextText,  String? youtubeUrl,  String? provider,  String? model,  List<QuizSourceRef> notes,  List<QuizSourceRef> attachments)?  $default,) {final _that = this;
switch (_that) {
case _QuizSource() when $default != null:
return $default(_that.contextText,_that.youtubeUrl,_that.provider,_that.model,_that.notes,_that.attachments);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _QuizSource implements QuizSource {
  const _QuizSource({this.contextText, this.youtubeUrl, this.provider, this.model,  List<QuizSourceRef> notes = const <QuizSourceRef>[],  List<QuizSourceRef> attachments = const <QuizSourceRef>[]}): _notes = notes,_attachments = attachments;
  factory _QuizSource.fromJson(Map<String, dynamic> json) => _$QuizSourceFromJson(json);

/// Pasted text (possibly truncated).
@override final  String? contextText;
@override final  String? youtubeUrl;
/// `LlmProviderId.wireName`, e.g. `gemini`.
@override final  String? provider;
@override final  String? model;
/// Notes used as source material (id + title at generation time).
 final  List<QuizSourceRef> _notes;
/// Notes used as source material (id + title at generation time).
@override@JsonKey() List<QuizSourceRef> get notes {
  if (_notes is EqualUnmodifiableListView) return _notes;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_notes);
}

/// Subject attachments used as source material (id + file name).
 final  List<QuizSourceRef> _attachments;
/// Subject attachments used as source material (id + file name).
@override@JsonKey() List<QuizSourceRef> get attachments {
  if (_attachments is EqualUnmodifiableListView) return _attachments;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_attachments);
}


/// Create a copy of QuizSource
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$QuizSourceCopyWith<_QuizSource> get copyWith => __$QuizSourceCopyWithImpl<_QuizSource>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$QuizSourceToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _QuizSource&&(identical(other.contextText, contextText) || other.contextText == contextText)&&(identical(other.youtubeUrl, youtubeUrl) || other.youtubeUrl == youtubeUrl)&&(identical(other.provider, provider) || other.provider == provider)&&(identical(other.model, model) || other.model == model)&&const DeepCollectionEquality().equals(other.notes, _notes)&&const DeepCollectionEquality().equals(other.attachments, _attachments));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,contextText,youtubeUrl,provider,model,const DeepCollectionEquality().hash(_notes),const DeepCollectionEquality().hash(_attachments));
}

@override
String toString() {
    return 'QuizSource(contextText: $contextText, youtubeUrl: $youtubeUrl, provider: $provider, model: $model, notes: $notes, attachments: $attachments)';
}


}

/// @nodoc
abstract mixin class _$QuizSourceCopyWith<$Res> implements $QuizSourceCopyWith<$Res> {
  factory _$QuizSourceCopyWith(_QuizSource value, $Res Function(_QuizSource) _then) = __$QuizSourceCopyWithImpl;
@override @useResult
$Res call({
 String? contextText, String? youtubeUrl, String? provider, String? model, List<QuizSourceRef> notes, List<QuizSourceRef> attachments
});




}
/// @nodoc
class __$QuizSourceCopyWithImpl<$Res>
    implements _$QuizSourceCopyWith<$Res> {
  __$QuizSourceCopyWithImpl(this._self, this._then);

  final _QuizSource _self;
  final $Res Function(_QuizSource) _then;

/// Create a copy of QuizSource
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? contextText = freezed,Object? youtubeUrl = freezed,Object? provider = freezed,Object? model = freezed,Object? notes = null,Object? attachments = null,}) {
  return _then(_QuizSource(
contextText: freezed == contextText ? _self.contextText : contextText // ignore: cast_nullable_to_non_nullable
as String?,youtubeUrl: freezed == youtubeUrl ? _self.youtubeUrl : youtubeUrl // ignore: cast_nullable_to_non_nullable
as String?,provider: freezed == provider ? _self.provider : provider // ignore: cast_nullable_to_non_nullable
as String?,model: freezed == model ? _self.model : model // ignore: cast_nullable_to_non_nullable
as String?,notes: null == notes ? _self._notes : notes // ignore: cast_nullable_to_non_nullable
as List<QuizSourceRef>,attachments: null == attachments ? _self._attachments : attachments // ignore: cast_nullable_to_non_nullable
as List<QuizSourceRef>,
  ));
}


}


/// @nodoc
mixin _$QuizSourceRef {

 String get id; String get name;
/// Create a copy of QuizSourceRef
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$QuizSourceRefCopyWith<QuizSourceRef> get copyWith => _$QuizSourceRefCopyWithImpl<QuizSourceRef>(this as QuizSourceRef, _$identity);

  /// Serializes this QuizSourceRef to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as QuizSourceRef;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is QuizSourceRef&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.name, _this.name) || other.name == _this.name));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as QuizSourceRef;
  return Object.hash(runtimeType,_this.id,_this.name);
}

@override
String toString() {
  final _this = this as QuizSourceRef;
  return 'QuizSourceRef(id: ${_this.id}, name: ${_this.name})';
}


}

/// @nodoc
abstract mixin class $QuizSourceRefCopyWith<$Res>  {
  factory $QuizSourceRefCopyWith(QuizSourceRef value, $Res Function(QuizSourceRef) _then) = _$QuizSourceRefCopyWithImpl;
@useResult
$Res call({
 String id, String name
});




}
/// @nodoc
class _$QuizSourceRefCopyWithImpl<$Res>
    implements $QuizSourceRefCopyWith<$Res> {
  _$QuizSourceRefCopyWithImpl(this._self, this._then);

  final QuizSourceRef _self;
  final $Res Function(QuizSourceRef) _then;

/// Create a copy of QuizSourceRef
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,}) {
  return _then(QuizSourceRef(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [QuizSourceRef].
extension QuizSourceRefPatterns on QuizSourceRef {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _QuizSourceRef value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _QuizSourceRef() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _QuizSourceRef value)  $default,){
final _that = this;
switch (_that) {
case _QuizSourceRef():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _QuizSourceRef value)?  $default,){
final _that = this;
switch (_that) {
case _QuizSourceRef() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _QuizSourceRef() when $default != null:
return $default(_that.id,_that.name);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name)  $default,) {final _that = this;
switch (_that) {
case _QuizSourceRef():
return $default(_that.id,_that.name);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name)?  $default,) {final _that = this;
switch (_that) {
case _QuizSourceRef() when $default != null:
return $default(_that.id,_that.name);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _QuizSourceRef implements QuizSourceRef {
  const _QuizSourceRef({required this.id, required this.name});
  factory _QuizSourceRef.fromJson(Map<String, dynamic> json) => _$QuizSourceRefFromJson(json);

@override final  String id;
@override final  String name;

/// Create a copy of QuizSourceRef
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$QuizSourceRefCopyWith<_QuizSourceRef> get copyWith => __$QuizSourceRefCopyWithImpl<_QuizSourceRef>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$QuizSourceRefToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _QuizSourceRef&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,id,name);
}

@override
String toString() {
    return 'QuizSourceRef(id: $id, name: $name)';
}


}

/// @nodoc
abstract mixin class _$QuizSourceRefCopyWith<$Res> implements $QuizSourceRefCopyWith<$Res> {
  factory _$QuizSourceRefCopyWith(_QuizSourceRef value, $Res Function(_QuizSourceRef) _then) = __$QuizSourceRefCopyWithImpl;
@override @useResult
$Res call({
 String id, String name
});




}
/// @nodoc
class __$QuizSourceRefCopyWithImpl<$Res>
    implements _$QuizSourceRefCopyWith<$Res> {
  __$QuizSourceRefCopyWithImpl(this._self, this._then);

  final _QuizSourceRef _self;
  final $Res Function(_QuizSourceRef) _then;

/// Create a copy of QuizSourceRef
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,}) {
  return _then(_QuizSourceRef(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
