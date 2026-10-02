// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'drafts.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$QuestionDraft {

 QuestionType get type; String get prompt; List<String> get options; List<int> get correctIndices; String? get answerText; String? get explanation;
/// Create a copy of QuestionDraft
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$QuestionDraftCopyWith<QuestionDraft> get copyWith => _$QuestionDraftCopyWithImpl<QuestionDraft>(this as QuestionDraft, _$identity);

  /// Serializes this QuestionDraft to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as QuestionDraft;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is QuestionDraft&&(identical(other.type, _this.type) || other.type == _this.type)&&(identical(other.prompt, _this.prompt) || other.prompt == _this.prompt)&&const DeepCollectionEquality().equals(other.options, _this.options)&&const DeepCollectionEquality().equals(other.correctIndices, _this.correctIndices)&&(identical(other.answerText, _this.answerText) || other.answerText == _this.answerText)&&(identical(other.explanation, _this.explanation) || other.explanation == _this.explanation));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as QuestionDraft;
  return Object.hash(runtimeType,_this.type,_this.prompt,const DeepCollectionEquality().hash(_this.options),const DeepCollectionEquality().hash(_this.correctIndices),_this.answerText,_this.explanation);
}

@override
String toString() {
  final _this = this as QuestionDraft;
  return 'QuestionDraft(type: ${_this.type}, prompt: ${_this.prompt}, options: ${_this.options}, correctIndices: ${_this.correctIndices}, answerText: ${_this.answerText}, explanation: ${_this.explanation})';
}


}

/// @nodoc
abstract mixin class $QuestionDraftCopyWith<$Res>  {
  factory $QuestionDraftCopyWith(QuestionDraft value, $Res Function(QuestionDraft) _then) = _$QuestionDraftCopyWithImpl;
@useResult
$Res call({
 QuestionType type, String prompt, List<String> options, List<int> correctIndices, String? answerText, String? explanation
});




}
/// @nodoc
class _$QuestionDraftCopyWithImpl<$Res>
    implements $QuestionDraftCopyWith<$Res> {
  _$QuestionDraftCopyWithImpl(this._self, this._then);

  final QuestionDraft _self;
  final $Res Function(QuestionDraft) _then;

/// Create a copy of QuestionDraft
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? type = null,Object? prompt = null,Object? options = null,Object? correctIndices = null,Object? answerText = freezed,Object? explanation = freezed,}) {
  return _then(QuestionDraft(
type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as QuestionType,prompt: null == prompt ? _self.prompt : prompt // ignore: cast_nullable_to_non_nullable
as String,options: null == options ? _self.options : options // ignore: cast_nullable_to_non_nullable
as List<String>,correctIndices: null == correctIndices ? _self.correctIndices : correctIndices // ignore: cast_nullable_to_non_nullable
as List<int>,answerText: freezed == answerText ? _self.answerText : answerText // ignore: cast_nullable_to_non_nullable
as String?,explanation: freezed == explanation ? _self.explanation : explanation // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [QuestionDraft].
extension QuestionDraftPatterns on QuestionDraft {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _QuestionDraft value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _QuestionDraft() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _QuestionDraft value)  $default,){
final _that = this;
switch (_that) {
case _QuestionDraft():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _QuestionDraft value)?  $default,){
final _that = this;
switch (_that) {
case _QuestionDraft() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( QuestionType type,  String prompt,  List<String> options,  List<int> correctIndices,  String? answerText,  String? explanation)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _QuestionDraft() when $default != null:
return $default(_that.type,_that.prompt,_that.options,_that.correctIndices,_that.answerText,_that.explanation);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( QuestionType type,  String prompt,  List<String> options,  List<int> correctIndices,  String? answerText,  String? explanation)  $default,) {final _that = this;
switch (_that) {
case _QuestionDraft():
return $default(_that.type,_that.prompt,_that.options,_that.correctIndices,_that.answerText,_that.explanation);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( QuestionType type,  String prompt,  List<String> options,  List<int> correctIndices,  String? answerText,  String? explanation)?  $default,) {final _that = this;
switch (_that) {
case _QuestionDraft() when $default != null:
return $default(_that.type,_that.prompt,_that.options,_that.correctIndices,_that.answerText,_that.explanation);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _QuestionDraft extends QuestionDraft {
  const _QuestionDraft({required this.type, required this.prompt,  List<String> options = const <String>[],  List<int> correctIndices = const <int>[], this.answerText, this.explanation}): _options = options,_correctIndices = correctIndices,super._();
  factory _QuestionDraft.fromJson(Map<String, dynamic> json) => _$QuestionDraftFromJson(json);

@override final  QuestionType type;
@override final  String prompt;
 final  List<String> _options;
@override@JsonKey() List<String> get options {
  if (_options is EqualUnmodifiableListView) return _options;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_options);
}

 final  List<int> _correctIndices;
@override@JsonKey() List<int> get correctIndices {
  if (_correctIndices is EqualUnmodifiableListView) return _correctIndices;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_correctIndices);
}

@override final  String? answerText;
@override final  String? explanation;

/// Create a copy of QuestionDraft
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$QuestionDraftCopyWith<_QuestionDraft> get copyWith => __$QuestionDraftCopyWithImpl<_QuestionDraft>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$QuestionDraftToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _QuestionDraft&&(identical(other.type, type) || other.type == type)&&(identical(other.prompt, prompt) || other.prompt == prompt)&&const DeepCollectionEquality().equals(other.options, _options)&&const DeepCollectionEquality().equals(other.correctIndices, _correctIndices)&&(identical(other.answerText, answerText) || other.answerText == answerText)&&(identical(other.explanation, explanation) || other.explanation == explanation));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,type,prompt,const DeepCollectionEquality().hash(_options),const DeepCollectionEquality().hash(_correctIndices),answerText,explanation);
}

@override
String toString() {
    return 'QuestionDraft(type: $type, prompt: $prompt, options: $options, correctIndices: $correctIndices, answerText: $answerText, explanation: $explanation)';
}


}

/// @nodoc
abstract mixin class _$QuestionDraftCopyWith<$Res> implements $QuestionDraftCopyWith<$Res> {
  factory _$QuestionDraftCopyWith(_QuestionDraft value, $Res Function(_QuestionDraft) _then) = __$QuestionDraftCopyWithImpl;
@override @useResult
$Res call({
 QuestionType type, String prompt, List<String> options, List<int> correctIndices, String? answerText, String? explanation
});




}
/// @nodoc
class __$QuestionDraftCopyWithImpl<$Res>
    implements _$QuestionDraftCopyWith<$Res> {
  __$QuestionDraftCopyWithImpl(this._self, this._then);

  final _QuestionDraft _self;
  final $Res Function(_QuestionDraft) _then;

/// Create a copy of QuestionDraft
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? type = null,Object? prompt = null,Object? options = null,Object? correctIndices = null,Object? answerText = freezed,Object? explanation = freezed,}) {
  return _then(_QuestionDraft(
type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as QuestionType,prompt: null == prompt ? _self.prompt : prompt // ignore: cast_nullable_to_non_nullable
as String,options: null == options ? _self._options : options // ignore: cast_nullable_to_non_nullable
as List<String>,correctIndices: null == correctIndices ? _self._correctIndices : correctIndices // ignore: cast_nullable_to_non_nullable
as List<int>,answerText: freezed == answerText ? _self.answerText : answerText // ignore: cast_nullable_to_non_nullable
as String?,explanation: freezed == explanation ? _self.explanation : explanation // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}


/// @nodoc
mixin _$QuizDraft {

 String get title; String? get description; List<QuestionDraft> get questions;
/// Create a copy of QuizDraft
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$QuizDraftCopyWith<QuizDraft> get copyWith => _$QuizDraftCopyWithImpl<QuizDraft>(this as QuizDraft, _$identity);

  /// Serializes this QuizDraft to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as QuizDraft;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is QuizDraft&&(identical(other.title, _this.title) || other.title == _this.title)&&(identical(other.description, _this.description) || other.description == _this.description)&&const DeepCollectionEquality().equals(other.questions, _this.questions));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as QuizDraft;
  return Object.hash(runtimeType,_this.title,_this.description,const DeepCollectionEquality().hash(_this.questions));
}

@override
String toString() {
  final _this = this as QuizDraft;
  return 'QuizDraft(title: ${_this.title}, description: ${_this.description}, questions: ${_this.questions})';
}


}

/// @nodoc
abstract mixin class $QuizDraftCopyWith<$Res>  {
  factory $QuizDraftCopyWith(QuizDraft value, $Res Function(QuizDraft) _then) = _$QuizDraftCopyWithImpl;
@useResult
$Res call({
 String title, String? description, List<QuestionDraft> questions
});




}
/// @nodoc
class _$QuizDraftCopyWithImpl<$Res>
    implements $QuizDraftCopyWith<$Res> {
  _$QuizDraftCopyWithImpl(this._self, this._then);

  final QuizDraft _self;
  final $Res Function(QuizDraft) _then;

/// Create a copy of QuizDraft
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? title = null,Object? description = freezed,Object? questions = null,}) {
  return _then(QuizDraft(
title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,questions: null == questions ? _self.questions : questions // ignore: cast_nullable_to_non_nullable
as List<QuestionDraft>,
  ));
}

}


/// Adds pattern-matching-related methods to [QuizDraft].
extension QuizDraftPatterns on QuizDraft {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _QuizDraft value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _QuizDraft() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _QuizDraft value)  $default,){
final _that = this;
switch (_that) {
case _QuizDraft():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _QuizDraft value)?  $default,){
final _that = this;
switch (_that) {
case _QuizDraft() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String title,  String? description,  List<QuestionDraft> questions)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _QuizDraft() when $default != null:
return $default(_that.title,_that.description,_that.questions);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String title,  String? description,  List<QuestionDraft> questions)  $default,) {final _that = this;
switch (_that) {
case _QuizDraft():
return $default(_that.title,_that.description,_that.questions);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String title,  String? description,  List<QuestionDraft> questions)?  $default,) {final _that = this;
switch (_that) {
case _QuizDraft() when $default != null:
return $default(_that.title,_that.description,_that.questions);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _QuizDraft extends QuizDraft {
  const _QuizDraft({required this.title, this.description,  List<QuestionDraft> questions = const <QuestionDraft>[]}): _questions = questions,super._();
  factory _QuizDraft.fromJson(Map<String, dynamic> json) => _$QuizDraftFromJson(json);

@override final  String title;
@override final  String? description;
 final  List<QuestionDraft> _questions;
@override@JsonKey() List<QuestionDraft> get questions {
  if (_questions is EqualUnmodifiableListView) return _questions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_questions);
}


/// Create a copy of QuizDraft
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$QuizDraftCopyWith<_QuizDraft> get copyWith => __$QuizDraftCopyWithImpl<_QuizDraft>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$QuizDraftToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _QuizDraft&&(identical(other.title, title) || other.title == title)&&(identical(other.description, description) || other.description == description)&&const DeepCollectionEquality().equals(other.questions, _questions));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,title,description,const DeepCollectionEquality().hash(_questions));
}

@override
String toString() {
    return 'QuizDraft(title: $title, description: $description, questions: $questions)';
}


}

/// @nodoc
abstract mixin class _$QuizDraftCopyWith<$Res> implements $QuizDraftCopyWith<$Res> {
  factory _$QuizDraftCopyWith(_QuizDraft value, $Res Function(_QuizDraft) _then) = __$QuizDraftCopyWithImpl;
@override @useResult
$Res call({
 String title, String? description, List<QuestionDraft> questions
});




}
/// @nodoc
class __$QuizDraftCopyWithImpl<$Res>
    implements _$QuizDraftCopyWith<$Res> {
  __$QuizDraftCopyWithImpl(this._self, this._then);

  final _QuizDraft _self;
  final $Res Function(_QuizDraft) _then;

/// Create a copy of QuizDraft
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? title = null,Object? description = freezed,Object? questions = null,}) {
  return _then(_QuizDraft(
title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,questions: null == questions ? _self._questions : questions // ignore: cast_nullable_to_non_nullable
as List<QuestionDraft>,
  ));
}


}


/// @nodoc
mixin _$NoteDraft {

 String get title; String get contentMarkdown;
/// Create a copy of NoteDraft
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NoteDraftCopyWith<NoteDraft> get copyWith => _$NoteDraftCopyWithImpl<NoteDraft>(this as NoteDraft, _$identity);

  /// Serializes this NoteDraft to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as NoteDraft;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NoteDraft&&(identical(other.title, _this.title) || other.title == _this.title)&&(identical(other.contentMarkdown, _this.contentMarkdown) || other.contentMarkdown == _this.contentMarkdown));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as NoteDraft;
  return Object.hash(runtimeType,_this.title,_this.contentMarkdown);
}

@override
String toString() {
  final _this = this as NoteDraft;
  return 'NoteDraft(title: ${_this.title}, contentMarkdown: ${_this.contentMarkdown})';
}


}

/// @nodoc
abstract mixin class $NoteDraftCopyWith<$Res>  {
  factory $NoteDraftCopyWith(NoteDraft value, $Res Function(NoteDraft) _then) = _$NoteDraftCopyWithImpl;
@useResult
$Res call({
 String title, String contentMarkdown
});




}
/// @nodoc
class _$NoteDraftCopyWithImpl<$Res>
    implements $NoteDraftCopyWith<$Res> {
  _$NoteDraftCopyWithImpl(this._self, this._then);

  final NoteDraft _self;
  final $Res Function(NoteDraft) _then;

/// Create a copy of NoteDraft
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? title = null,Object? contentMarkdown = null,}) {
  return _then(NoteDraft(
title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,contentMarkdown: null == contentMarkdown ? _self.contentMarkdown : contentMarkdown // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [NoteDraft].
extension NoteDraftPatterns on NoteDraft {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _NoteDraft value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _NoteDraft() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _NoteDraft value)  $default,){
final _that = this;
switch (_that) {
case _NoteDraft():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _NoteDraft value)?  $default,){
final _that = this;
switch (_that) {
case _NoteDraft() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String title,  String contentMarkdown)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _NoteDraft() when $default != null:
return $default(_that.title,_that.contentMarkdown);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String title,  String contentMarkdown)  $default,) {final _that = this;
switch (_that) {
case _NoteDraft():
return $default(_that.title,_that.contentMarkdown);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String title,  String contentMarkdown)?  $default,) {final _that = this;
switch (_that) {
case _NoteDraft() when $default != null:
return $default(_that.title,_that.contentMarkdown);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _NoteDraft implements NoteDraft {
  const _NoteDraft({required this.title, required this.contentMarkdown});
  factory _NoteDraft.fromJson(Map<String, dynamic> json) => _$NoteDraftFromJson(json);

@override final  String title;
@override final  String contentMarkdown;

/// Create a copy of NoteDraft
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$NoteDraftCopyWith<_NoteDraft> get copyWith => __$NoteDraftCopyWithImpl<_NoteDraft>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$NoteDraftToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _NoteDraft&&(identical(other.title, title) || other.title == title)&&(identical(other.contentMarkdown, contentMarkdown) || other.contentMarkdown == contentMarkdown));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,title,contentMarkdown);
}

@override
String toString() {
    return 'NoteDraft(title: $title, contentMarkdown: $contentMarkdown)';
}


}

/// @nodoc
abstract mixin class _$NoteDraftCopyWith<$Res> implements $NoteDraftCopyWith<$Res> {
  factory _$NoteDraftCopyWith(_NoteDraft value, $Res Function(_NoteDraft) _then) = __$NoteDraftCopyWithImpl;
@override @useResult
$Res call({
 String title, String contentMarkdown
});




}
/// @nodoc
class __$NoteDraftCopyWithImpl<$Res>
    implements _$NoteDraftCopyWith<$Res> {
  __$NoteDraftCopyWithImpl(this._self, this._then);

  final _NoteDraft _self;
  final $Res Function(_NoteDraft) _then;

/// Create a copy of NoteDraft
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? title = null,Object? contentMarkdown = null,}) {
  return _then(_NoteDraft(
title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,contentMarkdown: null == contentMarkdown ? _self.contentMarkdown : contentMarkdown // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
