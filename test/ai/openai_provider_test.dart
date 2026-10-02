import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/ai/llm_provider.dart';
import 'package:quiz_app/ai/providers/openai_provider.dart';
import 'package:quiz_app/core/errors/app_exception.dart';
import 'package:quiz_app/data/models/models.dart';

import 'test_helpers.dart';

const _key = 'sk-test-secret';

OpenAiProvider _provider(RecordingClient rc) => OpenAiProvider(
  const LlmConfig(
    providerId: LlmProviderId.openai,
    apiKey: _key,
    model: 'gpt-x',
  ),
  rc.client,
  isWeb: false,
);

Map<String, dynamic> _response(String text) => {
  'id': 'resp_1',
  'object': 'response',
  'status': 'completed',
  'output': [
    {'type': 'reasoning', 'summary': <Object>[]},
    {
      'type': 'message',
      'role': 'assistant',
      'content': [
        {'type': 'output_text', 'text': text, 'annotations': <Object>[]},
      ],
    },
  ],
};

void main() {
  test('Responses API request shape with strict json_schema', () async {
    final rc = RecordingClient([
      (_) => jsonResponse(_response(jsonEncode(validQuizJson()))),
    ]);
    final out = await _provider(rc).generateJson(
      prompt: 'user prompt',
      schema: quizDraftJsonSchema,
      schemaName: 'QuizDraft',
      systemPrompt: 'sys',
    );
    expect(out['questions'], hasLength(2));

    final r = rc.requests.single;
    expect(r.url.toString(), 'https://api.openai.com/v1/responses');
    expect(r.headers['authorization'], 'Bearer $_key');
    expect(r.headers['content-type'], startsWith('application/json'));
    final body = r.json;
    expect(body['model'], 'gpt-x');
    expect(body['instructions'], 'sys');
    expect(body['input'], 'user prompt');
    expect(body['store'], false);
    final format = (body['text'] as Map)['format'] as Map;
    expect(format['type'], 'json_schema');
    expect(format['name'], 'QuizDraft');
    expect(format['strict'], true);
    final schema = format['schema'] as Map;
    expect(schema['additionalProperties'], false);
    expect(schema.containsKey(r'$schema'), isFalse);
  });

  test('refusal is surfaced as a provider error', () async {
    final rc = RecordingClient([
      (_) => jsonResponse({
        'status': 'completed',
        'output': [
          {
            'type': 'message',
            'content': [
              {'type': 'refusal', 'refusal': "I can't help with that."},
            ],
          },
        ],
      }),
    ]);
    await expectLater(
      _provider(rc).generateJson(prompt: 'p', schema: noteDraftJsonSchema),
      throwsA(
        isA<AiException>()
            .having((e) => e.kind, 'kind', AiErrorKind.provider)
            .having((e) => e.message, 'msg', contains('declined')),
      ),
    );
  });

  test('incomplete (max_output_tokens) -> invalidOutput', () async {
    final rc = RecordingClient([
      (_) => jsonResponse({
        ..._response('{"title": "a'),
        'status': 'incomplete',
        'incomplete_details': {'reason': 'max_output_tokens'},
      }),
    ]);
    await expectLater(
      _provider(rc).generateJson(prompt: 'p', schema: noteDraftJsonSchema),
      throwsA(
        isA<AiException>().having(
          (e) => e.kind,
          'kind',
          AiErrorKind.invalidOutput,
        ),
      ),
    );
  });

  test('YouTube URL is unsupported', () async {
    final rc = RecordingClient([(_) => jsonResponse({})]);
    await expectLater(
      _provider(rc).generateJson(
        prompt: 'p',
        schema: noteDraftJsonSchema,
        youtubeUrl: 'https://youtu.be/dQw4w9WgXcQ',
      ),
      throwsA(
        isA<AiException>().having(
          (e) => e.kind,
          'kind',
          AiErrorKind.unsupported,
        ),
      ),
    );
    expect(rc.requests, isEmpty);
  });

  test('error mapping: 401, 429 rate limit, 429 quota, 500', () async {
    Future<AiException> errorFor(int status, Map<String, dynamic> body) async {
      final rc = RecordingClient([(_) => jsonResponse(body, status)]);
      try {
        await _provider(rc)
            .generateJson(prompt: 'p', schema: noteDraftJsonSchema);
      } on AiException catch (e) {
        return e;
      }
      fail('expected AiException');
    }

    final e401 = await errorFor(401, {
      'error': {
        'message': 'Incorrect API key provided: $_key.',
        'type': 'invalid_request_error',
        'code': 'invalid_api_key',
      },
    });
    expect(e401.kind, AiErrorKind.invalidApiKey);
    expect(e401.statusCode, 401);
    expect(e401.message, isNot(contains(_key)));
    expect(e401.cause.toString(), isNot(contains(_key)));

    final e429 = await errorFor(429, {
      'error': {
        'message': 'Rate limit reached for requests',
        'code': 'rate_limit_exceeded',
      },
    });
    expect(e429.kind, AiErrorKind.rateLimited);
    expect(e429.message, contains('rate limit'));

    final quota = await errorFor(429, {
      'error': {
        'message': 'You exceeded your current quota',
        'code': 'insufficient_quota',
      },
    });
    expect(quota.kind, AiErrorKind.rateLimited);
    expect(quota.message, contains('quota'));

    final e500 = await errorFor(500, {
      'error': {'message': 'boom'},
    });
    expect(e500.kind, AiErrorKind.provider);
    expect(e500.message, contains('temporarily unavailable'));
  });

  test('listModels keeps text-generation models only', () async {
    final rc = RecordingClient([
      (_) => jsonResponse({
        'object': 'list',
        'data': [
          {'id': 'gpt-5.5', 'object': 'model'},
          {'id': 'text-embedding-3-small', 'object': 'model'},
          {'id': 'gpt-4o-realtime-preview', 'object': 'model'},
          {'id': 'o4-mini', 'object': 'model'},
          {'id': 'dall-e-3', 'object': 'model'},
          {'id': 'gpt-5.4-mini', 'object': 'model'},
          {'id': 'gpt-4o-mini-tts', 'object': 'model'},
        ],
      }),
    ]);
    final models = await _provider(rc).listModels();
    expect(models, ['gpt-5.4-mini', 'gpt-5.5', 'o4-mini']);
    expect(
      rc.requests.single.url.toString(),
      'https://api.openai.com/v1/models',
    );
    expect(rc.requests.single.headers['authorization'], 'Bearer $_key');
  });
}
