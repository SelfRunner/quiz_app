import 'dart:convert';

import '../../core/errors/app_exception.dart';
import '../ai_source.dart';
import '../llm_provider.dart';
import 'attachment_support.dart';
import 'http_support.dart';
import 'schema_adapters.dart';

/// Anthropic Claude via the Messages API.
///
/// * `POST {base}/v1/messages` with `x-api-key`, `anthropic-version:
///   2023-06-01` and, on web, `anthropic-dangerous-direct-browser-access:
///   true` (required for CORS).
/// * Structured output: GA `output_config.format = {type: json_schema,
///   schema}` (no beta header). If a model/endpoint rejects it, falls back to
///   a forced tool call (`tools[0].input_schema` + `tool_choice: {type:
///   tool}`).
/// * Attachments: the user message `content` becomes blocks: a `text`
///   label, then `document` (base64 PDF, with `title`) or `image` (base64),
///   per file, then the prompt. No audio/video (`ProviderLimits.anthropic`).
/// * `GET {base}/v1/models` (paged with `after_id`).
class AnthropicProvider extends HttpLlmProvider {
  AnthropicProvider(
    super.config,
    super.client, {
    super.generateTimeout,
    super.listTimeout,
    super.isWeb,
    this.maxTokens = 16000,
  });

  static const defaultBaseUrl = 'https://api.anthropic.com';
  static const apiVersion = '2023-06-01';

  final int maxTokens;

  String get _base => config.baseUrl ?? defaultBaseUrl;
  Map<String, String> get _headers => {
    'x-api-key': config.apiKey,
    'anthropic-version': apiVersion,
    if (isWeb) 'anthropic-dangerous-direct-browser-access': 'true',
  };

  bool _useToolFallback = false;

  @override
  Future<List<String>> listModels() async {
    final ids = <String>[];
    String? afterId;
    var pages = 0;
    do {
      final uri = joinUrl(
        _base,
        '/v1/models',
      ).replace(queryParameters: {'limit': '1000', 'after_id': ?afterId});
      final body = await getJson(uri, headers: _headers);
      for (final m in (body['data'] as List? ?? const [])) {
        if (m is Map && m['id'] is String) ids.add(m['id'] as String);
      }
      final last = body['last_id'];
      afterId = body['has_more'] == true && last is String ? last : null;
    } while (afterId != null && ++pages < 10);
    return ids;
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
    rejectYoutube(attachments, youtubeUrl, 'Claude');
    ProviderLimits.anthropic.check(attachments, displayName);
    final adapted = toAnthropicSchema(schema);
    final toolName = _toolName(schemaName);
    final base = <String, Object?>{
      'model': config.model,
      'max_tokens': maxTokens,
      if (systemPrompt != null && systemPrompt.isNotEmpty)
        'system': systemPrompt,
      'messages': [
        {
          'role': 'user',
          'content': attachments.isEmpty
              ? prompt
              : _content(prompt, attachments),
        },
      ],
    };
    Map<String, Object?> structured() => {
      ...base,
      'output_config': {
        'format': {'type': 'json_schema', 'schema': adapted},
      },
    };
    Map<String, Object?> tool() => {
      ...base,
      'tools': [
        {
          'name': toolName,
          'description': 'Return the result as structured data.',
          'input_schema': adapted,
        },
      ],
      'tool_choice': {'type': 'tool', 'name': toolName},
    };

    final uri = joinUrl(_base, '/v1/messages');
    Map<String, dynamic> response;
    try {
      response = await postJson(
        uri,
        headers: _headers,
        body: _useToolFallback ? tool() : structured(),
      );
    } on AiException catch (e) {
      if (_useToolFallback ||
          !HttpLlmProvider.isRejection(
            e,
            RegExp(
              r'output_config|structured output|json_schema|format',
              caseSensitive: false,
            ),
          )) {
        rethrow;
      }
      _useToolFallback = true;
      response = await postJson(uri, headers: _headers, body: tool());
    }
    return _parse(response);
  }

  static List<Map<String, Object?>> _content(
    String prompt,
    List<LlmAttachment> attachments,
  ) => [
    for (final a in attachments.whereType<LlmFileAttachment>()) ...[
      {'type': 'text', 'text': a.label},
      if (a.kind == AiInputKind.image)
        {
          'type': 'image',
          'source': {
            'type': 'base64',
            'media_type': a.mimeType,
            'data': base64Encode(a.bytes),
          },
        }
      else
        {
          'type': 'document',
          'source': {
            'type': 'base64',
            'media_type': a.mimeType,
            'data': base64Encode(a.bytes),
          },
          'title': a.filename,
        },
    ],
    {'type': 'text', 'text': prompt},
  ];

  static String _toolName(String? schemaName) {
    final cleaned = (schemaName ?? 'output').replaceAll(
      RegExp(r'[^a-zA-Z0-9_-]'),
      '_',
    );
    return 'submit_$cleaned';
  }

  Map<String, dynamic> _parse(Map<String, dynamic> response) {
    final content = response['content'] as List? ?? const [];
    final text = StringBuffer();
    for (final block in content) {
      if (block is! Map) continue;
      if (block['type'] == 'tool_use' && block['input'] is Map) {
        return (block['input'] as Map).cast<String, dynamic>();
      }
      if (block['type'] == 'text' && block['text'] is String) {
        text.write(block['text']);
      }
    }
    final stop = response['stop_reason'];
    if (stop == 'refusal') {
      throw const AiException(
        'Claude declined this request. Try different source material.',
      );
    }
    if (stop == 'max_tokens') {
      throw AiException(
        'Claude ran out of output space. Ask for fewer questions or shorten '
        'the input.',
        kind: AiErrorKind.invalidOutput,
        cause: RawModelOutput(text.toString(), truncated: true),
      );
    }
    return decodeJsonObject(text.toString(), providerName: displayName);
  }
}
