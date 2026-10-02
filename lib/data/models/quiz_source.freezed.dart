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

 String? get contextText; String? get youtubeUrl;/// `LlmProviderId.wireName`, e.g. `gemini`.
 String? get provider; String? get model;
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
  return identical(this, other) || (other.runtimeType == runtimeType&&other is QuizSource&&(identical(other.contextText, _this.contextText) || other.contextText == _this.contextText)&&(identical(other.youtubeUrl, _this.youtubeUrl) || other.youtubeUrl == _this.youtubeUrl)&&(identical(other.provider, _this.provider) || other.provider == _this.provider)&&(identical(other.model, _this.model) || other.model == _this.model));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as QuizSource;
  return Object.hash(runtimeType,_this.contextText,_this.youtubeUrl,_this.provider,_this.model);
}

@override
String toString() {
  final _this = this as QuizSource;
  return 'QuizSource(contextText: ${_this.contextText}, youtubeUrl: ${_this.youtubeUrl}, provider: ${_this.provider}, model: ${_this.model})';
}


}

/// @nodoc
abstract mixin class $QuizSourceCopyWith<$Res>  {
  factory $QuizSourceCopyWith(QuizSource value, $Res Function(QuizSource) _then) = _$QuizSourceCopyWithImpl;
@useResult
$Res call({
 String? contextText, String? youtubeUrl, String? provider, String? model
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
@pragma('vm:prefer-inline') @override $Res call({Object? contextText = freezed,Object? youtubeUrl = freezed,Object? provider = freezed,Object? model = freezed,}) {
  return _then(QuizSource(
contextText: freezed == contextText ? _self.contextText : contextText // ignore: cast_nullable_to_non_nullable
as String?,youtubeUrl: freezed == youtubeUrl ? _self.youtubeUrl : youtubeUrl // ignore: cast_nullable_to_non_nullable
as String?,provider: freezed == provider ? _self.provider : provider // ignore: cast_nullable_to_non_nullable
as String?,model: freezed == model ? _self.model : model // ignore: cast_nullable_to_non_nullable
as String?,
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String? contextText,  String? youtubeUrl,  String? provider,  String? model)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _QuizSource() when $default != null:
return $default(_that.contextText,_that.youtubeUrl,_that.provider,_that.model);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String? contextText,  String? youtubeUrl,  String? provider,  String? model)  $default,) {final _that = this;
switch (_that) {
case _QuizSource():
return $default(_that.contextText,_that.youtubeUrl,_that.provider,_that.model);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String? contextText,  String? youtubeUrl,  String? provider,  String? model)?  $default,) {final _that = this;
switch (_that) {
case _QuizSource() when $default != null:
return $default(_that.contextText,_that.youtubeUrl,_that.provider,_that.model);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _QuizSource implements QuizSource {
  const _QuizSource({this.contextText, this.youtubeUrl, this.provider, this.model});
  factory _QuizSource.fromJson(Map<String, dynamic> json) => _$QuizSourceFromJson(json);

@override final  String? contextText;
@override final  String? youtubeUrl;
/// `LlmProviderId.wireName`, e.g. `gemini`.
@override final  String? provider;
@override final  String? model;

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
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _QuizSource&&(identical(other.contextText, contextText) || other.contextText == contextText)&&(identical(other.youtubeUrl, youtubeUrl) || other.youtubeUrl == youtubeUrl)&&(identical(other.provider, provider) || other.provider == provider)&&(identical(other.model, model) || other.model == model));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,contextText,youtubeUrl,provider,model);
}

@override
String toString() {
    return 'QuizSource(contextText: $contextText, youtubeUrl: $youtubeUrl, provider: $provider, model: $model)';
}


}

/// @nodoc
abstract mixin class _$QuizSourceCopyWith<$Res> implements $QuizSourceCopyWith<$Res> {
  factory _$QuizSourceCopyWith(_QuizSource value, $Res Function(_QuizSource) _then) = __$QuizSourceCopyWithImpl;
@override @useResult
$Res call({
 String? contextText, String? youtubeUrl, String? provider, String? model
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
@override @pragma('vm:prefer-inline') $Res call({Object? contextText = freezed,Object? youtubeUrl = freezed,Object? provider = freezed,Object? model = freezed,}) {
  return _then(_QuizSource(
contextText: freezed == contextText ? _self.contextText : contextText // ignore: cast_nullable_to_non_nullable
as String?,youtubeUrl: freezed == youtubeUrl ? _self.youtubeUrl : youtubeUrl // ignore: cast_nullable_to_non_nullable
as String?,provider: freezed == provider ? _self.provider : provider // ignore: cast_nullable_to_non_nullable
as String?,model: freezed == model ? _self.model : model // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
