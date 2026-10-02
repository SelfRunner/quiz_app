import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:quiz_app/ai/llm_provider.dart';
import 'package:quiz_app/ai/providers/openai_compatible_provider.dart';
import 'package:quiz_app/core/errors/app_exception.dart';
import 'package:quiz_app/data/models/models.dart';

import 'test_helpers.dart';

const _key = 'sk-or-secret';

OpenAiCompatibleProvider _provider(
  RecordingClient rc, {
  String? baseUrl,
  bool isWeb = false,
}) => OpenAiCompatibleProvider(
  LlmConfig(
    providerId: LlmProviderId.openaiCompatible,
    apiKey: _key,
    model: 'meta/llama',
    baseUrl: baseUrl,
    extraHeaders: const {
      'HTTP-Referer': 'https://quiz.app',
      'X-Title': 'Quiz App',
    },
  ),
  rc.client,
  isWeb: isWeb,
);

Map<String, dynamic> _chat(Object? content, {String finish = 'stop'}) => {
  'id': 'gen-1',
  'choices': [
    {
      'index': 0,
      'message': {'role': 'assistant', 'content': content},
      'finish_reason': finish,
    },
  ],
};

const _note = '{"title":"a","content_markdown":"b"}';

void main() {
  test('default OpenRouter request with json_schema + extra headers', () async {
    final rc = RecordingClient([(_) => jsonResponse(_chat(_note))]);
    final p = _provider(rc);
    expect(p.displayName, 'OpenRouter');
    final out = await p.generateJson(
      prompt: 'p',
      schema: noteDraftJsonSchema,
      schemaName: 'NoteDraft',
      systemPrompt: 'sys',
    );
    expect(out['title'], 'a');

    final r = rc.requests.single;
    expect(r.url.toString(), 'https://openrouter.ai/api/v1/chat/completions');
    expect(r.headers['authorization'], 'Bearer $_key');
    expect(
      r.headers['HTTP-Referer'] ?? r.headers['http-referer'],
      'https://quiz.app',
    );
    expect(r.headers['X-Title'] ?? r.headers['x-title'], 'Quiz App');
    final body = r.json;
    expect(body['model'], 'meta/llama');
    expect(body['messages'], [
      {'role': 'system', 'content': 'sys'},
      {'role': 'user', 'content': 'p'},
    ]);
    final rf = body['response_format'] as Map;
    expect(rf['type'], 'json_schema');
    expect((rf['json_schema'] as Map)['name'], 'NoteDraft');
    expect((rf['json_schema'] as Map)['strict'], true);
    expect(p.mode, CompatJsonMode.jsonSchema);
  });

  test('falls back json_schema -> json_object -> prompt-only', () async {
    http.Response reject(http.Request _) => jsonResponse({
      'error': {
        'message': "response_format type 'json_schema' is not supported",
      },
    }, 400);
    final rc = RecordingClient([
      reject,
      (_) => jsonResponse({
        'error': {'message': 'json_object response_format unsupported'},
      }, 400),
      (_) => jsonResponse(_chat('Here you go:\n```json\n$_note\n```')),
    ]);
    final p = _provider(rc, baseUrl: 'http://localhost:11434/v1');
    final out = await p.generateJson(prompt: 'p', schema: noteDraftJsonSchema);
    expect(out['content_markdown'], 'b');
    expect(rc.requests, hasLength(3));
    expect(
      rc.requests[0].url.toString(),
      'http://localhost:11434/v1/chat/completions',
    );
    expect(
      (rc.requests[1].json['response_format'] as Map)['type'],
      'json_object',
    );
    expect(rc.requests[2].json.containsKey('response_format'), isFalse);
    final system = (rc.requests[2].json['messages'] as List).first as Map;
    expect(system['content'], contains('JSON Schema'));
    expect(p.mode, CompatJsonMode.prompt);
  });

  test('does not fall back on unrelated 400s or auth errors', () async {
    final rc = RecordingClient([
      (_) => jsonResponse({
        'error': {'message': 'Invalid API key', 'code': 401},
      }, 401),
    ]);
    await expectLater(
      _provider(rc).generateJson(prompt: 'p', schema: noteDraftJsonSchema),
      throwsA(
        isA<AiException>().having(
          (e) => e.kind,
          'kind',
          AiErrorKind.invalidApiKey,
        ),
      ),
    );
    expect(rc.requests, hasLength(1));
  });

  test('content as list of parts, 200-with-error body, 402 credits', () async {
    final parts = RecordingClient([
      (_) => jsonResponse(
        _chat([
          {'type': 'text', 'text': _note},
        ]),
      ),
    ]);
    expect(
      await _provider(parts)
          .generateJson(prompt: 'p', schema: noteDraftJsonSchema),
      {'title': 'a', 'content_markdown': 'b'},
    );

    final upstream = RecordingClient([
      (_) => jsonResponse({
        'error': {'message': 'Rate limited upstream', 'code': 429},
      }),
    ]);
    await expectLater(
      _provider(upstream)
          .generateJson(prompt: 'p', schema: noteDraftJsonSchema),
      throwsA(
        isA<AiException>().having(
          (e) => e.kind,
          'kind',
          AiErrorKind.rateLimited,
        ),
      ),
    );

    final credits = RecordingClient([
      (_) => jsonResponse({
        'error': {'message': 'Insufficient credits', 'code': 402},
      }, 402),
    ]);
    await expectLater(
      _provider(credits).generateJson(prompt: 'p', schema: noteDraftJsonSchema),
      throwsA(
        isA<AiException>()
            .having((e) => e.kind, 'kind', AiErrorKind.rateLimited)
            .having((e) => e.message, 'msg', contains('credits')),
      ),
    );
  });

  test('network failure -> NetworkException with CORS hint on web', () async {
    final rc = RecordingClient([
      (r) => throw http.ClientException('XMLHttpRequest error.', r.url),
    ]);
    await expectLater(
      _provider(
        rc,
        isWeb: true,
      ).generateJson(prompt: 'p', schema: noteDraftJsonSchema),
      throwsA(
        isA<NetworkException>().having(
          (e) => e.message,
          'msg',
          contains('CORS'),
        ),
      ),
    );
  });

  test('listModels and OpenRouter verifyKey', () async {
    final rc = RecordingClient([
      (_) => jsonResponse({
        'data': [
          {'id': 'z/model'},
          {'id': 'a/model'},
        ],
      }),
      (_) => jsonResponse({
        'data': {'label': 'sk-or-...', 'limit': null},
      }),
    ]);
    final p = _provider(rc);
    expect(await p.listModels(), ['a/model', 'z/model']);
    await p.verifyKey();
    expect(
      rc.requests[0].url.toString(),
      'https://openrouter.ai/api/v1/models',
    );
    expect(rc.requests[1].url.toString(), 'https://openrouter.ai/api/v1/key');
    expect(rc.requests[1].headers['authorization'], 'Bearer $_key');
  });
}
