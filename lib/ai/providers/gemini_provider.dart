import '../../core/errors/app_exception.dart';
import 'http_support.dart';
import 'schema_adapters.dart';

/// Google Gemini via the Generative Language API (`v1beta`).
///
/// * `POST {base}/v1beta/models/{model}:generateContent`, key in the
///   `x-goog-api-key` header.
/// * Structured output: `generationConfig.responseFormat.text =
///   {mimeType: APPLICATION_JSON, schema: JSON Schema}` (current API). If
///   the endpoint rejects `responseFormat`, falls back to the deprecated
///   `responseMimeType: application/json` + `responseJsonSchema`.
/// * YouTube: the URL is sent as a `fileData` part (`fileUri`) before the
///   text part. Only public videos work.
/// * `GET {base}/v1beta/models` (paged) filtered to models whose
///   `supportedGenerationMethods` contain `generateContent`.
class GeminiProvider extends HttpLlmProvider {
  GeminiProvider(
    super.config,
    super.client, {
    super.generateTimeout,
    super.listTimeout,
    super.isWeb,
  });

  static const defaultBaseUrl = 'https://generativelanguage.googleapis.com';

  String get _base => config.baseUrl ?? defaultBaseUrl;
  Map<String, String> get _headers => {'x-goog-api-key': config.apiKey};

  /// Model id without the `models/` resource prefix.
  static String bareModel(String model) =>
      model.startsWith('models/') ? model.substring(7) : model;

  bool _useLegacySchemaField = false;

  @override
  Future<List<String>> listModels() async {
    final models = <String>[];
    String? pageToken;
    var pages = 0;
    do {
      final uri = joinUrl(
        _base,
        '/v1beta/models',
      ).replace(queryParameters: {'pageSize': '1000', 'pageToken': ?pageToken});
      final body = await getJson(uri, headers: _headers);
      for (final m in (body['models'] as List? ?? const [])) {
        if (m is! Map) continue;
        final methods = (m['supportedGenerationMethods'] as List?) ?? const [];
        final name = m['name'];
        if (name is String && methods.contains('generateContent')) {
          models.add(bareModel(name));
        }
      }
      final next = body['nextPageToken'];
      pageToken = next is String && next.isNotEmpty ? next : null;
    } while (pageToken != null && ++pages < 10);
    return models;
  }

  @override
  Future<Map<String, dynamic>> generateJson({
    required String prompt,
    required Map<String, Object?> schema,
    String? schemaName,
    String? youtubeUrl,
    String? systemPrompt,
  }) async {
    final geminiSchema = toGeminiSchema(schema);
    final uri = joinUrl(
      _base,
      '/v1beta/models/${bareModel(config.model)}:generateContent',
    );

    Map<String, Object?> buildBody({required bool legacy}) => {
      if (systemPrompt != null && systemPrompt.isNotEmpty)
        'systemInstruction': {
          'parts': [
            {'text': systemPrompt},
          ],
        },
      'contents': [
        {
          'role': 'user',
          'parts': [
            if (youtubeUrl != null)
              {
                'fileData': {'fileUri': youtubeUrl},
              },
            {'text': prompt},
          ],
        },
      ],
      'generationConfig': legacy
          ? {
              'responseMimeType': 'application/json',
              'responseJsonSchema': geminiSchema,
            }
          : {
              'responseFormat': {
                'text': {
                  'mimeType': 'APPLICATION_JSON',
                  'schema': geminiSchema,
                },
              },
            },
    };

    Map<String, dynamic> response;
    try {
      response = await postJson(
        uri,
        headers: _headers,
        body: buildBody(legacy: _useLegacySchemaField),
      );
    } on AiException catch (e) {
      if (_useLegacySchemaField ||
          !HttpLlmProvider.isRejection(
            e,
            RegExp(r'response_?format|unknown name', caseSensitive: false),
          )) {
        rethrow;
      }
      _useLegacySchemaField = true;
      response = await postJson(
        uri,
        headers: _headers,
        body: buildBody(legacy: true),
      );
    }
    return _parse(response);
  }

  Map<String, dynamic> _parse(Map<String, dynamic> response) {
    final feedback = response['promptFeedback'];
    if (feedback is Map && feedback['blockReason'] != null) {
      throw AiException(
        'Gemini blocked this request (${feedback['blockReason']}). Try '
        'different source material.',
      );
    }
    final candidates = response['candidates'];
    if (candidates is! List || candidates.isEmpty) {
      throw const AiException('Gemini returned no answer. Try again.');
    }
    final candidate = candidates.first;
    if (candidate is! Map) {
      throw const AiException('Gemini returned an unexpected response.');
    }
    final finish = candidate['finishReason'];
    final parts = (candidate['content'] as Map?)?['parts'] as List? ?? const [];
    final text = parts
        .whereType<Map<Object?, Object?>>()
        .where((p) => p['thought'] != true && p['text'] is String)
        .map((p) => p['text']! as String)
        .join();
    if (finish == 'MAX_TOKENS') {
      throw AiException(
        'Gemini ran out of output space. Ask for fewer questions or shorten '
        'the input.',
        kind: AiErrorKind.invalidOutput,
        cause: RawModelOutput(text, truncated: true),
      );
    }
    if (text.isEmpty &&
        finish is String &&
        finish != 'STOP' &&
        finish != 'FINISH_REASON_UNSPECIFIED') {
      throw AiException(
        'Gemini stopped without an answer ($finish). Try different source '
        'material.',
      );
    }
    return decodeJsonObject(text, providerName: displayName);
  }
}
