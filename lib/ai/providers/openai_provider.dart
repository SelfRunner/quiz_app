import '../../core/errors/app_exception.dart';
import '../ai_source.dart';
import '../llm_provider.dart';
import 'attachment_support.dart';
import 'http_support.dart';
import 'schema_adapters.dart';

/// OpenAI via the Responses API (recommended over Chat Completions for new
/// integrations).
///
/// * `POST {base}/v1/responses` with `Authorization: Bearer <key>`,
///   `instructions` (system prompt), `input` (user prompt), `store: false`
///   and `text.format = {type: json_schema, name, schema, strict: true}`.
/// * Output: `output[]` items of `type: message` whose `content[]` holds
///   `output_text` (JSON) or `refusal`.
/// * Attachments: `input` becomes one user message whose `content` holds
///   `input_text` labels, `input_file` (`filename` + base64 `file_data` data
///   URL) for PDFs, `input_image` (data URL) for images, then the prompt.
///   No audio/video (see `ProviderLimits.openai`).
/// * `GET {base}/v1/models`, filtered to text-generation model families.
class OpenAiProvider extends HttpLlmProvider {
  OpenAiProvider(
    super.config,
    super.client, {
    super.generateTimeout,
    super.listTimeout,
    super.isWeb,
  });

  static const defaultBaseUrl = 'https://api.openai.com/v1';

  String get _base => config.baseUrl ?? defaultBaseUrl;
  Map<String, String> get _headers => {
    'authorization': 'Bearer ${config.apiKey}',
  };

  static final _chatModel = RegExp(r'^(gpt-|o\d|chatgpt-)');
  static final _nonChat = RegExp(
    r'(audio|realtime|tts|transcribe|image|embedding|moderation|search|'
    r'instruct|codex|computer-use|dall-e|whisper|sora)',
  );

  /// Whether a model id from `/v1/models` is usable for text generation.
  static bool isTextModel(String id) =>
      _chatModel.hasMatch(id) && !_nonChat.hasMatch(id);

  @override
  Future<List<String>> listModels() async {
    final body = await getJson(joinUrl(_base, '/models'), headers: _headers);
    final ids = [
      for (final m in (body['data'] as List? ?? const []))
        if (m is Map && m['id'] is String && isTextModel(m['id'] as String))
          m['id'] as String,
    ]..sort();
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
    rejectYoutube(attachments, youtubeUrl, displayName);
    ProviderLimits.openai.check(attachments, displayName);
    final response = await postJson(
      joinUrl(_base, '/responses'),
      headers: _headers,
      body: {
        'model': config.model,
        if (systemPrompt != null && systemPrompt.isNotEmpty)
          'instructions': systemPrompt,
        'input': attachments.isEmpty ? prompt : _input(prompt, attachments),
        'store': false,
        'text': {
          'format': {
            'type': 'json_schema',
            'name': schemaName ?? 'output',
            'schema': toOpenAiStrictSchema(schema),
            'strict': true,
          },
        },
      },
    );
    return _parse(response);
  }

  static List<Map<String, Object?>> _input(
    String prompt,
    List<LlmAttachment> attachments,
  ) => [
    {
      'role': 'user',
      'content': [
        for (final a in attachments.whereType<LlmFileAttachment>()) ...[
          {'type': 'input_text', 'text': a.label},
          if (a.kind == AiInputKind.image)
            {'type': 'input_image', 'image_url': dataUrl(a.mimeType, a.bytes)}
          else
            {
              'type': 'input_file',
              'filename': a.filename,
              'file_data': dataUrl(a.mimeType, a.bytes),
            },
        ],
        {'type': 'input_text', 'text': prompt},
      ],
    },
  ];

  Map<String, dynamic> _parse(Map<String, dynamic> response) {
    final buffer = StringBuffer();
    String? refusal;
    for (final item in (response['output'] as List? ?? const [])) {
      if (item is! Map || item['type'] != 'message') continue;
      for (final c in (item['content'] as List? ?? const [])) {
        if (c is! Map) continue;
        if (c['type'] == 'output_text' && c['text'] is String) {
          buffer.write(c['text']);
        } else if (c['type'] == 'refusal') {
          refusal = c['refusal']?.toString();
        }
      }
    }
    final text = buffer.toString();
    if (text.isEmpty && refusal != null) {
      throw AiException(
        'OpenAI declined this request${refusal.isEmpty ? '' : ': $refusal'}',
      );
    }
    if (response['status'] == 'incomplete') {
      final reason = (response['incomplete_details'] as Map?)?['reason'];
      throw AiException(
        reason == 'max_output_tokens'
            ? 'OpenAI ran out of output space. Ask for fewer questions or '
                  'shorten the input.'
            : 'OpenAI stopped early${reason == null ? '' : ' ($reason)'}.',
        kind: AiErrorKind.invalidOutput,
        cause: RawModelOutput(text, truncated: reason == 'max_output_tokens'),
      );
    }
    final error = response['error'];
    if (text.isEmpty && error is Map) {
      throw AiException('OpenAI error: ${error['message'] ?? 'unknown'}');
    }
    return decodeJsonObject(text, providerName: displayName);
  }
}
