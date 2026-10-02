import 'dart:convert';

import '../../core/errors/app_exception.dart';
import '../ai_source.dart';
import '../llm_chat.dart';
import '../llm_provider.dart';
import 'attachment_support.dart';
import 'http_support.dart';
import 'schema_adapters.dart';
import 'sse.dart';

/// How structured output is requested from an OpenAI-compatible endpoint.
enum CompatJsonMode {
  /// `response_format: {type: json_schema, json_schema: {name, strict,
  /// schema}}`.
  jsonSchema,

  /// `response_format: {type: json_object}` + schema in the system prompt.
  jsonObject,

  /// No `response_format`; schema and "JSON only" enforced by the prompt.
  prompt,
}

/// Any OpenAI-compatible Chat Completions endpoint (OpenRouter by default,
/// also Ollama, LM Studio, Groq, Together, ...).
///
/// * `POST {baseUrl}/chat/completions` with `Authorization: Bearer <key>`
///   plus any configured extra headers (OpenRouter: `HTTP-Referer`,
///   `X-Title`).
/// * Tries `json_schema` (strict) first; if the endpoint rejects it with a
///   400/422 falls back to `json_object`, then to prompt-only JSON. The
///   working mode is remembered for this instance.
/// * Attachments: the user message `content` becomes parts: `text` labels,
///   `image_url` (data URL) for images and `file` (`filename` + base64
///   `file_data` data URL, OpenRouter's PDF format) for PDFs, then the
///   prompt. Whether the model accepts them is decided by `AiCapabilities`.
/// * `GET {baseUrl}/models`. For OpenRouter `testConnection` additionally
///   calls `GET {baseUrl}/key`, since `/models` does not need a key there.
class OpenAiCompatibleProvider extends HttpLlmProvider
    implements LlmChatProvider {
  OpenAiCompatibleProvider(
    super.config,
    super.client, {
    super.generateTimeout,
    super.listTimeout,
    super.isWeb,
  });

  String get _base =>
      config.baseUrl ?? LlmProviderId.openaiCompatible.defaultBaseUrl!;

  @override
  String get displayName {
    final host = Uri.tryParse(_base)?.host ?? '';
    if (host.contains('openrouter.ai')) return 'OpenRouter';
    return host.isEmpty ? config.providerId.displayName : host;
  }

  bool get isOpenRouter => _base.contains('openrouter.ai');

  Map<String, String> get _headers => {
    ...config.extraHeaders,
    if (config.apiKey.isNotEmpty) 'authorization': 'Bearer ${config.apiKey}',
  };

  CompatJsonMode _mode = CompatJsonMode.jsonSchema;

  /// The mode that last worked (or will be tried first).
  CompatJsonMode get mode => _mode;

  @override
  Future<List<String>> listModels() async {
    final body = await getJson(joinUrl(_base, '/models'), headers: _headers);
    final data = body['data'] ?? body['models'];
    final ids = [
      for (final m in (data is List ? data : const <Object?>[]))
        if (m is Map && m['id'] is String) m['id'] as String,
    ]..sort();
    return ids;
  }

  /// Validates the key where the endpoint allows it (OpenRouter `/key`),
  /// otherwise lists models.
  Future<void> verifyKey() async {
    if (isOpenRouter) {
      await getJson(joinUrl(_base, '/key'), headers: _headers);
    } else {
      await listModels();
    }
  }

  @override
  Future<Map<String, dynamic>> generateJson({
    required String prompt,
    required Map<String, Object?> schema,
    String? schemaName,
    String? youtubeUrl,
    String? systemPrompt,
    List<LlmAttachment> attachments = const [],
  }) async {
    rejectYoutube(attachments, youtubeUrl, displayName);
    ProviderLimits.openaiCompatible.check(attachments, displayName);
    final strictSchema = toOpenAiStrictSchema(schema);
    final reject = RegExp(
      r'response_format|json_schema|json_object|structured|schema|'
      r'not supported|unsupported',
      caseSensitive: false,
    );
    while (true) {
      try {
        final response = await postJson(
          joinUrl(_base, '/chat/completions'),
          headers: _headers,
          body: _body(
            _mode,
            prompt,
            systemPrompt,
            strictSchema,
            schemaName,
            attachments,
          ),
        );
        return _parse(response);
      } on AiException catch (e) {
        final next = _mode.index + 1;
        if (next >= CompatJsonMode.values.length ||
            !HttpLlmProvider.isRejection(e, reject)) {
          rethrow;
        }
        _mode = CompatJsonMode.values[next];
      }
    }
  }

  Map<String, Object?> _body(
    CompatJsonMode mode,
    String prompt,
    String? systemPrompt,
    Map<String, Object?> schema,
    String? schemaName,
    List<LlmAttachment> attachments,
  ) {
    final system = [
      if (systemPrompt != null && systemPrompt.isNotEmpty) systemPrompt,
      if (mode != CompatJsonMode.jsonSchema)
        'Respond with a single JSON object only (no Markdown fences, no '
            'prose) that conforms to this JSON Schema:\n${jsonEncode(schema)}',
    ].join('\n\n');
    return {
      'model': config.model,
      'messages': [
        if (system.isNotEmpty) {'role': 'system', 'content': system},
        {
          'role': 'user',
          'content': attachments.isEmpty
              ? prompt
              : _content(prompt, attachments),
        },
      ],
      if (mode == CompatJsonMode.jsonSchema)
        'response_format': {
          'type': 'json_schema',
          'json_schema': {
            'name': schemaName ?? 'output',
            'strict': true,
            'schema': schema,
          },
        },
      if (mode == CompatJsonMode.jsonObject)
        'response_format': {'type': 'json_object'},
    };
  }

  static List<Map<String, Object?>> _content(
    String prompt,
    List<LlmAttachment> attachments,
  ) => [
    for (final a in attachments.whereType<LlmFileAttachment>()) ...[
      {'type': 'text', 'text': a.label},
      if (a.kind == AiInputKind.image)
        {
          'type': 'image_url',
          'image_url': {'url': dataUrl(a.mimeType, a.bytes)},
        }
      else
        {
          'type': 'file',
          'file': {
            'filename': a.filename,
            'file_data': dataUrl(a.mimeType, a.bytes),
          },
        },
    ],
    {'type': 'text', 'text': prompt},
  ];

  // ---------------------------------------------------------------- chat

  static final _streamRejection = RegExp(
    r'stream|not supported|unsupported',
    caseSensitive: false,
  );

  @override
  Stream<LlmChatEvent> streamChat({
    required List<LlmChatMessage> messages,
    String? systemPrompt,
    List<LlmAttachment> attachments = const [],
    int? maxOutputTokens,
  }) => streamSse(
    uri: joinUrl(_base, '/chat/completions'),
    headers: _headers,
    body: () async => _chatBody(
      messages,
      systemPrompt,
      attachments,
      maxOutputTokens,
      stream: true,
    ),
    parser: () => _CompatStreamParser(this),
    parseJson: _chatCompletion,
    fallback: () => completeChat(
      messages: messages,
      systemPrompt: systemPrompt,
      attachments: attachments,
      maxOutputTokens: maxOutputTokens,
    ),
    streamRejection: _streamRejection,
  );

  @override
  Future<LlmChatCompletion> completeChat({
    required List<LlmChatMessage> messages,
    String? systemPrompt,
    List<LlmAttachment> attachments = const [],
    int? maxOutputTokens,
  }) async {
    final response = await postJson(
      joinUrl(_base, '/chat/completions'),
      headers: _headers,
      body: _chatBody(
        messages,
        systemPrompt,
        attachments,
        maxOutputTokens,
        stream: false,
      ),
    );
    return _chatCompletion(response);
  }

  Map<String, Object?> _chatBody(
    List<LlmChatMessage> messages,
    String? systemPrompt,
    List<LlmAttachment> attachments,
    int? maxOutputTokens, {
    required bool stream,
  }) {
    final turns = normalizeChatMessages(messages);
    if (turns.isEmpty) {
      throw const ValidationException('Type a message first.');
    }
    rejectYoutube(attachments, null, displayName);
    ProviderLimits.openaiCompatible.check(attachments, displayName);
    return {
      'model': config.model,
      'messages': [
        if (systemPrompt != null && systemPrompt.isNotEmpty)
          {'role': 'system', 'content': systemPrompt},
        for (var i = 0; i < turns.length; i++)
          {
            'role': turns[i].role.name,
            'content': i == turns.length - 1 && attachments.isNotEmpty
                ? _content(turns[i].text, attachments)
                : turns[i].text,
          },
      ],
      if (stream) 'stream': true,
      'max_tokens': ?maxOutputTokens,
    };
  }

  static LlmFinishReason? _finishReason(Object? reason) => switch (reason) {
    null => null,
    'stop' || 'eos' || 'end_turn' => LlmFinishReason.stop,
    'length' || 'max_tokens' => LlmFinishReason.length,
    'content_filter' => LlmFinishReason.blocked,
    _ => LlmFinishReason.other,
  };

  /// Throws the mapped error when [json] carries an `error` object
  /// (OpenRouter reports upstream errors with a 200 status, also
  /// mid-stream).
  void _throwIfError(Map<String, dynamic> json) {
    final error = json['error'];
    if (error is! Map) return;
    final code = error['code'];
    throw mapHttpError(
      providerName: displayName,
      statusCode: code is int ? code : 502,
      body: json,
      rawBody: '',
      apiKey: config.apiKey,
    );
  }

  static String _contentText(Object? content) => switch (content) {
    final String s => s,
    final List<Object?> parts =>
      parts
          .whereType<Map<Object?, Object?>>()
          .map((p) => p['text'])
          .whereType<String>()
          .join(),
    _ => '',
  };

  LlmChatCompletion _chatCompletion(Map<String, dynamic> response) {
    _throwIfError(response);
    final choices = response['choices'];
    if (choices is! List || choices.isEmpty || choices.first is! Map) {
      throw AiException('$displayName returned no answer. Try again.');
    }
    final choice = choices.first as Map;
    final message = choice['message'] as Map? ?? const {};
    final text = _contentText(message['content']);
    final refusal = message['refusal'];
    if (text.isEmpty && refusal is String && refusal.isNotEmpty) {
      return LlmChatCompletion('', LlmFinishReason.refusal, detail: refusal);
    }
    final reason = choice['finish_reason'];
    return LlmChatCompletion(
      text,
      _finishReason(reason) ?? LlmFinishReason.stop,
      detail: reason?.toString(),
    );
  }

  Map<String, dynamic> _parse(Map<String, dynamic> response) {
    final choices = response['choices'];
    if (choices is! List || choices.isEmpty) {
      // OpenRouter can report upstream errors with a 200 status.
      final error = response['error'];
      if (error is Map) {
        final code = error['code'];
        throw mapHttpError(
          providerName: displayName,
          statusCode: code is int ? code : 502,
          body: response,
          rawBody: '',
          apiKey: config.apiKey,
        );
      }
      throw AiException('$displayName returned no answer. Try again.');
    }
    final choice = choices.first as Map? ?? const {};
    final message = choice['message'] as Map? ?? const {};
    final content = message['content'];
    final text = switch (content) {
      final String s => s,
      final List<Object?> parts =>
        parts
            .whereType<Map<Object?, Object?>>()
            .map((p) => p['text'])
            .whereType<String>()
            .join(),
      _ => '',
    };
    final refusal = message['refusal'];
    if (text.isEmpty && refusal is String && refusal.isNotEmpty) {
      throw AiException('$displayName declined this request: $refusal');
    }
    if (choice['finish_reason'] == 'length') {
      throw AiException(
        '$displayName ran out of output space. Ask for fewer questions or '
        'shorten the input.',
        kind: AiErrorKind.invalidOutput,
        cause: RawModelOutput(text, truncated: true),
      );
    }
    return decodeJsonObject(text, providerName: displayName);
  }
}

/// Chat Completions streaming: `data: {choices: [{delta: {content},
/// finish_reason}]}` chunks, terminated by `data: [DONE]`. OpenRouter adds
/// `: OPENROUTER PROCESSING` comments and may send `{error: {...}}`
/// mid-stream.
class _CompatStreamParser implements SseChatParser {
  _CompatStreamParser(this._provider);

  final OpenAiCompatibleProvider _provider;
  LlmFinishReason? _finish;
  String? _detail;
  final _refusal = StringBuffer();
  var _hasText = false;

  LlmChatDone _done() {
    if (!_hasText && _refusal.isNotEmpty) {
      return LlmChatDone(LlmFinishReason.refusal, detail: _refusal.toString());
    }
    return LlmChatDone(_finish ?? LlmFinishReason.stop, detail: _detail);
  }

  @override
  Iterable<LlmChatEvent> onEvent(SseEvent event) {
    if (event.data.trim() == '[DONE]') return [_done()];
    final json = sseJson(event);
    if (json == null) return const [];
    _provider._throwIfError(json);
    final choices = json['choices'];
    if (choices is! List || choices.isEmpty || choices.first is! Map) {
      return const [];
    }
    final choice = choices.first as Map;
    final reason = choice['finish_reason'];
    if (reason != null) {
      _finish = OpenAiCompatibleProvider._finishReason(reason);
      _detail = reason.toString();
    }
    final delta = choice['delta'];
    if (delta is! Map) return const [];
    final refusal = delta['refusal'];
    if (refusal is String) _refusal.write(refusal);
    final text = OpenAiCompatibleProvider._contentText(delta['content']);
    if (text.isEmpty) return const [];
    _hasText = true;
    return [LlmTextDelta(text)];
  }

  /// Some servers close without `[DONE]`; accept that once a finish reason
  /// arrived.
  @override
  LlmChatDone onEnd() {
    if (_finish == null) throw streamInterrupted(_provider.displayName);
    return _done();
  }
}
