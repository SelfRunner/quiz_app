// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'ai_service.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$QuizGenerationRequest {

/// Pasted source material. At least one of [contextText]/[youtubeUrl].
 String? get contextText; String? get youtubeUrl; int get questionCount; Set<QuestionType> get questionTypes; Difficulty get difficulty;/// Output language (e.g. `en`); null = same as the source.
 String? get language; String? get extraInstructions;/// Subject or note title, gives the model context (optional).
 String? get topic;/// Overrides; null = selection from `ApiKeyStore`.
 LlmProviderId? get providerId; String? get model;
/// Create a copy of QuizGenerationRequest
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$QuizGenerationRequestCopyWith<QuizGenerationRequest> get copyWith => _$QuizGenerationRequestCopyWithImpl<QuizGenerationRequest>(this as QuizGenerationRequest, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as QuizGenerationRequest;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is QuizGenerationRequest&&(identical(other.contextText, _this.contextText) || other.contextText == _this.contextText)&&(identical(other.youtubeUrl, _this.youtubeUrl) || other.youtubeUrl == _this.youtubeUrl)&&(identical(other.questionCount, _this.questionCount) || other.questionCount == _this.questionCount)&&const DeepCollectionEquality().equals(other.questionTypes, _this.questionTypes)&&(identical(other.difficulty, _this.difficulty) || other.difficulty == _this.difficulty)&&(identical(other.language, _this.language) || other.language == _this.language)&&(identical(other.extraInstructions, _this.extraInstructions) || other.extraInstructions == _this.extraInstructions)&&(identical(other.topic, _this.topic) || other.topic == _this.topic)&&(identical(other.providerId, _this.providerId) || other.providerId == _this.providerId)&&(identical(other.model, _this.model) || other.model == _this.model));
}


@override
int get hashCode {
  final _this = this as QuizGenerationRequest;
  return Object.hash(runtimeType,_this.contextText,_this.youtubeUrl,_this.questionCount,const DeepCollectionEquality().hash(_this.questionTypes),_this.difficulty,_this.language,_this.extraInstructions,_this.topic,_this.providerId,_this.model);
}

@override
String toString() {
  final _this = this as QuizGenerationRequest;
  return 'QuizGenerationRequest(contextText: ${_this.contextText}, youtubeUrl: ${_this.youtubeUrl}, questionCount: ${_this.questionCount}, questionTypes: ${_this.questionTypes}, difficulty: ${_this.difficulty}, language: ${_this.language}, extraInstructions: ${_this.extraInstructions}, topic: ${_this.topic}, providerId: ${_this.providerId}, model: ${_this.model})';
}


}

/// @nodoc
abstract mixin class $QuizGenerationRequestCopyWith<$Res>  {
  factory $QuizGenerationRequestCopyWith(QuizGenerationRequest value, $Res Function(QuizGenerationRequest) _then) = _$QuizGenerationRequestCopyWithImpl;
@useResult
$Res call({
 String? contextText, String? youtubeUrl, int questionCount, Set<QuestionType> questionTypes, Difficulty difficulty, String? language, String? extraInstructions, String? topic, LlmProviderId? providerId, String? model
});




}
/// @nodoc
class _$QuizGenerationRequestCopyWithImpl<$Res>
    implements $QuizGenerationRequestCopyWith<$Res> {
  _$QuizGenerationRequestCopyWithImpl(this._self, this._then);

  final QuizGenerationRequest _self;
  final $Res Function(QuizGenerationRequest) _then;

/// Create a copy of QuizGenerationRequest
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? contextText = freezed,Object? youtubeUrl = freezed,Object? questionCount = null,Object? questionTypes = null,Object? difficulty = null,Object? language = freezed,Object? extraInstructions = freezed,Object? topic = freezed,Object? providerId = freezed,Object? model = freezed,}) {
  return _then(QuizGenerationRequest(
contextText: freezed == contextText ? _self.contextText : contextText // ignore: cast_nullable_to_non_nullable
as String?,youtubeUrl: freezed == youtubeUrl ? _self.youtubeUrl : youtubeUrl // ignore: cast_nullable_to_non_nullable
as String?,questionCount: null == questionCount ? _self.questionCount : questionCount // ignore: cast_nullable_to_non_nullable
as int,questionTypes: null == questionTypes ? _self.questionTypes : questionTypes // ignore: cast_nullable_to_non_nullable
as Set<QuestionType>,difficulty: null == difficulty ? _self.difficulty : difficulty // ignore: cast_nullable_to_non_nullable
as Difficulty,language: freezed == language ? _self.language : language // ignore: cast_nullable_to_non_nullable
as String?,extraInstructions: freezed == extraInstructions ? _self.extraInstructions : extraInstructions // ignore: cast_nullable_to_non_nullable
as String?,topic: freezed == topic ? _self.topic : topic // ignore: cast_nullable_to_non_nullable
as String?,providerId: freezed == providerId ? _self.providerId : providerId // ignore: cast_nullable_to_non_nullable
as LlmProviderId?,model: freezed == model ? _self.model : model // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [QuizGenerationRequest].
extension QuizGenerationRequestPatterns on QuizGenerationRequest {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _QuizGenerationRequest value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _QuizGenerationRequest() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _QuizGenerationRequest value)  $default,){
final _that = this;
switch (_that) {
case _QuizGenerationRequest():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _QuizGenerationRequest value)?  $default,){
final _that = this;
switch (_that) {
case _QuizGenerationRequest() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String? contextText,  String? youtubeUrl,  int questionCount,  Set<QuestionType> questionTypes,  Difficulty difficulty,  String? language,  String? extraInstructions,  String? topic,  LlmProviderId? providerId,  String? model)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _QuizGenerationRequest() when $default != null:
return $default(_that.contextText,_that.youtubeUrl,_that.questionCount,_that.questionTypes,_that.difficulty,_that.language,_that.extraInstructions,_that.topic,_that.providerId,_that.model);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String? contextText,  String? youtubeUrl,  int questionCount,  Set<QuestionType> questionTypes,  Difficulty difficulty,  String? language,  String? extraInstructions,  String? topic,  LlmProviderId? providerId,  String? model)  $default,) {final _that = this;
switch (_that) {
case _QuizGenerationRequest():
return $default(_that.contextText,_that.youtubeUrl,_that.questionCount,_that.questionTypes,_that.difficulty,_that.language,_that.extraInstructions,_that.topic,_that.providerId,_that.model);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String? contextText,  String? youtubeUrl,  int questionCount,  Set<QuestionType> questionTypes,  Difficulty difficulty,  String? language,  String? extraInstructions,  String? topic,  LlmProviderId? providerId,  String? model)?  $default,) {final _that = this;
switch (_that) {
case _QuizGenerationRequest() when $default != null:
return $default(_that.contextText,_that.youtubeUrl,_that.questionCount,_that.questionTypes,_that.difficulty,_that.language,_that.extraInstructions,_that.topic,_that.providerId,_that.model);case _:
  return null;

}
}

}

/// @nodoc


class _QuizGenerationRequest implements QuizGenerationRequest {
  const _QuizGenerationRequest({this.contextText, this.youtubeUrl, this.questionCount = 10,  Set<QuestionType> questionTypes = const {QuestionType.mcqSingle, QuestionType.mcqMulti, QuestionType.trueFalse, QuestionType.shortAnswer}, this.difficulty = Difficulty.medium, this.language, this.extraInstructions, this.topic, this.providerId, this.model}): _questionTypes = questionTypes;
  

/// Pasted source material. At least one of [contextText]/[youtubeUrl].
@override final  String? contextText;
@override final  String? youtubeUrl;
@override@JsonKey() final  int questionCount;
 final  Set<QuestionType> _questionTypes;
@override@JsonKey() Set<QuestionType> get questionTypes {
  if (_questionTypes is EqualUnmodifiableSetView) return _questionTypes;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableSetView(_questionTypes);
}

@override@JsonKey() final  Difficulty difficulty;
/// Output language (e.g. `en`); null = same as the source.
@override final  String? language;
@override final  String? extraInstructions;
/// Subject or note title, gives the model context (optional).
@override final  String? topic;
/// Overrides; null = selection from `ApiKeyStore`.
@override final  LlmProviderId? providerId;
@override final  String? model;

/// Create a copy of QuizGenerationRequest
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$QuizGenerationRequestCopyWith<_QuizGenerationRequest> get copyWith => __$QuizGenerationRequestCopyWithImpl<_QuizGenerationRequest>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _QuizGenerationRequest&&(identical(other.contextText, contextText) || other.contextText == contextText)&&(identical(other.youtubeUrl, youtubeUrl) || other.youtubeUrl == youtubeUrl)&&(identical(other.questionCount, questionCount) || other.questionCount == questionCount)&&const DeepCollectionEquality().equals(other.questionTypes, _questionTypes)&&(identical(other.difficulty, difficulty) || other.difficulty == difficulty)&&(identical(other.language, language) || other.language == language)&&(identical(other.extraInstructions, extraInstructions) || other.extraInstructions == extraInstructions)&&(identical(other.topic, topic) || other.topic == topic)&&(identical(other.providerId, providerId) || other.providerId == providerId)&&(identical(other.model, model) || other.model == model));
}


@override
int get hashCode {
    return Object.hash(runtimeType,contextText,youtubeUrl,questionCount,const DeepCollectionEquality().hash(_questionTypes),difficulty,language,extraInstructions,topic,providerId,model);
}

@override
String toString() {
    return 'QuizGenerationRequest(contextText: $contextText, youtubeUrl: $youtubeUrl, questionCount: $questionCount, questionTypes: $questionTypes, difficulty: $difficulty, language: $language, extraInstructions: $extraInstructions, topic: $topic, providerId: $providerId, model: $model)';
}


}

/// @nodoc
abstract mixin class _$QuizGenerationRequestCopyWith<$Res> implements $QuizGenerationRequestCopyWith<$Res> {
  factory _$QuizGenerationRequestCopyWith(_QuizGenerationRequest value, $Res Function(_QuizGenerationRequest) _then) = __$QuizGenerationRequestCopyWithImpl;
@override @useResult
$Res call({
 String? contextText, String? youtubeUrl, int questionCount, Set<QuestionType> questionTypes, Difficulty difficulty, String? language, String? extraInstructions, String? topic, LlmProviderId? providerId, String? model
});




}
/// @nodoc
class __$QuizGenerationRequestCopyWithImpl<$Res>
    implements _$QuizGenerationRequestCopyWith<$Res> {
  __$QuizGenerationRequestCopyWithImpl(this._self, this._then);

  final _QuizGenerationRequest _self;
  final $Res Function(_QuizGenerationRequest) _then;

/// Create a copy of QuizGenerationRequest
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? contextText = freezed,Object? youtubeUrl = freezed,Object? questionCount = null,Object? questionTypes = null,Object? difficulty = null,Object? language = freezed,Object? extraInstructions = freezed,Object? topic = freezed,Object? providerId = freezed,Object? model = freezed,}) {
  return _then(_QuizGenerationRequest(
contextText: freezed == contextText ? _self.contextText : contextText // ignore: cast_nullable_to_non_nullable
as String?,youtubeUrl: freezed == youtubeUrl ? _self.youtubeUrl : youtubeUrl // ignore: cast_nullable_to_non_nullable
as String?,questionCount: null == questionCount ? _self.questionCount : questionCount // ignore: cast_nullable_to_non_nullable
as int,questionTypes: null == questionTypes ? _self._questionTypes : questionTypes // ignore: cast_nullable_to_non_nullable
as Set<QuestionType>,difficulty: null == difficulty ? _self.difficulty : difficulty // ignore: cast_nullable_to_non_nullable
as Difficulty,language: freezed == language ? _self.language : language // ignore: cast_nullable_to_non_nullable
as String?,extraInstructions: freezed == extraInstructions ? _self.extraInstructions : extraInstructions // ignore: cast_nullable_to_non_nullable
as String?,topic: freezed == topic ? _self.topic : topic // ignore: cast_nullable_to_non_nullable
as String?,providerId: freezed == providerId ? _self.providerId : providerId // ignore: cast_nullable_to_non_nullable
as LlmProviderId?,model: freezed == model ? _self.model : model // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc
mixin _$NoteGenerationRequest {

 String? get contextText; String? get youtubeUrl; String? get language;/// e.g. "concise summary", "detailed study notes with headings".
 String? get extraInstructions;/// Subject title, gives the model context (optional).
 String? get topic; LlmProviderId? get providerId; String? get model;
/// Create a copy of NoteGenerationRequest
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NoteGenerationRequestCopyWith<NoteGenerationRequest> get copyWith => _$NoteGenerationRequestCopyWithImpl<NoteGenerationRequest>(this as NoteGenerationRequest, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as NoteGenerationRequest;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NoteGenerationRequest&&(identical(other.contextText, _this.contextText) || other.contextText == _this.contextText)&&(identical(other.youtubeUrl, _this.youtubeUrl) || other.youtubeUrl == _this.youtubeUrl)&&(identical(other.language, _this.language) || other.language == _this.language)&&(identical(other.extraInstructions, _this.extraInstructions) || other.extraInstructions == _this.extraInstructions)&&(identical(other.topic, _this.topic) || other.topic == _this.topic)&&(identical(other.providerId, _this.providerId) || other.providerId == _this.providerId)&&(identical(other.model, _this.model) || other.model == _this.model));
}


@override
int get hashCode {
  final _this = this as NoteGenerationRequest;
  return Object.hash(runtimeType,_this.contextText,_this.youtubeUrl,_this.language,_this.extraInstructions,_this.topic,_this.providerId,_this.model);
}

@override
String toString() {
  final _this = this as NoteGenerationRequest;
  return 'NoteGenerationRequest(contextText: ${_this.contextText}, youtubeUrl: ${_this.youtubeUrl}, language: ${_this.language}, extraInstructions: ${_this.extraInstructions}, topic: ${_this.topic}, providerId: ${_this.providerId}, model: ${_this.model})';
}


}

/// @nodoc
abstract mixin class $NoteGenerationRequestCopyWith<$Res>  {
  factory $NoteGenerationRequestCopyWith(NoteGenerationRequest value, $Res Function(NoteGenerationRequest) _then) = _$NoteGenerationRequestCopyWithImpl;
@useResult
$Res call({
 String? contextText, String? youtubeUrl, String? language, String? extraInstructions, String? topic, LlmProviderId? providerId, String? model
});




}
/// @nodoc
class _$NoteGenerationRequestCopyWithImpl<$Res>
    implements $NoteGenerationRequestCopyWith<$Res> {
  _$NoteGenerationRequestCopyWithImpl(this._self, this._then);

  final NoteGenerationRequest _self;
  final $Res Function(NoteGenerationRequest) _then;

/// Create a copy of NoteGenerationRequest
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? contextText = freezed,Object? youtubeUrl = freezed,Object? language = freezed,Object? extraInstructions = freezed,Object? topic = freezed,Object? providerId = freezed,Object? model = freezed,}) {
  return _then(NoteGenerationRequest(
contextText: freezed == contextText ? _self.contextText : contextText // ignore: cast_nullable_to_non_nullable
as String?,youtubeUrl: freezed == youtubeUrl ? _self.youtubeUrl : youtubeUrl // ignore: cast_nullable_to_non_nullable
as String?,language: freezed == language ? _self.language : language // ignore: cast_nullable_to_non_nullable
as String?,extraInstructions: freezed == extraInstructions ? _self.extraInstructions : extraInstructions // ignore: cast_nullable_to_non_nullable
as String?,topic: freezed == topic ? _self.topic : topic // ignore: cast_nullable_to_non_nullable
as String?,providerId: freezed == providerId ? _self.providerId : providerId // ignore: cast_nullable_to_non_nullable
as LlmProviderId?,model: freezed == model ? _self.model : model // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [NoteGenerationRequest].
extension NoteGenerationRequestPatterns on NoteGenerationRequest {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _NoteGenerationRequest value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _NoteGenerationRequest() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _NoteGenerationRequest value)  $default,){
final _that = this;
switch (_that) {
case _NoteGenerationRequest():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _NoteGenerationRequest value)?  $default,){
final _that = this;
switch (_that) {
case _NoteGenerationRequest() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String? contextText,  String? youtubeUrl,  String? language,  String? extraInstructions,  String? topic,  LlmProviderId? providerId,  String? model)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _NoteGenerationRequest() when $default != null:
return $default(_that.contextText,_that.youtubeUrl,_that.language,_that.extraInstructions,_that.topic,_that.providerId,_that.model);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String? contextText,  String? youtubeUrl,  String? language,  String? extraInstructions,  String? topic,  LlmProviderId? providerId,  String? model)  $default,) {final _that = this;
switch (_that) {
case _NoteGenerationRequest():
return $default(_that.contextText,_that.youtubeUrl,_that.language,_that.extraInstructions,_that.topic,_that.providerId,_that.model);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String? contextText,  String? youtubeUrl,  String? language,  String? extraInstructions,  String? topic,  LlmProviderId? providerId,  String? model)?  $default,) {final _that = this;
switch (_that) {
case _NoteGenerationRequest() when $default != null:
return $default(_that.contextText,_that.youtubeUrl,_that.language,_that.extraInstructions,_that.topic,_that.providerId,_that.model);case _:
  return null;

}
}

}

/// @nodoc


class _NoteGenerationRequest implements NoteGenerationRequest {
  const _NoteGenerationRequest({this.contextText, this.youtubeUrl, this.language, this.extraInstructions, this.topic, this.providerId, this.model});
  

@override final  String? contextText;
@override final  String? youtubeUrl;
@override final  String? language;
/// e.g. "concise summary", "detailed study notes with headings".
@override final  String? extraInstructions;
/// Subject title, gives the model context (optional).
@override final  String? topic;
@override final  LlmProviderId? providerId;
@override final  String? model;

/// Create a copy of NoteGenerationRequest
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$NoteGenerationRequestCopyWith<_NoteGenerationRequest> get copyWith => __$NoteGenerationRequestCopyWithImpl<_NoteGenerationRequest>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _NoteGenerationRequest&&(identical(other.contextText, contextText) || other.contextText == contextText)&&(identical(other.youtubeUrl, youtubeUrl) || other.youtubeUrl == youtubeUrl)&&(identical(other.language, language) || other.language == language)&&(identical(other.extraInstructions, extraInstructions) || other.extraInstructions == extraInstructions)&&(identical(other.topic, topic) || other.topic == topic)&&(identical(other.providerId, providerId) || other.providerId == providerId)&&(identical(other.model, model) || other.model == model));
}


@override
int get hashCode {
    return Object.hash(runtimeType,contextText,youtubeUrl,language,extraInstructions,topic,providerId,model);
}

@override
String toString() {
    return 'NoteGenerationRequest(contextText: $contextText, youtubeUrl: $youtubeUrl, language: $language, extraInstructions: $extraInstructions, topic: $topic, providerId: $providerId, model: $model)';
}


}

/// @nodoc
abstract mixin class _$NoteGenerationRequestCopyWith<$Res> implements $NoteGenerationRequestCopyWith<$Res> {
  factory _$NoteGenerationRequestCopyWith(_NoteGenerationRequest value, $Res Function(_NoteGenerationRequest) _then) = __$NoteGenerationRequestCopyWithImpl;
@override @useResult
$Res call({
 String? contextText, String? youtubeUrl, String? language, String? extraInstructions, String? topic, LlmProviderId? providerId, String? model
});




}
/// @nodoc
class __$NoteGenerationRequestCopyWithImpl<$Res>
    implements _$NoteGenerationRequestCopyWith<$Res> {
  __$NoteGenerationRequestCopyWithImpl(this._self, this._then);

  final _NoteGenerationRequest _self;
  final $Res Function(_NoteGenerationRequest) _then;

/// Create a copy of NoteGenerationRequest
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? contextText = freezed,Object? youtubeUrl = freezed,Object? language = freezed,Object? extraInstructions = freezed,Object? topic = freezed,Object? providerId = freezed,Object? model = freezed,}) {
  return _then(_NoteGenerationRequest(
contextText: freezed == contextText ? _self.contextText : contextText // ignore: cast_nullable_to_non_nullable
as String?,youtubeUrl: freezed == youtubeUrl ? _self.youtubeUrl : youtubeUrl // ignore: cast_nullable_to_non_nullable
as String?,language: freezed == language ? _self.language : language // ignore: cast_nullable_to_non_nullable
as String?,extraInstructions: freezed == extraInstructions ? _self.extraInstructions : extraInstructions // ignore: cast_nullable_to_non_nullable
as String?,topic: freezed == topic ? _self.topic : topic // ignore: cast_nullable_to_non_nullable
as String?,providerId: freezed == providerId ? _self.providerId : providerId // ignore: cast_nullable_to_non_nullable
as LlmProviderId?,model: freezed == model ? _self.model : model // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
