import 'package:freezed_annotation/freezed_annotation.dart';

part 'quiz_source.freezed.dart';
part 'quiz_source.g.dart';

/// Provenance of an AI-generated quiz (`quizzes.source` jsonb).
/// Null on manually created quizzes.
@freezed
abstract class QuizSource with _$QuizSource {
  const factory QuizSource({
    /// Pasted text (possibly truncated).
    String? contextText,
    String? youtubeUrl,

    /// `LlmProviderId.wireName`, e.g. `gemini`.
    String? provider,
    String? model,

    /// Notes used as source material (id + title at generation time).
    @Default(<QuizSourceRef>[]) List<QuizSourceRef> notes,

    /// Subject attachments used as source material (id + file name).
    @Default(<QuizSourceRef>[]) List<QuizSourceRef> attachments,
  }) = _QuizSource;

  factory QuizSource.fromJson(Map<String, dynamic> json) =>
      _$QuizSourceFromJson(json);
}

/// A note or attachment referenced by [QuizSource] (the item may have been
/// renamed or deleted since; [name] is a snapshot).
@freezed
abstract class QuizSourceRef with _$QuizSourceRef {
  const factory QuizSourceRef({required String id, required String name}) =
      _QuizSourceRef;

  factory QuizSourceRef.fromJson(Map<String, dynamic> json) =>
      _$QuizSourceRefFromJson(json);
}
