import '../../core/errors/app_exception.dart';
import '../ai_source.dart';
import '../llm_chat.dart';
import '../llm_provider.dart';
import 'attachment_support.dart';
import 'http_support.dart';
import 'schema_adapters.dart';
import 'sse.dart';

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
class OpenAiProvider extends HttpLlmProvider implements LlmChatProvider {
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
    {'role': 'user', 'content': _userContent(prompt, attachments)},
  ];

  static List<Map<String, Object?>> _userContent(
    String prompt,
    List<LlmAttachment> attachments,
  ) => [
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
  ];

  // ---------------------------------------------------------------- chat

  @override
  Stream<LlmChatEvent> streamChat({
    required List<LlmChatMessage> messages,
    String? systemPrompt,
    List<LlmAttachment> attachments = const [],
    int? maxOutputTokens,
  }) => streamSse(
    uri: joinUrl(_base, '/responses'),
    headers: _headers,
    body: () async => _chatBody(
      messages,
      systemPrompt,
      attachments,
      maxOutputTokens,
      stream: true,
    ),
    parser: _OpenAiStreamParser.new,
    parseJson: _chatCompletion,
    fallback: () => completeChat(
      messages: messages,
      systemPrompt: systemPrompt,
      attachments: attachments,
      maxOutputTokens: maxOutputTokens,
    ),
    streamRejection: RegExp('stream', caseSensitive: false),
  );

  @override
  Future<LlmChatCompletion> completeChat({
    required List<LlmChatMessage> messages,
    String? systemPrompt,
    List<LlmAttachment> attachments = const [],
    int? maxOutputTokens,
  }) async {
    final response = await postJson(
      joinUrl(_base, '/responses'),
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
    ProviderLimits.openai.check(attachments, displayName);
    return {
      'model': config.model,
      if (systemPrompt != null && systemPrompt.isNotEmpty)
        'instructions': systemPrompt,
      'input': [
        for (var i = 0; i < turns.length; i++)
          {
            'role': turns[i].role.name,
            'content': i == turns.length - 1 && attachments.isNotEmpty
                ? _userContent(turns[i].text, attachments)
                : turns[i].text,
          },
      ],
      'store': false,
      if (stream) 'stream': true,
      'max_output_tokens': ?maxOutputTokens,
    };
  }

  /// Text + finish state of a complete Responses API object.
  static LlmChatCompletion _chatCompletion(Map<String, dynamic> response) {
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
    final failure = _responseError(response);
    if (failure != null && text.isEmpty) throw failure;
    if (response['status'] == 'incomplete') {
      final reason = (response['incomplete_details'] as Map?)?['reason'];
      return LlmChatCompletion(
        text,
        _incompleteReason(reason),
        detail: reason?.toString(),
      );
    }
    if (text.isEmpty && refusal != null) {
      return LlmChatCompletion('', LlmFinishReason.refusal, detail: refusal);
    }
    return LlmChatCompletion(text, LlmFinishReason.stop);
  }

  static LlmFinishReason _incompleteReason(Object? reason) => switch (reason) {
    'max_output_tokens' => LlmFinishReason.length,
    'content_filter' => LlmFinishReason.blocked,
    _ => LlmFinishReason.other,
  };

  /// `AiException` for a failed response / `error` stream event, else null.
  static AiException? _responseError(Map<String, dynamic> json) {
    final error = json['error'];
    final Map<Object?, Object?>? e = error is Map
        ? error
        : (json['type'] == 'error' ? json : null);
    if (e == null) return null;
    final code = '${e['code'] ?? e['type'] ?? ''}'.toLowerCase();
    final message = e['message']?.toString() ?? 'unknown error';
    if (code.contains('rate_limit') || code.contains('quota')) {
      return AiException(
        'OpenAI rate limit or quota reached ($message).',
        kind: AiErrorKind.rateLimited,
      );
    }
    return AiException('OpenAI error: $message');
  }

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

/// Responses API streaming: `response.output_text.delta` carries text,
/// `response.completed` / `response.incomplete` end the stream,
/// `response.failed` and `error` events fail it.
class _OpenAiStreamParser implements SseChatParser {
  final _refusal = StringBuffer();
  var _hasText = false;

  @override
  Iterable<LlmChatEvent> onEvent(SseEvent event) {
    final json = sseJson(event);
    if (json == null) return const [];
    final type = json['type'] ?? event.event;
    switch (type) {
      case 'response.output_text.delta':
        final delta = json['delta'];
        if (delta is String && delta.isNotEmpty) {
          _hasText = true;
          return [LlmTextDelta(delta)];
        }
      case 'response.refusal.delta':
        final delta = json['delta'];
        if (delta is String) _refusal.write(delta);
      case 'response.completed':
        if (!_hasText && _refusal.isNotEmpty) {
          return [
            LlmChatDone(LlmFinishReason.refusal, detail: _refusal.toString()),
          ];
        }
        return const [LlmChatDone(LlmFinishReason.stop)];
      case 'response.incomplete':
        final response = json['response'];
        final details = response is Map ? response['incomplete_details'] : null;
        final reason = details is Map ? details['reason'] : null;
        return [
          LlmChatDone(
            OpenAiProvider._incompleteReason(reason),
            detail: reason?.toString(),
          ),
        ];
      case 'response.failed':
        final response = json['response'];
        throw (response is Map<String, dynamic>
                ? OpenAiProvider._responseError(response)
                : null) ??
            const AiException('OpenAI could not complete the answer.');
      case 'error':
        throw OpenAiProvider._responseError(json)!;
    }
    return const [];
  }

  @override
  LlmChatDone onEnd() => throw streamInterrupted('OpenAI');
}
