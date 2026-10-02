import 'dart:convert';

import '../core/errors/app_exception.dart';
import '../data/models/drafts.dart';
import '../data/models/question.dart';
import 'ai_capabilities.dart';
import 'ai_readiness.dart';
import 'ai_service.dart';
import 'api_key_store.dart';
import 'base_url_policy.dart';
import 'draft_validator.dart';
import 'llm_provider.dart';
import 'prompts.dart';
import 'providers/http_support.dart';
import 'providers/openai_compatible_provider.dart';
import 'text_extractor.dart';
import 'transcript_service.dart';
import 'youtube_url.dart';

/// Default [AiService]: ApiKeyStore selection -> LlmProvider -> validator
/// with one repair retry. Returns drafts only; persisting is the UI's job.
class DefaultAiService implements AiService {
  DefaultAiService({
    required ApiKeyStore keyStore,
    required LlmProviderFactory providerFactory,
    required TranscriptService transcriptService,
    this.capabilities,
    this.isWeb,
    this.maxContextChars = 100000,
    this.maxQuestionCount = 50,
  }) : _keys = keyStore,
       _factory = providerFactory,
       _transcripts = transcriptService;

  final ApiKeyStore _keys;
  final LlmProviderFactory _factory;
  final TranscriptService _transcripts;

  /// Resolves model capabilities (OpenRouter metadata); null = static table.
  final AiCapabilityResolver? capabilities;

  /// Platform override for the static capability table (null = `kIsWeb`).
  final bool? isWeb;

  /// Total characters of user-provided text (pasted text, notes, text
  /// files) sent to the model; longer sources are cut evenly, with a note.
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
      sources: _collect(
        request.sources,
        request.contextText,
        request.youtubeUrl,
      ),
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
      attachments: prepared.attachments,
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
      sources: _collect(
        request.sources,
        request.contextText,
        request.youtubeUrl,
      ),
      providerId: request.providerId,
      model: request.model,
    );
    return _generateValidated(
      provider: prepared.provider,
      system: Prompts.noteSystem(),
      user: Prompts.noteUser(request, prepared.source),
      schema: noteDraftJsonSchema,
      schemaName: Prompts.noteSchemaName,
      attachments: prepared.attachments,
      what: 'note',
      validate: DraftValidator.validateNote,
    );
  }

  // ---------------------------------------------------------- structured

  /// Generic generation from sources into `request.schema` (e.g. flashcard
  /// decks), with the same source handling, capability checks and single
  /// repair retry as quizzes/notes. [validate] returns the parsed value or
  /// errors that are sent back to the model once.
  Future<T> generateStructured<T>(
    StructuredGenerationRequest request, {
    required DraftValidation<T> Function(Map<String, dynamic> json) validate,
    String what = 'result',
  }) async {
    final prepared = await _prepare(
      sources: _collect(request.sources, null, null),
      providerId: request.providerId,
      model: request.model,
    );
    return _generateValidated(
      provider: prepared.provider,
      system: request.systemPrompt,
      user: Prompts.structuredUser(
        task: request.task,
        source: prepared.source,
        topic: request.topic,
        language: request.language,
        extraInstructions: request.extraInstructions,
      ),
      schema: request.schema,
      schemaName: request.schemaName,
      attachments: prepared.attachments,
      what: what,
      validate: validate,
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
        if (configured.contains(p) ||
            isKeylessEndpoint(p, await _keys.getBaseUrl(p))) {
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
        baseUrl: _checkedBaseUrl(
          _blankToNull(baseUrl) ??
              await _keys.getBaseUrl(provider) ??
              provider.defaultBaseUrl,
        ),
        extraHeaders: extraHeaders ?? await _keys.getExtraHeaders(provider),
      ),
    );
  }

  // ------------------------------------------------------------ internals

  /// Legacy [contextText]/[youtubeUrl] first, then [sources]; blank text
  /// sources dropped.
  static List<AiSource> _collect(
    List<AiSource> sources,
    String? contextText,
    String? youtubeUrl,
  ) {
    final text = _blankToNull(contextText);
    final url = _blankToNull(youtubeUrl);
    return [
      if (text != null) TextSource(text: text),
      if (url != null) YoutubeSource(url),
      for (final s in sources)
        if (switch (s) {
          TextSource(:final text) => text.trim().isNotEmpty,
          NoteSource(:final markdown) => markdown.trim().isNotEmpty,
          FileSource() => true,
          YoutubeSource(:final url) => url.trim().isNotEmpty,
        })
          s,
    ];
  }

  Future<_Prepared> _prepare({
    required List<AiSource> sources,
    required LlmProviderId? providerId,
    required String? model,
  }) async {
    if (sources.isEmpty) {
      throw const ValidationException(
        'Add some text, a note, a file or a YouTube link to generate from.',
      );
    }
    // Validate cheap things before touching settings or the network.
    final youtube = <YoutubeSource, String>{};
    for (final s in sources) {
      if (s is YoutubeSource) {
        final url = YoutubeUrl.normalize(s.url.trim());
        if (url == null) {
          throw const ValidationException(
            "That doesn't look like a YouTube video link.",
          );
        }
        youtube[s] = url;
      } else if (s is FileSource && s.kind == null) {
        throw AiException(
          '"${s.name}" is not a supported file type. Use PDF, images, text '
          'files (.txt, .md, .docx) or, with Gemini, audio and video.',
          kind: AiErrorKind.unsupported,
        );
      }
    }

    final selection = await resolveSelection(
      providerId: providerId,
      model: model,
    );
    final id = selection.providerId;
    final key = await _keys.getApiKey(id);
    final storedBase = await _keys.getBaseUrl(id);
    if (key == null && !isKeylessEndpoint(id, storedBase)) {
      throw AiException(
        'No API key saved for ${id.displayName}. Add one in Settings.',
        kind: AiErrorKind.missingApiKey,
      );
    }
    final baseUrl = _checkedBaseUrl(storedBase ?? id.defaultBaseUrl);
    final provider = _factory.create(
      LlmConfig(
        providerId: id,
        apiKey: key ?? '',
        model: selection.model,
        baseUrl: baseUrl,
        extraHeaders: id == LlmProviderId.openaiCompatible
            ? await _keys.getExtraHeaders(id)
            : const {},
      ),
    );

    final needsCaps = sources.any(
      (s) =>
          s is YoutubeSource || (s is FileSource && s.kind != AiInputKind.text),
    );
    final caps = needsCaps
        ? await _capabilitiesFor(selection, baseUrl)
        : AiCapabilities.textOnly;

    final entries = <PromptSourceEntry>[];
    final attachments = <LlmAttachment>[];
    for (final s in sources) {
      switch (s) {
        case TextSource(:final label, :final text):
          entries.add(
            PromptSourceEntry(
              kind: PromptSourceKind.pastedText,
              label: label,
              text: text.trim(),
            ),
          );
        case NoteSource(:final title, :final markdown):
          entries.add(
            PromptSourceEntry(
              kind: PromptSourceKind.note,
              label: title.trim().isEmpty ? 'Untitled note' : title.trim(),
              text: markdown.trim(),
            ),
          );
        case FileSource():
          final kind = s.kind!;
          if (kind == AiInputKind.text) {
            final text =
                TextExtractor.extract(s.name, s.mimeType, s.bytes) ?? '';
            if (text.trim().isEmpty) {
              throw ValidationException('"${s.name}" contains no text.');
            }
            entries.add(
              PromptSourceEntry(
                kind: PromptSourceKind.textFile,
                label: s.name,
                text: text.trim(),
              ),
            );
            continue;
          }
          if (!caps.supports(kind)) {
            throw AiException(
              _unsupportedMessage(selection, kind, s.name),
              kind: AiErrorKind.unsupported,
            );
          }
          final n = attachments.length + 1;
          attachments.add(
            LlmFileAttachment(
              label: 'Attachment $n: ${s.name}',
              filename: s.name,
              mimeType: s.effectiveMimeType,
              bytes: s.bytes,
              kind: kind,
            ),
          );
          entries.add(
            PromptSourceEntry(
              kind: switch (kind) {
                AiInputKind.pdf => PromptSourceKind.pdf,
                AiInputKind.image => PromptSourceKind.image,
                AiInputKind.audio => PromptSourceKind.audio,
                _ => PromptSourceKind.video,
              },
              label: s.name,
              attachmentNumber: n,
            ),
          );
        case YoutubeSource():
          final url = youtube[s]!;
          if (caps.youtubeNative) {
            final n = attachments.length + 1;
            attachments.add(
              LlmYoutubeAttachment(
                label: 'Attachment $n: YouTube video',
                url: url,
              ),
            );
            entries.add(
              PromptSourceEntry(
                kind: PromptSourceKind.youtubeVideo,
                label: 'YouTube video',
                attachmentNumber: n,
              ),
            );
          } else if (!caps.youtube) {
            throw TranscriptUnavailableException(
              "YouTube captions can't be loaded in the browser, and "
              '${id.displayName} cannot watch videos. Use Google Gemini or '
              'paste the text instead.',
            );
          } else {
            final transcript = await _transcripts.fetchTranscript(url);
            entries.add(
              PromptSourceEntry(
                kind: PromptSourceKind.youtubeTranscript,
                label: transcript.title ?? 'YouTube video',
                text: transcript.text,
                autoGenerated: transcript.isAutoGenerated,
              ),
            );
          }
      }
    }
    return _Prepared(
      provider: provider,
      attachments: attachments,
      source: PromptSource(_fitTextBudget(entries)),
    );
  }

  Future<AiCapabilities> _capabilitiesFor(
    AiSelection selection,
    String? baseUrl,
  ) async {
    final Object store = _keys;
    final Set<AiInputKind> manual = store is AiCapabilityOverrideStore
        ? await store.getInputOverride(selection.providerId, selection.model)
        : const {};
    final resolver = capabilities;
    if (resolver != null) {
      return resolver.resolve(
        provider: selection.providerId,
        model: selection.model,
        baseUrl: baseUrl,
        manualOverride: manual,
      );
    }
    return staticCapabilities(
      selection.providerId,
      selection.model,
      manual: manual,
      isWeb: isWeb,
    );
  }

  static String _unsupportedMessage(
    AiSelection selection,
    AiInputKind kind,
    String fileName,
  ) {
    final who = '${selection.model} (${selection.providerId.displayName})';
    final hint = switch (kind) {
      AiInputKind.audio ||
      AiInputKind.video => 'Audio and video need a Google Gemini model.',
      _ when selection.providerId == LlmProviderId.openaiCompatible =>
        'Pick a model that accepts ${kind.plural}, or mark this model as '
            'supporting them in Settings if it does.',
      _ => 'Pick a model that accepts ${kind.plural} (e.g. a vision model).',
    };
    return "$who can't read ${kind.plural} (\"$fileName\"). $hint";
  }

  /// Shares [maxContextChars] among the user-provided text sources (pasted
  /// text, notes, text files; transcripts have their own budget): short
  /// sources are kept whole, long ones are cut evenly, with a note.
  List<PromptSourceEntry> _fitTextBudget(List<PromptSourceEntry> entries) {
    final budgeted = [
      for (var i = 0; i < entries.length; i++)
        if (entries[i].isText &&
            entries[i].kind != PromptSourceKind.youtubeTranscript)
          i,
    ];
    final total = budgeted.fold<int>(
      0,
      (sum, i) => sum + entries[i].text!.length,
    );
    if (total <= maxContextChars) return entries;
    final byLength = [...budgeted]
      ..sort((a, b) => entries[a].text!.length - entries[b].text!.length);
    final allowance = <int, int>{};
    var remaining = maxContextChars;
    for (var k = 0; k < byLength.length; k++) {
      final i = byLength[k];
      final share = remaining ~/ (byLength.length - k);
      final length = entries[i].text!.length;
      final take = length < share ? length : share;
      allowance[i] = take;
      remaining -= take;
    }
    return [
      for (var i = 0; i < entries.length; i++)
        allowance.containsKey(i)
            ? PromptSourceEntry(
                kind: entries[i].kind,
                label: entries[i].label,
                text: _truncate(entries[i].text!, allowance[i]!),
              )
            : entries[i],
    ];
  }

  static String _truncate(String text, int max) {
    if (text.length <= max) return text;
    return '${text.substring(0, max)}\n\n[Source truncated: showing the '
        'first $max of ${text.length} characters.]';
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
    required List<LlmAttachment> attachments,
    required String what,
    required DraftValidation<T> Function(Map<String, dynamic> json) validate,
  }) async {
    Future<Map<String, dynamic>> call(String prompt) => provider.generateJson(
      prompt: prompt,
      schema: schema,
      schemaName: schemaName,
      systemPrompt: system,
      attachments: attachments,
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

  /// Never send a key to a non-https remote URL (unsaved Settings input or
  /// a value stored before the https rule existed).
  static String? _checkedBaseUrl(String? url) =>
      url == null ? null : normalizeBaseUrl(url);

  static String? _blankToNull(String? v) =>
      (v == null || v.trim().isEmpty) ? null : v.trim();
}

class _Prepared {
  const _Prepared({
    required this.provider,
    required this.source,
    required this.attachments,
  });

  final LlmProvider provider;
  final PromptSource source;
  final List<LlmAttachment> attachments;
}
