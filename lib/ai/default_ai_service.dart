import 'dart:convert';

import '../core/errors/app_exception.dart';
import '../data/models/drafts.dart';
import '../data/models/question.dart';
import 'ai_service.dart';
import 'api_key_store.dart';
import 'draft_validator.dart';
import 'llm_provider.dart';
import 'prompts.dart';
import 'providers/http_support.dart';
import 'providers/openai_compatible_provider.dart';
import 'transcript_service.dart';
import 'youtube_url.dart';

/// Default [AiService]: ApiKeyStore selection -> LlmProvider -> validator
/// with one repair retry. Returns drafts only; persisting is the UI's job.
class DefaultAiService implements AiService {
  DefaultAiService({
    required ApiKeyStore keyStore,
    required LlmProviderFactory providerFactory,
    required TranscriptService transcriptService,
    this.maxContextChars = 100000,
    this.maxQuestionCount = 50,
  }) : _keys = keyStore,
       _factory = providerFactory,
       _transcripts = transcriptService;

  final ApiKeyStore _keys;
  final LlmProviderFactory _factory;
  final TranscriptService _transcripts;

  /// Pasted context longer than this is cut (with a note) before prompting.
  final int maxContextChars;
  final int maxQuestionCount;

  // ---------------------------------------------------------------- quiz

  @override
  Future<QuizDraft> generateQuiz(QuizGenerationRequest request) async {
    if (request.questionCount < 1 || request.questionCount > maxQuestionCount) {
      throw ValidationException(
        'Choose between 1 and $maxQuestionCount questions.',
      );
    }
    final types = request.questionTypes.isEmpty
        ? QuestionType.values.toSet()
        : request.questionTypes;
    final prepared = await _prepare(
      contextText: request.contextText,
      youtubeUrl: request.youtubeUrl,
      providerId: request.providerId,
      model: request.model,
    );
    final userPrompt = Prompts.quizUser(
      request.copyWith(questionTypes: types),
      prepared.source,
    );
    return _generateValidated(
      provider: prepared.provider,
      system: Prompts.quizSystem(),
      user: userPrompt,
      schema: quizDraftJsonSchema,
      schemaName: Prompts.quizSchemaName,
      youtubeUrl: prepared.nativeVideoUrl,
      what: 'quiz',
      validate: (json) => DraftValidator.validateQuiz(
        json,
        allowedTypes: types,
        maxQuestions: request.questionCount,
      ),
    );
  }

  // ---------------------------------------------------------------- note

  @override
  Future<NoteDraft> generateNote(NoteGenerationRequest request) async {
    final prepared = await _prepare(
      contextText: request.contextText,
      youtubeUrl: request.youtubeUrl,
      providerId: request.providerId,
      model: request.model,
    );
    return _generateValidated(
      provider: prepared.provider,
      system: Prompts.noteSystem(),
      user: Prompts.noteUser(request, prepared.source),
      schema: noteDraftJsonSchema,
      schemaName: Prompts.noteSchemaName,
      youtubeUrl: prepared.nativeVideoUrl,
      what: 'note',
      validate: DraftValidator.validateNote,
    );
  }

  // ------------------------------------------------------------ settings

  @override
  Future<AiSelection> resolveSelection({
    LlmProviderId? providerId,
    String? model,
  }) async {
    var provider = providerId ?? await _keys.getSelectedProvider();
    if (provider == null) {
      final configured = await _keys.configuredProviders();
      for (final p in LlmProviderId.values) {
        if (configured.contains(p)) {
          provider = p;
          break;
        }
      }
    }
    if (provider == null) {
      throw const AiException(
        'Add an AI provider API key in Settings to generate content.',
        kind: AiErrorKind.missingApiKey,
      );
    }
    final override = model?.trim();
    final resolvedModel = (override != null && override.isNotEmpty)
        ? override
        : (await _keys.getSelectedModel(provider)) ?? provider.defaultModel;
    return AiSelection(providerId: provider, model: resolvedModel);
  }

  @override
  Future<List<String>> listModels(
    LlmProviderId provider, {
    String? apiKey,
    String? baseUrl,
    Map<String, String>? extraHeaders,
  }) async {
    final llm = await _settingsProvider(
      provider,
      apiKey: apiKey,
      baseUrl: baseUrl,
      extraHeaders: extraHeaders,
    );
    return llm.listModels();
  }

  @override
  Future<void> testConnection(
    LlmProviderId provider, {
    String? apiKey,
    String? baseUrl,
    Map<String, String>? extraHeaders,
  }) async {
    final llm = await _settingsProvider(
      provider,
      apiKey: apiKey,
      baseUrl: baseUrl,
      extraHeaders: extraHeaders,
    );
    if (llm is OpenAiCompatibleProvider) {
      await llm.verifyKey();
    } else {
      await llm.listModels();
    }
  }

  Future<LlmProvider> _settingsProvider(
    LlmProviderId provider, {
    String? apiKey,
    String? baseUrl,
    Map<String, String>? extraHeaders,
  }) async {
    final key = _blankToNull(apiKey) ?? await _keys.getApiKey(provider);
    if (key == null && !provider.requiresBaseUrl) {
      throw AiException(
        'Enter your ${provider.displayName} API key first.',
        kind: AiErrorKind.missingApiKey,
      );
    }
    return _factory.create(
      LlmConfig(
        providerId: provider,
        apiKey: key ?? '',
        model:
            (await _keys.getSelectedModel(provider)) ?? provider.defaultModel,
        baseUrl:
            _blankToNull(baseUrl) ??
            await _keys.getBaseUrl(provider) ??
            provider.defaultBaseUrl,
        extraHeaders: extraHeaders ?? await _keys.getExtraHeaders(provider),
      ),
    );
  }

  // ------------------------------------------------------------ internals

  Future<_Prepared> _prepare({
    required String? contextText,
    required String? youtubeUrl,
    required LlmProviderId? providerId,
    required String? model,
  }) async {
    final text = _blankToNull(contextText);
    final rawUrl = _blankToNull(youtubeUrl);
    if (text == null && rawUrl == null) {
      throw const ValidationException(
        'Add some text or a YouTube link to generate from.',
      );
    }
    String? url;
    if (rawUrl != null) {
      url = YoutubeUrl.normalize(rawUrl);
      if (url == null) {
        throw const ValidationException(
          "That doesn't look like a YouTube video link.",
        );
      }
    }

    final selection = await resolveSelection(
      providerId: providerId,
      model: model,
    );
    final id = selection.providerId;
    final key = await _keys.getApiKey(id);
    if (key == null) {
      throw AiException(
        'No API key saved for ${id.displayName}. Add one in Settings.',
        kind: AiErrorKind.missingApiKey,
      );
    }
    final provider = _factory.create(
      LlmConfig(
        providerId: id,
        apiKey: key,
        model: selection.model,
        baseUrl: (await _keys.getBaseUrl(id)) ?? id.defaultBaseUrl,
        extraHeaders: id == LlmProviderId.openaiCompatible
            ? await _keys.getExtraHeaders(id)
            : const {},
      ),
    );

    VideoTranscript? transcript;
    String? nativeVideoUrl;
    if (url != null) {
      if (id.supportsYoutubeUrl) {
        nativeVideoUrl = url;
      } else {
        transcript = await _transcripts.fetchTranscript(url);
      }
    }
    return _Prepared(
      provider: provider,
      nativeVideoUrl: nativeVideoUrl,
      source: PromptSource(
        contextText: text == null ? null : _truncateContext(text),
        transcript: transcript,
        nativeVideo: nativeVideoUrl != null,
      ),
    );
  }

  String _truncateContext(String text) {
    if (text.length <= maxContextChars) return text;
    return '${text.substring(0, maxContextChars)}\n\n[Source truncated: '
        'showing the first $maxContextChars of ${text.length} characters.]';
  }

  /// Calls the provider, validates, and on invalid JSON / validation errors
  /// sends ONE repair request containing the previous output and the
  /// problems. The second attempt is accepted if it yields any valid draft
  /// (invalid questions are dropped).
  Future<T> _generateValidated<T>({
    required LlmProvider provider,
    required String system,
    required String user,
    required Map<String, Object?> schema,
    required String schemaName,
    required String? youtubeUrl,
    required String what,
    required DraftValidation<T> Function(Map<String, dynamic> json) validate,
  }) async {
    Future<Map<String, dynamic>> call(String prompt) => provider.generateJson(
      prompt: prompt,
      schema: schema,
      schemaName: schemaName,
      youtubeUrl: youtubeUrl,
      systemPrompt: system,
    );

    String previous;
    List<String> problems;
    try {
      final json = await call(user);
      final result = validate(json);
      if (result.isValid) return result.value as T;
      previous = jsonEncode(json);
      problems = result.errors;
    } on AiException catch (e) {
      final raw = e.cause;
      if (e.kind != AiErrorKind.invalidOutput ||
          (raw is RawModelOutput && raw.truncated)) {
        rethrow;
      }
      previous = raw is RawModelOutput ? raw.text : '';
      problems = const [
        'The answer was not a single valid JSON object matching the schema.',
      ];
    }

    final repairPrompt = Prompts.repair(
      originalPrompt: user,
      previousOutput: previous,
      problems: problems,
    );
    try {
      final json = await call(repairPrompt);
      final result = validate(json);
      final value = result.value;
      if (value != null) return value;
      throw AiException(
        'The AI returned an unusable $what twice. Try again, add more source '
        'material, or pick a different model.',
        kind: AiErrorKind.invalidOutput,
        cause: result.errors.join('\n'),
      );
    } on AiException catch (e) {
      if (e.kind != AiErrorKind.invalidOutput) rethrow;
      final raw = e.cause;
      if (raw is RawModelOutput && raw.truncated) rethrow;
      if (e.cause is String) rethrow; // our own message above
      throw AiException(
        'The AI returned an unusable $what twice. Try again or pick a '
        'different model.',
        kind: AiErrorKind.invalidOutput,
        cause: e,
      );
    }
  }

  static String? _blankToNull(String? v) =>
      (v == null || v.trim().isEmpty) ? null : v.trim();
}

class _Prepared {
  const _Prepared({
    required this.provider,
    required this.source,
    this.nativeVideoUrl,
  });

  final LlmProvider provider;
  final PromptSource source;
  final String? nativeVideoUrl;
}
