import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/ai/llm_provider.dart';
import 'package:quiz_app/ai/providers/gemini_provider.dart';
import 'package:quiz_app/ai/providers/http_support.dart';
import 'package:quiz_app/core/errors/app_exception.dart';
import 'package:quiz_app/data/models/models.dart';

import 'test_helpers.dart';

const _key = 'gem-secret-key';

GeminiProvider _provider(
  RecordingClient rc, {
  String model = 'gemini-flash-latest',
}) => GeminiProvider(
  LlmConfig(providerId: LlmProviderId.gemini, apiKey: _key, model: model),
  rc.client,
  isWeb: false,
);

Map<String, dynamic> _candidate(String text, {String finish = 'STOP'}) => {
  'candidates': [
    {
      'content': {
        'role': 'model',
        'parts': [
          {'text': 'thinking...', 'thought': true},
          {'text': text},
        ],
      },
      'finishReason': finish,
    },
  ],
};

void main() {
  test('generateContent request shape with YouTube fileData part', () async {
    final rc = RecordingClient([
      (_) => jsonResponse(_candidate(jsonEncode(validQuizJson()))),
    ]);
    final out = await _provider(rc, model: 'models/gemini-x').generateJson(
      prompt: 'Make a quiz',
      schema: quizDraftJsonSchema,
      schemaName: 'QuizDraft',
      systemPrompt: 'You are a teacher',
      youtubeUrl: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
    );
    expect(out['title'], 'Cells');

    final r = rc.requests.single;
    expect(r.method, 'POST');
    expect(
      r.url.toString(),
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-x:generateContent',
    );
    expect(r.headers['x-goog-api-key'], _key);
    expect(r.url.queryParameters.containsKey('key'), isFalse);

    final body = r.json;
    expect(body['systemInstruction'], {
      'parts': [
        {'text': 'You are a teacher'},
      ],
    });
    final parts = ((body['contents'] as List).single as Map)['parts'] as List;
    expect(parts.first, {
      'fileData': {'fileUri': 'https://www.youtube.com/watch?v=dQw4w9WgXcQ'},
    });
    expect(parts.last, {'text': 'Make a quiz'});

    final format =
        ((body['generationConfig'] as Map)['responseFormat'] as Map)['text']
            as Map;
    expect(format['mimeType'], 'APPLICATION_JSON');
    final schema = format['schema'] as Map;
    expect(schema.containsKey(r'$schema'), isFalse);
    expect(schema['properties'], contains('questions'));
  });

  test('no YouTube part when no URL', () async {
    final rc = RecordingClient([
      (_) => jsonResponse(_candidate('{"title":"x","content_markdown":"y"}')),
    ]);
    await _provider(rc).generateJson(prompt: 'p', schema: noteDraftJsonSchema);
    final parts =
        ((rc.requests.single.json['contents'] as List).single as Map)['parts']
            as List;
    expect(parts, [
      {'text': 'p'},
    ]);
    expect(rc.requests.single.json.containsKey('systemInstruction'), isFalse);
  });

  test('falls back to legacy responseJsonSchema when responseFormat rejected', () async {
    final rc = RecordingClient([
      (_) => jsonResponse({
        'error': {
          'code': 400,
          'message':
              'Invalid JSON payload received. Unknown name "responseFormat" at '
              "'generation_config': Cannot find field.",
          'status': 'INVALID_ARGUMENT',
        },
      }, 400),
      (_) => jsonResponse(_candidate('{"title":"x","content_markdown":"y"}')),
    ]);
    final p = _provider(rc);
    await p.generateJson(prompt: 'p', schema: noteDraftJsonSchema);
    expect(rc.requests, hasLength(2));
    final config = rc.requests[1].json['generationConfig'] as Map;
    expect(config['responseMimeType'], 'application/json');
    expect(config['responseJsonSchema'], isA<Map<String, dynamic>>());
    expect(config.containsKey('responseFormat'), isFalse);

    // remembered for the next call
    await p.generateJson(prompt: 'p', schema: noteDraftJsonSchema);
    expect(rc.requests, hasLength(3));
    expect(
      (rc.requests[2].json['generationConfig'] as Map),
      contains('responseJsonSchema'),
    );
  });

  test('ignores thought parts and parses fenced JSON', () async {
    final rc = RecordingClient([
      (_) => jsonResponse(
        _candidate('```json\n{"title":"a","content_markdown":"b"}\n```'),
      ),
    ]);
    final out = await _provider(rc)
        .generateJson(prompt: 'p', schema: noteDraftJsonSchema);
    expect(out, {'title': 'a', 'content_markdown': 'b'});
  });

  test('non-JSON output -> invalidOutput with raw text', () async {
    final rc = RecordingClient([(_) => jsonResponse(_candidate('sorry, no'))]);
    await expectLater(
      _provider(rc).generateJson(prompt: 'p', schema: noteDraftJsonSchema),
      throwsA(
        isA<AiException>()
            .having((e) => e.kind, 'kind', AiErrorKind.invalidOutput)
            .having(
              (e) => (e.cause! as RawModelOutput).text,
              'raw',
              'sorry, no',
            ),
      ),
    );
  });

  test('MAX_TOKENS -> truncated invalidOutput', () async {
    final rc = RecordingClient([
      (_) => jsonResponse(_candidate('{"title":', finish: 'MAX_TOKENS')),
    ]);
    await expectLater(
      _provider(rc).generateJson(prompt: 'p', schema: noteDraftJsonSchema),
      throwsA(
        isA<AiException>()
            .having((e) => e.kind, 'kind', AiErrorKind.invalidOutput)
            .having(
              (e) => (e.cause! as RawModelOutput).truncated,
              'truncated',
              true,
            ),
      ),
    );
  });

  test('blocked prompt -> provider error', () async {
    final rc = RecordingClient([
      (_) => jsonResponse({
        'promptFeedback': {'blockReason': 'SAFETY'},
      }),
    ]);
    await expectLater(
      _provider(rc).generateJson(prompt: 'p', schema: noteDraftJsonSchema),
      throwsA(
        isA<AiException>().having((e) => e.message, 'm', contains('SAFETY')),
      ),
    );
  });

  test(
    'invalid key (400 API_KEY_INVALID) -> invalidApiKey, key not leaked',
    () async {
      final rc = RecordingClient([
        (_) => jsonResponse({
          'error': {
            'code': 400,
            'message':
                'API key not valid. Please pass a valid API key. ($_key)',
            'status': 'INVALID_ARGUMENT',
            'details': [
              {'reason': 'API_KEY_INVALID'},
            ],
          },
        }, 400),
      ]);
      await expectLater(
        _provider(rc).generateJson(prompt: 'p', schema: noteDraftJsonSchema),
        throwsA(
          isA<AiException>()
              .having((e) => e.kind, 'kind', AiErrorKind.invalidApiKey)
              .having((e) => e.message, 'message', isNot(contains(_key)))
              .having(
                (e) => e.cause.toString(),
                'cause',
                isNot(contains(_key)),
              ),
        ),
      );
      expect(rc.requests, hasLength(1)); // no legacy fallback for key errors
    },
  );

  test('listModels filters to generateContent and follows pages', () async {
    final rc = RecordingClient([
      (_) => jsonResponse({
        'models': [
          {
            'name': 'models/gemini-flash-latest',
            'supportedGenerationMethods': ['generateContent', 'countTokens'],
          },
          {
            'name': 'models/text-embedding-004',
            'supportedGenerationMethods': ['embedContent'],
          },
        ],
        'nextPageToken': 'p2',
      }),
      (_) => jsonResponse({
        'models': [
          {
            'name': 'models/gemini-pro-latest',
            'supportedGenerationMethods': ['generateContent'],
          },
        ],
      }),
    ]);
    final models = await _provider(rc).listModels();
    expect(models, ['gemini-flash-latest', 'gemini-pro-latest']);
    expect(rc.requests[0].url.path, '/v1beta/models');
    expect(rc.requests[0].headers['x-goog-api-key'], _key);
    expect(rc.requests[1].url.queryParameters['pageToken'], 'p2');
  });
}
