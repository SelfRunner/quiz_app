import 'dart:convert';

import '../../core/errors/app_exception.dart';
import '../llm_provider.dart';
import 'attachment_support.dart';
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
/// * Files (PDF, images, audio, video): `inlineData` (base64) while the
///   request holds at most [ProviderLimits.geminiInlineBytes] of inline
///   data; larger files are uploaded with the Files API (resumable upload to
///   `POST {base}/upload/v1beta/files`, then `fileData{mimeType, fileUri}`),
///   polling `GET {base}/v1beta/files/{id}` until the file is `ACTIVE`
///   (videos are processed for a while). Uploads are reused for the repair
///   retry of the same generation; Gemini deletes them after 48 h.
/// * `GET {base}/v1beta/models` (paged) filtered to models whose
///   `supportedGenerationMethods` contain `generateContent`.
class GeminiProvider extends HttpLlmProvider {
  GeminiProvider(
    super.config,
    super.client, {
    super.generateTimeout,
    super.listTimeout,
    super.isWeb,
    this.filePollInterval = const Duration(seconds: 2),
    this.fileProcessingTimeout = const Duration(minutes: 5),
  });

  /// Delay between `files.get` polls while an upload is `PROCESSING`.
  final Duration filePollInterval;

  /// Give up waiting for an upload to become `ACTIVE` after this long.
  final Duration fileProcessingTimeout;

  final _uploads = Map<LlmFileAttachment, GeminiFile>.identity();

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
    List<LlmAttachment> attachments = const [],
  }) async {
    ProviderLimits.gemini.check(attachments, displayName);
    final mediaParts = await _attachmentParts([
      if (youtubeUrl != null) LlmYoutubeAttachment(label: '', url: youtubeUrl),
      ...attachments,
    ]);
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
            ...mediaParts,
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

  Future<List<Map<String, Object?>>> _attachmentParts(
    List<LlmAttachment> attachments,
  ) async {
    final parts = <Map<String, Object?>>[];
    var inlineBytes = 0;
    for (final a in attachments) {
      if (a.label.isNotEmpty) parts.add({'text': a.label});
      switch (a) {
        case LlmYoutubeAttachment(:final url):
          parts.add({
            'fileData': {'fileUri': url},
          });
        case LlmFileAttachment():
          final size = a.bytes.length;
          if (inlineBytes + size <= ProviderLimits.geminiInlineBytes) {
            inlineBytes += size;
            parts.add({
              'inlineData': {
                'mimeType': a.mimeType,
                'data': base64Encode(a.bytes),
              },
            });
          } else {
            final file = await uploadFile(a);
            parts.add({
              'fileData': {'mimeType': file.mimeType, 'fileUri': file.uri},
            });
          }
      }
    }
    return parts;
  }

  /// Uploads [a] with the Files API (resumable protocol) and waits until it
  /// is `ACTIVE`. Cached per attachment instance.
  Future<GeminiFile> uploadFile(LlmFileAttachment a) async {
    final cached = _uploads[a];
    if (cached != null) return cached;

    final start = await sendRaw(
      () => client.post(
        joinUrl(_base, '/upload/v1beta/files'),
        headers: {
          ..._headers,
          'x-goog-upload-protocol': 'resumable',
          'x-goog-upload-command': 'start',
          'x-goog-upload-header-content-length': '${a.bytes.length}',
          'x-goog-upload-header-content-type': a.mimeType,
          'content-type': 'application/json',
        },
        body: jsonEncode({
          'file': {'display_name': a.filename},
        }),
      ),
      timeout: listTimeout,
    );
    final uploadUrl = start.headers['x-goog-upload-url'];
    if (uploadUrl == null || uploadUrl.isEmpty) {
      throw AiException(
        'Gemini did not accept the upload of "${a.filename}"'
        '${isWeb ? ' (the browser may be blocking the upload URL)' : ''}. '
        'Try again or use a smaller file.',
      );
    }
    final done = await sendRaw(
      () => client.post(
        Uri.parse(uploadUrl),
        headers: {
          ..._headers,
          'x-goog-upload-offset': '0',
          'x-goog-upload-command': 'upload, finalize',
          'content-type': a.mimeType,
        },
        body: a.bytes,
      ),
    );
    var file = GeminiFile.fromJson(_decodeMap(done.body), a);
    final deadline = DateTime.now().add(fileProcessingTimeout);
    while (file.state == 'PROCESSING' || file.state == 'STATE_UNSPECIFIED') {
      if (DateTime.now().isAfter(deadline)) {
        throw AiException(
          'Gemini is still processing "${a.filename}". Try again in a '
          'minute.',
        );
      }
      await Future<void>.delayed(filePollInterval);
      final body = await getJson(
        joinUrl(_base, '/v1beta/${file.name}'),
        headers: _headers,
      );
      file = GeminiFile.fromJson(body, a);
    }
    if (file.state == 'FAILED') {
      throw AiException(
        'Gemini could not process "${a.filename}". Check that the file is '
        'not corrupt and try again.',
      );
    }
    return _uploads[a] = file;
  }

  static Map<String, dynamic> _decodeMap(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException {
      // fall through
    }
    throw const AiException('Gemini returned an unexpected upload response.');
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

/// A file stored with the Gemini Files API.
class GeminiFile {
  const GeminiFile({
    required this.name,
    required this.uri,
    required this.mimeType,
    required this.state,
  });

  /// Parses `{file: {...}}` (upload result) or a bare file resource.
  factory GeminiFile.fromJson(
    Map<String, dynamic> json,
    LlmFileAttachment source,
  ) {
    final f = json['file'] is Map ? json['file'] as Map : json;
    final name = f['name'];
    final uri = f['uri'];
    if (name is! String || uri is! String) {
      throw const AiException('Gemini returned an unexpected upload response.');
    }
    final mime = f['mimeType'];
    final state = f['state'];
    return GeminiFile(
      name: name,
      uri: uri,
      mimeType: mime is String && mime.isNotEmpty ? mime : source.mimeType,
      // Files without a state are usable immediately.
      state: state is String ? state : 'ACTIVE',
    );
  }

  /// Resource name, e.g. `files/abc123`.
  final String name;
  final String uri;
  final String mimeType;

  /// `PROCESSING`, `ACTIVE` or `FAILED`.
  final String state;
}
