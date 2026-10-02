import 'package:freezed_annotation/freezed_annotation.dart';

import '../data/models/drafts.dart';
import '../data/models/question.dart';
import 'llm_provider.dart';

part 'ai_service.freezed.dart';

enum Difficulty { easy, medium, hard }

@freezed
abstract class QuizGenerationRequest with _$QuizGenerationRequest {
  const factory QuizGenerationRequest({
    /// Pasted source material. At least one of [contextText]/[youtubeUrl].
    String? contextText,
    String? youtubeUrl,
    @Default(10) int questionCount,
    @Default({
      QuestionType.mcqSingle,
      QuestionType.mcqMulti,
      QuestionType.trueFalse,
      QuestionType.shortAnswer,
    })
    Set<QuestionType> questionTypes,
    @Default(Difficulty.medium) Difficulty difficulty,

    /// Output language (e.g. `en`); null = same as the source.
    String? language,
    String? extraInstructions,

    /// Overrides; null = selection from `ApiKeyStore`.
    LlmProviderId? providerId,
    String? model,
  }) = _QuizGenerationRequest;
}

@freezed
abstract class NoteGenerationRequest with _$NoteGenerationRequest {
  const factory NoteGenerationRequest({
    String? contextText,
    String? youtubeUrl,
    String? language,

    /// e.g. "concise summary", "detailed study notes with headings".
    String? extraInstructions,
    LlmProviderId? providerId,
    String? model,
  }) = _NoteGenerationRequest;
}

/// High-level AI generation: resolves provider/key/model, fetches the YouTube
/// transcript when the provider cannot take URLs, builds prompts, calls
/// `LlmProvider.generateJson`, validates against the draft schema (one repair
/// retry), and returns a draft for preview/editing.
///
/// Errors: `AiException` (missingApiKey if no key for the provider),
/// `TranscriptUnavailableException`, `ValidationException` (no input),
/// `NetworkException`.
abstract interface class AiService {
  Future<QuizDraft> generateQuiz(QuizGenerationRequest request);

  Future<NoteDraft> generateNote(NoteGenerationRequest request);
}
