// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'quiz_attempt.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$QuestionAnswer {

 String get questionId;/// Selected option indices (MCQ / true-false).
 List<int> get selectedIndices;/// Typed answer (short answer); optional for self-graded flashcards.
 String? get textAnswer;/// Auto-graded for option questions; self-graded for short answer.
/// Null = not answered / not graded yet.
 bool? get isCorrect;
/// Create a copy of QuestionAnswer
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$QuestionAnswerCopyWith<QuestionAnswer> get copyWith => _$QuestionAnswerCopyWithImpl<QuestionAnswer>(this as QuestionAnswer, _$identity);

  /// Serializes this QuestionAnswer to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as QuestionAnswer;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is QuestionAnswer&&(identical(other.questionId, _this.questionId) || other.questionId == _this.questionId)&&const DeepCollectionEquality().equals(other.selectedIndices, _this.selectedIndices)&&(identical(other.textAnswer, _this.textAnswer) || other.textAnswer == _this.textAnswer)&&(identical(other.isCorrect, _this.isCorrect) || other.isCorrect == _this.isCorrect));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as QuestionAnswer;
  return Object.hash(runtimeType,_this.questionId,const DeepCollectionEquality().hash(_this.selectedIndices),_this.textAnswer,_this.isCorrect);
}

@override
String toString() {
  final _this = this as QuestionAnswer;
  return 'QuestionAnswer(questionId: ${_this.questionId}, selectedIndices: ${_this.selectedIndices}, textAnswer: ${_this.textAnswer}, isCorrect: ${_this.isCorrect})';
}


}

/// @nodoc
abstract mixin class $QuestionAnswerCopyWith<$Res>  {
  factory $QuestionAnswerCopyWith(QuestionAnswer value, $Res Function(QuestionAnswer) _then) = _$QuestionAnswerCopyWithImpl;
@useResult
$Res call({
 String questionId, List<int> selectedIndices, String? textAnswer, bool? isCorrect
});




}
/// @nodoc
class _$QuestionAnswerCopyWithImpl<$Res>
    implements $QuestionAnswerCopyWith<$Res> {
  _$QuestionAnswerCopyWithImpl(this._self, this._then);

  final QuestionAnswer _self;
  final $Res Function(QuestionAnswer) _then;

/// Create a copy of QuestionAnswer
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? questionId = null,Object? selectedIndices = null,Object? textAnswer = freezed,Object? isCorrect = freezed,}) {
  return _then(QuestionAnswer(
questionId: null == questionId ? _self.questionId : questionId // ignore: cast_nullable_to_non_nullable
as String,selectedIndices: null == selectedIndices ? _self.selectedIndices : selectedIndices // ignore: cast_nullable_to_non_nullable
as List<int>,textAnswer: freezed == textAnswer ? _self.textAnswer : textAnswer // ignore: cast_nullable_to_non_nullable
as String?,isCorrect: freezed == isCorrect ? _self.isCorrect : isCorrect // ignore: cast_nullable_to_non_nullable
as bool?,
  ));
}

}


/// Adds pattern-matching-related methods to [QuestionAnswer].
extension QuestionAnswerPatterns on QuestionAnswer {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _QuestionAnswer value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _QuestionAnswer() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _QuestionAnswer value)  $default,){
final _that = this;
switch (_that) {
case _QuestionAnswer():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _QuestionAnswer value)?  $default,){
final _that = this;
switch (_that) {
case _QuestionAnswer() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String questionId,  List<int> selectedIndices,  String? textAnswer,  bool? isCorrect)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _QuestionAnswer() when $default != null:
return $default(_that.questionId,_that.selectedIndices,_that.textAnswer,_that.isCorrect);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String questionId,  List<int> selectedIndices,  String? textAnswer,  bool? isCorrect)  $default,) {final _that = this;
switch (_that) {
case _QuestionAnswer():
return $default(_that.questionId,_that.selectedIndices,_that.textAnswer,_that.isCorrect);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String questionId,  List<int> selectedIndices,  String? textAnswer,  bool? isCorrect)?  $default,) {final _that = this;
switch (_that) {
case _QuestionAnswer() when $default != null:
return $default(_that.questionId,_that.selectedIndices,_that.textAnswer,_that.isCorrect);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _QuestionAnswer implements QuestionAnswer {
  const _QuestionAnswer({required this.questionId,  List<int> selectedIndices = const <int>[], this.textAnswer, this.isCorrect}): _selectedIndices = selectedIndices;
  factory _QuestionAnswer.fromJson(Map<String, dynamic> json) => _$QuestionAnswerFromJson(json);

@override final  String questionId;
/// Selected option indices (MCQ / true-false).
 final  List<int> _selectedIndices;
/// Selected option indices (MCQ / true-false).
@override@JsonKey() List<int> get selectedIndices {
  if (_selectedIndices is EqualUnmodifiableListView) return _selectedIndices;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_selectedIndices);
}

/// Typed answer (short answer); optional for self-graded flashcards.
@override final  String? textAnswer;
/// Auto-graded for option questions; self-graded for short answer.
/// Null = not answered / not graded yet.
@override final  bool? isCorrect;

/// Create a copy of QuestionAnswer
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$QuestionAnswerCopyWith<_QuestionAnswer> get copyWith => __$QuestionAnswerCopyWithImpl<_QuestionAnswer>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$QuestionAnswerToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _QuestionAnswer&&(identical(other.questionId, questionId) || other.questionId == questionId)&&const DeepCollectionEquality().equals(other.selectedIndices, _selectedIndices)&&(identical(other.textAnswer, textAnswer) || other.textAnswer == textAnswer)&&(identical(other.isCorrect, isCorrect) || other.isCorrect == isCorrect));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,questionId,const DeepCollectionEquality().hash(_selectedIndices),textAnswer,isCorrect);
}

@override
String toString() {
    return 'QuestionAnswer(questionId: $questionId, selectedIndices: $selectedIndices, textAnswer: $textAnswer, isCorrect: $isCorrect)';
}


}

/// @nodoc
abstract mixin class _$QuestionAnswerCopyWith<$Res> implements $QuestionAnswerCopyWith<$Res> {
  factory _$QuestionAnswerCopyWith(_QuestionAnswer value, $Res Function(_QuestionAnswer) _then) = __$QuestionAnswerCopyWithImpl;
@override @useResult
$Res call({
 String questionId, List<int> selectedIndices, String? textAnswer, bool? isCorrect
});




}
/// @nodoc
class __$QuestionAnswerCopyWithImpl<$Res>
    implements _$QuestionAnswerCopyWith<$Res> {
  __$QuestionAnswerCopyWithImpl(this._self, this._then);

  final _QuestionAnswer _self;
  final $Res Function(_QuestionAnswer) _then;

/// Create a copy of QuestionAnswer
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? questionId = null,Object? selectedIndices = null,Object? textAnswer = freezed,Object? isCorrect = freezed,}) {
  return _then(_QuestionAnswer(
questionId: null == questionId ? _self.questionId : questionId // ignore: cast_nullable_to_non_nullable
as String,selectedIndices: null == selectedIndices ? _self._selectedIndices : selectedIndices // ignore: cast_nullable_to_non_nullable
as List<int>,textAnswer: freezed == textAnswer ? _self.textAnswer : textAnswer // ignore: cast_nullable_to_non_nullable
as String?,isCorrect: freezed == isCorrect ? _self.isCorrect : isCorrect // ignore: cast_nullable_to_non_nullable
as bool?,
  ));
}


}


/// @nodoc
mixin _$QuizAttempt {

 String get id; String get quizId;/// The attempting user (column `owner_id`).
 String get ownerId; List<QuestionAnswer> get answers;/// Number of correct answers (double to allow partial credit later).
 double get score;/// Number of questions in the quiz at attempt time.
 int get total; DateTime get startedAt;/// Null while in progress.
 DateTime? get completedAt;/// Practice (default), exam or mistakes. Unknown values -> practice.
@JsonKey(unknownEnumValue: AttemptMode.practice) AttemptMode get mode;/// Exam time limit; null = untimed.
 int? get timeLimitSeconds;/// Question ids served, in order (random pool subset); null = all
/// questions of the quiz.
 List<String>? get questionIds;/// Time actually spent, in seconds (set on completion).
 int? get durationSeconds; DateTime get createdAt; DateTime get updatedAt; DateTime? get deletedAt;
/// Create a copy of QuizAttempt
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$QuizAttemptCopyWith<QuizAttempt> get copyWith => _$QuizAttemptCopyWithImpl<QuizAttempt>(this as QuizAttempt, _$identity);

  /// Serializes this QuizAttempt to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as QuizAttempt;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is QuizAttempt&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.quizId, _this.quizId) || other.quizId == _this.quizId)&&(identical(other.ownerId, _this.ownerId) || other.ownerId == _this.ownerId)&&const DeepCollectionEquality().equals(other.answers, _this.answers)&&(identical(other.score, _this.score) || other.score == _this.score)&&(identical(other.total, _this.total) || other.total == _this.total)&&(identical(other.startedAt, _this.startedAt) || other.startedAt == _this.startedAt)&&(identical(other.completedAt, _this.completedAt) || other.completedAt == _this.completedAt)&&(identical(other.mode, _this.mode) || other.mode == _this.mode)&&(identical(other.timeLimitSeconds, _this.timeLimitSeconds) || other.timeLimitSeconds == _this.timeLimitSeconds)&&const DeepCollectionEquality().equals(other.questionIds, _this.questionIds)&&(identical(other.durationSeconds, _this.durationSeconds) || other.durationSeconds == _this.durationSeconds)&&(identical(other.createdAt, _this.createdAt) || other.createdAt == _this.createdAt)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt)&&(identical(other.deletedAt, _this.deletedAt) || other.deletedAt == _this.deletedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as QuizAttempt;
  return Object.hash(runtimeType,_this.id,_this.quizId,_this.ownerId,const DeepCollectionEquality().hash(_this.answers),_this.score,_this.total,_this.startedAt,_this.completedAt,_this.mode,_this.timeLimitSeconds,const DeepCollectionEquality().hash(_this.questionIds),_this.durationSeconds,_this.createdAt,_this.updatedAt,_this.deletedAt);
}

@override
String toString() {
  final _this = this as QuizAttempt;
  return 'QuizAttempt(id: ${_this.id}, quizId: ${_this.quizId}, ownerId: ${_this.ownerId}, answers: ${_this.answers}, score: ${_this.score}, total: ${_this.total}, startedAt: ${_this.startedAt}, completedAt: ${_this.completedAt}, mode: ${_this.mode}, timeLimitSeconds: ${_this.timeLimitSeconds}, questionIds: ${_this.questionIds}, durationSeconds: ${_this.durationSeconds}, createdAt: ${_this.createdAt}, updatedAt: ${_this.updatedAt}, deletedAt: ${_this.deletedAt})';
}


}

/// @nodoc
abstract mixin class $QuizAttemptCopyWith<$Res>  {
  factory $QuizAttemptCopyWith(QuizAttempt value, $Res Function(QuizAttempt) _then) = _$QuizAttemptCopyWithImpl;
@useResult
$Res call({
 String id, String quizId, String ownerId, List<QuestionAnswer> answers, double score, int total, DateTime startedAt, DateTime? completedAt,@JsonKey(unknownEnumValue: AttemptMode.practice) AttemptMode mode, int? timeLimitSeconds, List<String>? questionIds, int? durationSeconds, DateTime createdAt, DateTime updatedAt, DateTime? deletedAt
});




}
/// @nodoc
class _$QuizAttemptCopyWithImpl<$Res>
    implements $QuizAttemptCopyWith<$Res> {
  _$QuizAttemptCopyWithImpl(this._self, this._then);

  final QuizAttempt _self;
  final $Res Function(QuizAttempt) _then;

/// Create a copy of QuizAttempt
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? quizId = null,Object? ownerId = null,Object? answers = null,Object? score = null,Object? total = null,Object? startedAt = null,Object? completedAt = freezed,Object? mode = null,Object? timeLimitSeconds = freezed,Object? questionIds = freezed,Object? durationSeconds = freezed,Object? createdAt = null,Object? updatedAt = null,Object? deletedAt = freezed,}) {
  return _then(QuizAttempt(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,quizId: null == quizId ? _self.quizId : quizId // ignore: cast_nullable_to_non_nullable
as String,ownerId: null == ownerId ? _self.ownerId : ownerId // ignore: cast_nullable_to_non_nullable
as String,answers: null == answers ? _self.answers : answers // ignore: cast_nullable_to_non_nullable
as List<QuestionAnswer>,score: null == score ? _self.score : score // ignore: cast_nullable_to_non_nullable
as double,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,startedAt: null == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as DateTime,completedAt: freezed == completedAt ? _self.completedAt : completedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,mode: null == mode ? _self.mode : mode // ignore: cast_nullable_to_non_nullable
as AttemptMode,timeLimitSeconds: freezed == timeLimitSeconds ? _self.timeLimitSeconds : timeLimitSeconds // ignore: cast_nullable_to_non_nullable
as int?,questionIds: freezed == questionIds ? _self.questionIds : questionIds // ignore: cast_nullable_to_non_nullable
as List<String>?,durationSeconds: freezed == durationSeconds ? _self.durationSeconds : durationSeconds // ignore: cast_nullable_to_non_nullable
as int?,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,deletedAt: freezed == deletedAt ? _self.deletedAt : deletedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

}


/// Adds pattern-matching-related methods to [QuizAttempt].
extension QuizAttemptPatterns on QuizAttempt {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _QuizAttempt value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _QuizAttempt() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _QuizAttempt value)  $default,){
final _that = this;
switch (_that) {
case _QuizAttempt():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _QuizAttempt value)?  $default,){
final _that = this;
switch (_that) {
case _QuizAttempt() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String quizId,  String ownerId,  List<QuestionAnswer> answers,  double score,  int total,  DateTime startedAt,  DateTime? completedAt, @JsonKey(unknownEnumValue: AttemptMode.practice)  AttemptMode mode,  int? timeLimitSeconds,  List<String>? questionIds,  int? durationSeconds,  DateTime createdAt,  DateTime updatedAt,  DateTime? deletedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _QuizAttempt() when $default != null:
return $default(_that.id,_that.quizId,_that.ownerId,_that.answers,_that.score,_that.total,_that.startedAt,_that.completedAt,_that.mode,_that.timeLimitSeconds,_that.questionIds,_that.durationSeconds,_that.createdAt,_that.updatedAt,_that.deletedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String quizId,  String ownerId,  List<QuestionAnswer> answers,  double score,  int total,  DateTime startedAt,  DateTime? completedAt, @JsonKey(unknownEnumValue: AttemptMode.practice)  AttemptMode mode,  int? timeLimitSeconds,  List<String>? questionIds,  int? durationSeconds,  DateTime createdAt,  DateTime updatedAt,  DateTime? deletedAt)  $default,) {final _that = this;
switch (_that) {
case _QuizAttempt():
return $default(_that.id,_that.quizId,_that.ownerId,_that.answers,_that.score,_that.total,_that.startedAt,_that.completedAt,_that.mode,_that.timeLimitSeconds,_that.questionIds,_that.durationSeconds,_that.createdAt,_that.updatedAt,_that.deletedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String quizId,  String ownerId,  List<QuestionAnswer> answers,  double score,  int total,  DateTime startedAt,  DateTime? completedAt, @JsonKey(unknownEnumValue: AttemptMode.practice)  AttemptMode mode,  int? timeLimitSeconds,  List<String>? questionIds,  int? durationSeconds,  DateTime createdAt,  DateTime updatedAt,  DateTime? deletedAt)?  $default,) {final _that = this;
switch (_that) {
case _QuizAttempt() when $default != null:
return $default(_that.id,_that.quizId,_that.ownerId,_that.answers,_that.score,_that.total,_that.startedAt,_that.completedAt,_that.mode,_that.timeLimitSeconds,_that.questionIds,_that.durationSeconds,_that.createdAt,_that.updatedAt,_that.deletedAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _QuizAttempt implements QuizAttempt {
  const _QuizAttempt({required this.id, required this.quizId, required this.ownerId,  List<QuestionAnswer> answers = const <QuestionAnswer>[], this.score = 0, this.total = 0, required this.startedAt, this.completedAt, @JsonKey(unknownEnumValue: AttemptMode.practice) this.mode = AttemptMode.practice, this.timeLimitSeconds,  List<String>? questionIds, this.durationSeconds, required this.createdAt, required this.updatedAt, this.deletedAt}): _answers = answers,_questionIds = questionIds;
  factory _QuizAttempt.fromJson(Map<String, dynamic> json) => _$QuizAttemptFromJson(json);

@override final  String id;
@override final  String quizId;
/// The attempting user (column `owner_id`).
@override final  String ownerId;
 final  List<QuestionAnswer> _answers;
@override@JsonKey() List<QuestionAnswer> get answers {
  if (_answers is EqualUnmodifiableListView) return _answers;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_answers);
}

/// Number of correct answers (double to allow partial credit later).
@override@JsonKey() final  double score;
/// Number of questions in the quiz at attempt time.
@override@JsonKey() final  int total;
@override final  DateTime startedAt;
/// Null while in progress.
@override final  DateTime? completedAt;
/// Practice (default), exam or mistakes. Unknown values -> practice.
@override@JsonKey(unknownEnumValue: AttemptMode.practice) final  AttemptMode mode;
/// Exam time limit; null = untimed.
@override final  int? timeLimitSeconds;
/// Question ids served, in order (random pool subset); null = all
/// questions of the quiz.
 final  List<String>? _questionIds;
/// Question ids served, in order (random pool subset); null = all
/// questions of the quiz.
@override List<String>? get questionIds {
  final value = _questionIds;
  if (value == null) return null;
  if (_questionIds is EqualUnmodifiableListView) return _questionIds;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(value);
}

/// Time actually spent, in seconds (set on completion).
@override final  int? durationSeconds;
@override final  DateTime createdAt;
@override final  DateTime updatedAt;
@override final  DateTime? deletedAt;

/// Create a copy of QuizAttempt
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$QuizAttemptCopyWith<_QuizAttempt> get copyWith => __$QuizAttemptCopyWithImpl<_QuizAttempt>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$QuizAttemptToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _QuizAttempt&&(identical(other.id, id) || other.id == id)&&(identical(other.quizId, quizId) || other.quizId == quizId)&&(identical(other.ownerId, ownerId) || other.ownerId == ownerId)&&const DeepCollectionEquality().equals(other.answers, _answers)&&(identical(other.score, score) || other.score == score)&&(identical(other.total, total) || other.total == total)&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt)&&(identical(other.completedAt, completedAt) || other.completedAt == completedAt)&&(identical(other.mode, mode) || other.mode == mode)&&(identical(other.timeLimitSeconds, timeLimitSeconds) || other.timeLimitSeconds == timeLimitSeconds)&&const DeepCollectionEquality().equals(other.questionIds, _questionIds)&&(identical(other.durationSeconds, durationSeconds) || other.durationSeconds == durationSeconds)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.deletedAt, deletedAt) || other.deletedAt == deletedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,id,quizId,ownerId,const DeepCollectionEquality().hash(_answers),score,total,startedAt,completedAt,mode,timeLimitSeconds,const DeepCollectionEquality().hash(_questionIds),durationSeconds,createdAt,updatedAt,deletedAt);
}

@override
String toString() {
    return 'QuizAttempt(id: $id, quizId: $quizId, ownerId: $ownerId, answers: $answers, score: $score, total: $total, startedAt: $startedAt, completedAt: $completedAt, mode: $mode, timeLimitSeconds: $timeLimitSeconds, questionIds: $questionIds, durationSeconds: $durationSeconds, createdAt: $createdAt, updatedAt: $updatedAt, deletedAt: $deletedAt)';
}


}

/// @nodoc
abstract mixin class _$QuizAttemptCopyWith<$Res> implements $QuizAttemptCopyWith<$Res> {
  factory _$QuizAttemptCopyWith(_QuizAttempt value, $Res Function(_QuizAttempt) _then) = __$QuizAttemptCopyWithImpl;
@override @useResult
$Res call({
 String id, String quizId, String ownerId, List<QuestionAnswer> answers, double score, int total, DateTime startedAt, DateTime? completedAt,@JsonKey(unknownEnumValue: AttemptMode.practice) AttemptMode mode, int? timeLimitSeconds, List<String>? questionIds, int? durationSeconds, DateTime createdAt, DateTime updatedAt, DateTime? deletedAt
});




}
/// @nodoc
class __$QuizAttemptCopyWithImpl<$Res>
    implements _$QuizAttemptCopyWith<$Res> {
  __$QuizAttemptCopyWithImpl(this._self, this._then);

  final _QuizAttempt _self;
  final $Res Function(_QuizAttempt) _then;

/// Create a copy of QuizAttempt
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? quizId = null,Object? ownerId = null,Object? answers = null,Object? score = null,Object? total = null,Object? startedAt = null,Object? completedAt = freezed,Object? mode = null,Object? timeLimitSeconds = freezed,Object? questionIds = freezed,Object? durationSeconds = freezed,Object? createdAt = null,Object? updatedAt = null,Object? deletedAt = freezed,}) {
  return _then(_QuizAttempt(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,quizId: null == quizId ? _self.quizId : quizId // ignore: cast_nullable_to_non_nullable
as String,ownerId: null == ownerId ? _self.ownerId : ownerId // ignore: cast_nullable_to_non_nullable
as String,answers: null == answers ? _self._answers : answers // ignore: cast_nullable_to_non_nullable
as List<QuestionAnswer>,score: null == score ? _self.score : score // ignore: cast_nullable_to_non_nullable
as double,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,startedAt: null == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as DateTime,completedAt: freezed == completedAt ? _self.completedAt : completedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,mode: null == mode ? _self.mode : mode // ignore: cast_nullable_to_non_nullable
as AttemptMode,timeLimitSeconds: freezed == timeLimitSeconds ? _self.timeLimitSeconds : timeLimitSeconds // ignore: cast_nullable_to_non_nullable
as int?,questionIds: freezed == questionIds ? _self._questionIds : questionIds // ignore: cast_nullable_to_non_nullable
as List<String>?,durationSeconds: freezed == durationSeconds ? _self.durationSeconds : durationSeconds // ignore: cast_nullable_to_non_nullable
as int?,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,deletedAt: freezed == deletedAt ? _self.deletedAt : deletedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}

// dart format on
