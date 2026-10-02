import 'dart:convert';

import '../../core/errors/app_exception.dart';
import '../llm_provider.dart';
import 'http_support.dart';
import 'schema_adapters.dart';

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
/// * `GET {baseUrl}/models`. For OpenRouter `testConnection` additionally
///   calls `GET {baseUrl}/key`, since `/models` does not need a key there.
class OpenAiCompatibleProvider extends HttpLlmProvider {
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
  }) async {
    if (youtubeUrl != null) {
      throw AiException(
        '$displayName cannot watch YouTube videos directly; a transcript is '
        'used instead.',
        kind: AiErrorKind.unsupported,
      );
    }
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
          body: _body(_mode, prompt, systemPrompt, strictSchema, schemaName),
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
        {'role': 'user', 'content': prompt},
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
