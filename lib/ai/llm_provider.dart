import 'dart:typed_data';

import 'ai_source.dart';

/// Supported AI backends. Keys are stored per id in `ApiKeyStore`.
enum LlmProviderId {
  gemini('gemini', 'Google Gemini'),
  openai('openai', 'OpenAI'),
  anthropic('anthropic', 'Anthropic'),

  /// Any OpenAI-compatible endpoint (OpenRouter, Ollama, ...). Needs a base
  /// URL.
  openaiCompatible('openai_compatible', 'OpenAI-compatible');

  const LlmProviderId(this.wireName, this.displayName);

  /// Stable id used in storage and `QuizSource.provider`.
  final String wireName;
  final String displayName;

  /// Gemini accepts YouTube URLs directly; others need a transcript.
  bool get supportsYoutubeUrl => this == LlmProviderId.gemini;

  bool get requiresBaseUrl => this == LlmProviderId.openaiCompatible;

  /// Model used when the user has not picked one. Prefer stable aliases so
  /// the default keeps working as providers ship new snapshots.
  String get defaultModel => switch (this) {
    LlmProviderId.gemini => 'gemini-flash-latest',
    LlmProviderId.openai => 'gpt-5.4-mini',
    LlmProviderId.anthropic => 'claude-sonnet-5-5',
    LlmProviderId.openaiCompatible => 'openrouter/auto',
  };

  /// Base URL used when none is stored (only meaningful for
  /// [LlmProviderId.openaiCompatible]; the others have fixed endpoints).
  String? get defaultBaseUrl => switch (this) {
    LlmProviderId.openaiCompatible => 'https://openrouter.ai/api/v1',
    _ => null,
  };

  static LlmProviderId? fromWireName(String? value) {
    for (final id in values) {
      if (id.wireName == value) return id;
    }
    return null;
  }
}

/// Everything needed to talk to one provider.
class LlmConfig {
  const LlmConfig({
    required this.providerId,
    required this.apiKey,
    required this.model,
    this.baseUrl,
    this.extraHeaders = const {},
  });

  final LlmProviderId providerId;
  final String apiKey;
  final String model;

  /// Required for [LlmProviderId.openaiCompatible], optional override
  /// otherwise.
  final String? baseUrl;

  /// Extra HTTP headers sent with every request (OpenAI-compatible only),
  /// e.g. OpenRouter's `HTTP-Referer` / `X-Title`.
  final Map<String, String> extraHeaders;

  @override
  String toString() =>
      'LlmConfig(${providerId.wireName}, model: $model, baseUrl: $baseUrl)';
}

/// Binary input sent alongside the prompt (see [LlmProvider.generateJson]).
/// Text-like sources never become attachments; their text is in the prompt.
sealed class LlmAttachment {
  const LlmAttachment({required this.label});

  /// Shown to the model in a text part right before the attachment, e.g.
  /// `Attachment 1: lecture.pdf`, so the prompt can refer to it.
  final String label;
}

/// A file sent inline / uploaded: PDF, image, audio or video.
final class LlmFileAttachment extends LlmAttachment {
  const LlmFileAttachment({
    required super.label,
    required this.filename,
    required this.mimeType,
    required this.bytes,
    required this.kind,
  });

  final String filename;

  /// Normalized MIME type (e.g. `application/pdf`, `image/png`).
  final String mimeType;
  final Uint8List bytes;

  /// [AiInputKind.pdf], [AiInputKind.image], [AiInputKind.audio] or
  /// [AiInputKind.video].
  final AiInputKind kind;
}

/// A YouTube video passed by URL (Gemini only).
final class LlmYoutubeAttachment extends LlmAttachment {
  const LlmYoutubeAttachment({required super.label, required this.url});
  final String url;
}

/// A configured LLM backend producing structured JSON.
///
/// Errors: throws `AiException` (kind: invalidApiKey, rateLimited,
/// unsupported, provider, invalidOutput), `ValidationException` (attachment
/// too large for the provider) or `NetworkException`.
abstract interface class LlmProvider {
  LlmProviderId get id;

  /// Model ids available for the configured key (from the provider's
  /// list-models endpoint). UI falls back to free-text entry on failure.
  Future<List<String>> listModels();

  /// Generates a JSON object conforming to [schema] (a JSON Schema map such as
  /// `quizDraftJsonSchema`) and returns it decoded.
  ///
  /// [attachments] are sent before the prompt, each preceded by a text part
  /// holding its label. Providers throw `AiException(kind: unsupported)`
  /// for kinds they cannot take (e.g. audio to OpenAI, YouTube URLs to
  /// anything but Gemini) and `ValidationException` when a file exceeds the
  /// provider's size limits (see `ProviderLimits`).
  /// [youtubeUrl] is shorthand for one [LlmYoutubeAttachment] (sent first,
  /// without a label part).
  /// [schemaName] is used where the API requires a name (e.g. `QuizDraft`).
  Future<Map<String, dynamic>> generateJson({
    required String prompt,
    required Map<String, Object?> schema,
    String? schemaName,
    String? youtubeUrl,
    String? systemPrompt,
    List<LlmAttachment> attachments = const [],
  });
}

/// Builds a provider instance for a config.
abstract interface class LlmProviderFactory {
  LlmProvider create(LlmConfig config);
}
