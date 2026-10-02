import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:quiz_app/ai/ai_source.dart';
import 'package:quiz_app/ai/llm_provider.dart';
import 'package:quiz_app/ai/providers/anthropic_provider.dart';
import 'package:quiz_app/ai/providers/attachment_support.dart';
import 'package:quiz_app/ai/providers/gemini_provider.dart';
import 'package:quiz_app/ai/providers/openai_compatible_provider.dart';
import 'package:quiz_app/ai/providers/openai_provider.dart';
import 'package:quiz_app/core/errors/app_exception.dart';
import 'package:quiz_app/data/models/models.dart';

import 'test_helpers.dart';

const _mb = 1024 * 1024;
final _pdfBytes = Uint8List.fromList(utf8.encode('%PDF-1.7 fake'));
final _pngBytes = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]);
final _pdfB64 = base64Encode(_pdfBytes);
final _pngB64 = base64Encode(_pngBytes);

LlmFileAttachment _pdf({int n = 1, Uint8List? bytes}) => LlmFileAttachment(
  label: 'Attachment $n: notes.pdf',
  filename: 'notes.pdf',
  mimeType: 'application/pdf',
  bytes: bytes ?? _pdfBytes,
  kind: AiInputKind.pdf,
);

LlmFileAttachment _png({
  int n = 2,
  Uint8List? bytes,
  String mime = 'image/png',
}) => LlmFileAttachment(
  label: 'Attachment $n: board.png',
  filename: 'board.png',
  mimeType: mime,
  bytes: bytes ?? _pngBytes,
  kind: AiInputKind.image,
);

LlmFileAttachment _video(Uint8List bytes, {int n = 1}) => LlmFileAttachment(
  label: 'Attachment $n: lecture.mp4',
  filename: 'lecture.mp4',
  mimeType: 'video/mp4',
  bytes: bytes,
  kind: AiInputKind.video,
);

LlmConfig _config(LlmProviderId id, String model, {String? baseUrl}) =>
    LlmConfig(providerId: id, apiKey: 'secret', model: model, baseUrl: baseUrl);

final _note = jsonEncode({'title': 'T', 'content_markdown': '## A\n- b'});

Map<String, dynamic> _geminiOk() => {
  'candidates': [
    {
      'content': {
        'parts': [
          {'text': _note},
        ],
      },
      'finishReason': 'STOP',
    },
  ],
};

Map<String, dynamic> _openAiOk() => {
  'status': 'completed',
  'output': [
    {
      'type': 'message',
      'content': [
        {'type': 'output_text', 'text': _note},
      ],
    },
  ],
};

Map<String, dynamic> _anthropicOk() => {
  'content': [
    {'type': 'text', 'text': _note},
  ],
  'stop_reason': 'end_turn',
};

Map<String, dynamic> _chatOk() => {
  'choices': [
    {
      'message': {'role': 'assistant', 'content': _note},
      'finish_reason': 'stop',
    },
  ],
};

Matcher _throwsKind(AiErrorKind kind, [Object? message]) => throwsA(
  isA<AiException>()
      .having((e) => e.kind, 'kind', kind)
      .having((e) => e.message, 'message', message ?? anything),
);

void main() {
  group('Gemini', () {
    GeminiProvider provider(RecordingClient rc) => GeminiProvider(
      _config(LlmProviderId.gemini, 'gemini-flash-latest'),
      rc.client,
      isWeb: false,
      filePollInterval: Duration.zero,
    );

    test('small files go inline, labeled, before the prompt', () async {
      final rc = RecordingClient([(_) => jsonResponse(_geminiOk())]);
      await provider(rc).generateJson(
        prompt: 'Make notes',
        schema: noteDraftJsonSchema,
        attachments: [
          _pdf(),
          _png(),
          const LlmYoutubeAttachment(
            label: 'Attachment 3: YouTube video',
            url: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
          ),
        ],
      );
      final parts =
          ((rc.requests.single.json['contents'] as List).single as Map)['parts']
              as List;
      expect(parts, [
        {'text': 'Attachment 1: notes.pdf'},
        {
          'inlineData': {'mimeType': 'application/pdf', 'data': _pdfB64},
        },
        {'text': 'Attachment 2: board.png'},
        {
          'inlineData': {'mimeType': 'image/png', 'data': _pngB64},
        },
        {'text': 'Attachment 3: YouTube video'},
        {
          'fileData': {
            'fileUri': 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
          },
        },
        {'text': 'Make notes'},
      ]);
    });

    test('Files API: resumable upload, poll until ACTIVE, file_uri part, '
        'reused on retry', () async {
      final big = Uint8List(ProviderLimits.geminiInlineBytes + 1);
      const uploadUrl =
          'https://generativelanguage.googleapis.com/upload/v1beta/files?upload_id=xyz';
      const fileUri =
          'https://generativelanguage.googleapis.com/v1beta/files/abc';
      final rc = RecordingClient([
        // 1. start
        (_) =>
            http.Response('', 200, headers: {'x-goog-upload-url': uploadUrl}),
        // 2. upload + finalize
        (_) => jsonResponse({
          'file': {
            'name': 'files/abc',
            'uri': fileUri,
            'mimeType': 'video/mp4',
            'state': 'PROCESSING',
          },
        }),
        // 3. poll: still processing
        (_) => jsonResponse({
          'name': 'files/abc',
          'uri': fileUri,
          'state': 'PROCESSING',
        }),
        // 4. poll: active
        (_) => jsonResponse({
          'name': 'files/abc',
          'uri': fileUri,
          'mimeType': 'video/mp4',
          'state': 'ACTIVE',
        }),
        // 5./6. generateContent (twice)
        (_) => jsonResponse(_geminiOk()),
      ]);
      final p = provider(rc);
      final video = _video(big);
      await p.generateJson(
        prompt: 'Quiz',
        schema: noteDraftJsonSchema,
        attachments: [video],
      );

      final start = rc.requests[0];
      expect(start.method, 'POST');
      expect(
        start.url.toString(),
        'https://generativelanguage.googleapis.com/upload/v1beta/files',
      );
      expect(start.headers['x-goog-api-key'], 'secret');
      expect(start.headers['x-goog-upload-protocol'], 'resumable');
      expect(start.headers['x-goog-upload-command'], 'start');
      expect(
        start.headers['x-goog-upload-header-content-length'],
        '${big.length}',
      );
      expect(start.headers['x-goog-upload-header-content-type'], 'video/mp4');
      expect(start.json, {
        'file': {'display_name': 'lecture.mp4'},
      });

      final upload = rc.requests[1];
      expect(upload.url.toString(), uploadUrl);
      expect(upload.headers['x-goog-upload-command'], 'upload, finalize');
      expect(upload.headers['x-goog-upload-offset'], '0');
      expect(upload.request.bodyBytes.length, big.length);

      expect(rc.requests[2].method, 'GET');
      expect(
        rc.requests[2].url.toString(),
        'https://generativelanguage.googleapis.com/v1beta/files/abc',
      );
      expect(rc.requests[3].method, 'GET');

      final gen = rc.requests[4];
      expect(gen.url.path, endsWith(':generateContent'));
      final parts =
          ((gen.json['contents'] as List).single as Map)['parts'] as List;
      expect(parts, [
        {'text': 'Attachment 1: lecture.mp4'},
        {
          'fileData': {'mimeType': 'video/mp4', 'fileUri': fileUri},
        },
        {'text': 'Quiz'},
      ]);
      expect(gen.request.body.length, lessThan(10000));

      // A repair retry with the same attachment does not upload again.
      await p.generateJson(
        prompt: 'Quiz again',
        schema: noteDraftJsonSchema,
        attachments: [video],
      );
      expect(rc.requests, hasLength(6));
    });

    test('inline budget is shared: second file is uploaded', () async {
      final a = Uint8List(10 * _mb);
      final b = Uint8List(10 * _mb);
      final rc = RecordingClient([
        (_) => http.Response(
          '',
          200,
          headers: {'x-goog-upload-url': 'https://u/x'},
        ),
        (_) => jsonResponse({
          'file': {'name': 'files/b', 'uri': 'https://f/b'}, // no state = ready
        }),
        (_) => jsonResponse(_geminiOk()),
      ]);
      await provider(rc).generateJson(
        prompt: 'p',
        schema: noteDraftJsonSchema,
        attachments: [
          _pdf(bytes: a),
          _pdf(n: 2, bytes: b),
        ],
      );
      expect(rc.requests, hasLength(3));
      final parts =
          ((rc.requests[2].json['contents'] as List).single as Map)['parts']
              as List;
      expect((parts[1] as Map).containsKey('inlineData'), isTrue);
      expect(parts[3], {
        'fileData': {'mimeType': 'application/pdf', 'fileUri': 'https://f/b'},
      });
    });

    test('upload FAILED state -> provider error', () async {
      final rc = RecordingClient([
        (_) => http.Response(
          '',
          200,
          headers: {'x-goog-upload-url': 'https://u/x'},
        ),
        (_) => jsonResponse({
          'file': {'name': 'files/c', 'uri': 'https://f/c', 'state': 'FAILED'},
        }),
      ]);
      await expectLater(
        provider(rc).generateJson(
          prompt: 'p',
          schema: noteDraftJsonSchema,
          attachments: [
            _video(Uint8List(ProviderLimits.geminiInlineBytes + 1)),
          ],
        ),
        _throwsKind(AiErrorKind.provider, contains('could not process')),
      );
    });

    test('missing upload URL header -> clear error', () async {
      final rc = RecordingClient([(_) => http.Response('', 200)]);
      await expectLater(
        provider(rc).uploadFile(_video(Uint8List(3))),
        _throwsKind(AiErrorKind.provider, contains('did not accept')),
      );
    });

    test('unsupported image type is rejected before sending', () async {
      final rc = RecordingClient([(_) => jsonResponse(_geminiOk())]);
      await expectLater(
        provider(rc).generateJson(
          prompt: 'p',
          schema: noteDraftJsonSchema,
          attachments: [_png(mime: 'image/gif')],
        ),
        _throwsKind(AiErrorKind.unsupported, contains('image/gif')),
      );
      expect(rc.requests, isEmpty);
    });
  });

  group('OpenAI Responses', () {
    OpenAiProvider provider(RecordingClient rc) => OpenAiProvider(
      _config(LlmProviderId.openai, 'gpt-5.4-mini'),
      rc.client,
    );

    test('input_file (PDF) and input_image parts', () async {
      final rc = RecordingClient([(_) => jsonResponse(_openAiOk())]);
      await provider(rc).generateJson(
        prompt: 'Make notes',
        schema: noteDraftJsonSchema,
        systemPrompt: 'sys',
        attachments: [_pdf(), _png()],
      );
      final body = rc.requests.single.json;
      expect(body['instructions'], 'sys');
      expect(body['input'], [
        {
          'role': 'user',
          'content': [
            {'type': 'input_text', 'text': 'Attachment 1: notes.pdf'},
            {
              'type': 'input_file',
              'filename': 'notes.pdf',
              'file_data': 'data:application/pdf;base64,$_pdfB64',
            },
            {'type': 'input_text', 'text': 'Attachment 2: board.png'},
            {
              'type': 'input_image',
              'image_url': 'data:image/png;base64,$_pngB64',
            },
            {'type': 'input_text', 'text': 'Make notes'},
          ],
        },
      ]);
    });

    test('audio/video and YouTube attachments are unsupported', () async {
      final rc = RecordingClient([(_) => jsonResponse(_openAiOk())]);
      await expectLater(
        provider(rc).generateJson(
          prompt: 'p',
          schema: noteDraftJsonSchema,
          attachments: [_video(Uint8List(4))],
        ),
        _throwsKind(AiErrorKind.unsupported, contains('Gemini')),
      );
      await expectLater(
        provider(rc).generateJson(
          prompt: 'p',
          schema: noteDraftJsonSchema,
          attachments: [
            const LlmYoutubeAttachment(label: 'x', url: 'https://youtu.be/x'),
          ],
        ),
        _throwsKind(AiErrorKind.unsupported),
      );
      expect(rc.requests, isEmpty);
    });

    test('size limits: per file and per request', () async {
      final rc = RecordingClient([(_) => jsonResponse(_openAiOk())]);
      await expectLater(
        provider(rc).generateJson(
          prompt: 'p',
          schema: noteDraftJsonSchema,
          attachments: [_pdf(bytes: Uint8List(50 * _mb + 1))],
        ),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.message,
            'message',
            allOf(contains('notes.pdf'), contains('50 MB')),
          ),
        ),
      );
      await expectLater(
        provider(rc).generateJson(
          prompt: 'p',
          schema: noteDraftJsonSchema,
          attachments: [
            _pdf(bytes: Uint8List(30 * _mb)),
            _pdf(n: 2, bytes: Uint8List(30 * _mb)),
          ],
        ),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.message,
            'message',
            contains('total'),
          ),
        ),
      );
      expect(rc.requests, isEmpty);
    });
  });

  group('Anthropic Messages', () {
    AnthropicProvider provider(RecordingClient rc) => AnthropicProvider(
      _config(LlmProviderId.anthropic, 'claude-sonnet-5-5'),
      rc.client,
      isWeb: false,
    );

    test('document (base64 PDF) and image blocks', () async {
      final rc = RecordingClient([(_) => jsonResponse(_anthropicOk())]);
      await provider(rc).generateJson(
        prompt: 'Make notes',
        schema: noteDraftJsonSchema,
        attachments: [_pdf(), _png()],
      );
      final messages = rc.requests.single.json['messages'] as List;
      expect(messages, [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': 'Attachment 1: notes.pdf'},
            {
              'type': 'document',
              'source': {
                'type': 'base64',
                'media_type': 'application/pdf',
                'data': _pdfB64,
              },
              'title': 'notes.pdf',
            },
            {'type': 'text', 'text': 'Attachment 2: board.png'},
            {
              'type': 'image',
              'source': {
                'type': 'base64',
                'media_type': 'image/png',
                'data': _pngB64,
              },
            },
            {'type': 'text', 'text': 'Make notes'},
          ],
        },
      ]);
    });

    test('image over 5 MB and HEIC are rejected', () async {
      final rc = RecordingClient([(_) => jsonResponse(_anthropicOk())]);
      await expectLater(
        provider(rc).generateJson(
          prompt: 'p',
          schema: noteDraftJsonSchema,
          attachments: [_png(bytes: Uint8List(5 * _mb + 1))],
        ),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.message,
            'message',
            contains('5 MB'),
          ),
        ),
      );
      await expectLater(
        provider(rc).generateJson(
          prompt: 'p',
          schema: noteDraftJsonSchema,
          attachments: [_png(mime: 'image/heic')],
        ),
        _throwsKind(AiErrorKind.unsupported, contains('image/heic')),
      );
      expect(rc.requests, isEmpty);
    });
  });

  group('OpenAI-compatible chat', () {
    test('image_url data URL and OpenRouter file part for PDF', () async {
      final rc = RecordingClient([(_) => jsonResponse(_chatOk())]);
      final p = OpenAiCompatibleProvider(
        _config(LlmProviderId.openaiCompatible, 'openai/gpt-5.4-mini'),
        rc.client,
        isWeb: false,
      );
      await p.generateJson(
        prompt: 'Make notes',
        schema: noteDraftJsonSchema,
        systemPrompt: 'sys',
        attachments: [_pdf(), _png()],
      );
      final messages = rc.requests.single.json['messages'] as List;
      expect(messages.first, {'role': 'system', 'content': 'sys'});
      expect(messages[1], {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': 'Attachment 1: notes.pdf'},
          {
            'type': 'file',
            'file': {
              'filename': 'notes.pdf',
              'file_data': 'data:application/pdf;base64,$_pdfB64',
            },
          },
          {'type': 'text', 'text': 'Attachment 2: board.png'},
          {
            'type': 'image_url',
            'image_url': {'url': 'data:image/png;base64,$_pngB64'},
          },
          {'type': 'text', 'text': 'Make notes'},
        ],
      });
    });

    test('attachments survive the json_object fallback', () async {
      final rc = RecordingClient([
        (_) => jsonResponse({
          'error': {'message': 'json_schema not supported'},
        }, 400),
        (_) => jsonResponse(_chatOk()),
      ]);
      final p = OpenAiCompatibleProvider(
        _config(
          LlmProviderId.openaiCompatible,
          'llava',
          baseUrl: 'http://localhost:11434/v1',
        ),
        rc.client,
        isWeb: false,
      );
      await p.generateJson(
        prompt: 'p',
        schema: noteDraftJsonSchema,
        attachments: [_png(n: 1)],
      );
      final user = (rc.requests[1].json['messages'] as List).last as Map;
      expect((user['content'] as List)[1], {
        'type': 'image_url',
        'image_url': {'url': 'data:image/png;base64,$_pngB64'},
      });
    });
  });

  test('formatBytes', () {
    expect(formatBytes(512), '512 B');
    expect(formatBytes(2048), '2 KB');
    expect(formatBytes(5 * _mb), '5 MB');
    expect(formatBytes(15 * _mb + _mb ~/ 2), '15.5 MB');
    expect(formatBytes(2048 * _mb), '2.0 GB');
  });
}
