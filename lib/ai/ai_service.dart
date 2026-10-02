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

    /// Subject or note title, gives the model context (optional).
    String? topic,

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

    /// Subject title, gives the model context (optional).
    String? topic,
    LlmProviderId? providerId,
    String? model,
  }) = _NoteGenerationRequest;
}

/// The provider/model a generation will use (or used). Fill
/// `QuizSource(provider: selection.providerId.wireName, model:
/// selection.model)` from it when saving a draft.
class AiSelection {
  const AiSelection({required this.providerId, required this.model});

  final LlmProviderId providerId;
  final String model;

  @override
  bool operator ==(Object other) =>
      other is AiSelection &&
      other.providerId == providerId &&
      other.model == model;

  @override
  int get hashCode => Object.hash(providerId, model);

  @override
  String toString() => 'AiSelection(${providerId.wireName}, $model)';
}

/// High-level AI generation: resolves provider/key/model, fetches the YouTube
/// transcript when the provider cannot take URLs, builds prompts, calls
/// `LlmProvider.generateJson`, validates against the draft schema (one repair
/// retry), and returns a draft for preview/editing. Never writes to the
/// database.
///
/// Errors: `AiException` (missingApiKey if no key for the provider,
/// invalidApiKey, rateLimited, invalidOutput, unsupported, provider),
/// `TranscriptUnavailableException`, `ValidationException` (no input / bad
/// URL), `NetworkException`.
abstract interface class AiService {
  Future<QuizDraft> generateQuiz(QuizGenerationRequest request);

  Future<NoteDraft> generateNote(NoteGenerationRequest request);

  /// The provider/model that a request with these overrides would use:
  /// override > `ApiKeyStore` selection > first provider with a key; model
  /// override > stored model > `LlmProviderId.defaultModel`.
  /// Throws `AiException(kind: missingApiKey)` when no provider has a key.
  Future<AiSelection> resolveSelection({
    LlmProviderId? providerId,
    String? model,
  });

  /// Model ids for [provider] (settings model picker). Uses [apiKey] /
  /// [baseUrl] when given (unsaved form values), else the stored ones.
  Future<List<String>> listModels(
    LlmProviderId provider, {
    String? apiKey,
    String? baseUrl,
    Map<String, String>? extraHeaders,
  });

  /// Cheap key check for the settings screen (lists models; for OpenRouter
  /// also checks `/key`). Completes normally when the key works, otherwise
  /// throws the same typed errors as generation.
  Future<void> testConnection(
    LlmProviderId provider, {
    String? apiKey,
    String? baseUrl,
    Map<String, String>? extraHeaders,
  });
}
