import 'package:freezed_annotation/freezed_annotation.dart';

part 'quiz_source.freezed.dart';
part 'quiz_source.g.dart';

/// Provenance of an AI-generated quiz (`quizzes.source` jsonb).
/// Null on manually created quizzes.
@freezed
abstract class QuizSource with _$QuizSource {
  const factory QuizSource({
    String? contextText,
    String? youtubeUrl,

    /// `LlmProviderId.wireName`, e.g. `gemini`.
    String? provider,
    String? model,
  }) = _QuizSource;

  factory QuizSource.fromJson(Map<String, dynamic> json) =>
      _$QuizSourceFromJson(json);
}
