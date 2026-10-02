import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/ai/llm_provider.dart';
import 'package:quiz_app/ai/providers/anthropic_provider.dart';
import 'package:quiz_app/core/errors/app_exception.dart';
import 'package:quiz_app/data/models/models.dart';

import 'test_helpers.dart';

const _key = 'sk-ant-secret';

AnthropicProvider _provider(RecordingClient rc, {bool isWeb = false}) =>
    AnthropicProvider(
      const LlmConfig(
        providerId: LlmProviderId.anthropic,
        apiKey: _key,
        model: 'claude-sonnet-5-5',
      ),
      rc.client,
      isWeb: isWeb,
    );

Map<String, dynamic> _message(
  List<Map<String, dynamic>> content, {
  String stop = 'end_turn',
}) => {
  'id': 'msg_1',
  'type': 'message',
  'role': 'assistant',
  'content': content,
  'stop_reason': stop,
};

void main() {
  test('Messages API request shape with output_config.format', () async {
    final rc = RecordingClient([
      (_) => jsonResponse(
        _message([
          {'type': 'text', 'text': jsonEncode(validQuizJson())},
        ]),
      ),
    ]);
    final out = await _provider(rc).generateJson(
      prompt: 'user',
      schema: quizDraftJsonSchema,
      schemaName: 'QuizDraft',
      systemPrompt: 'sys',
    );
    expect(out['title'], 'Cells');

    final r = rc.requests.single;
    expect(r.url.toString(), 'https://api.anthropic.com/v1/messages');
    expect(r.headers['x-api-key'], _key);
    expect(r.headers['anthropic-version'], '2023-06-01');
    expect(
      r.headers.containsKey('anthropic-dangerous-direct-browser-access'),
      isFalse,
    );
    expect(r.headers.containsKey('authorization'), isFalse);
    final body = r.json;
    expect(body['model'], 'claude-sonnet-5-5');
    expect(body['max_tokens'], isA<int>());
    expect(body['system'], 'sys');
    expect(body['messages'], [
      {'role': 'user', 'content': 'user'},
    ]);
    final format = (body['output_config'] as Map)['format'] as Map;
    expect(format['type'], 'json_schema');
    final schema = format['schema'] as Map;
    expect(schema.containsKey(r'$schema'), isFalse);
    expect(schema['additionalProperties'], false);
    expect(body.containsKey('tools'), isFalse);
  });

  test('web adds the direct-browser-access header', () async {
    final rc = RecordingClient([
      (_) => jsonResponse(
        _message([
          {'type': 'text', 'text': '{"title":"a","content_markdown":"b"}'},
        ]),
      ),
    ]);
    await _provider(
      rc,
      isWeb: true,
    ).generateJson(prompt: 'p', schema: noteDraftJsonSchema);
    expect(
      rc.requests.single.headers['anthropic-dangerous-direct-browser-access'],
      'true',
    );
  });

  test(
    'falls back to forced tool_use when output_config is rejected',
    () async {
      final rc = RecordingClient([
        (_) => jsonResponse({
          'type': 'error',
          'error': {
            'type': 'invalid_request_error',
            'message': 'output_config.format: structured outputs are not supported for this model',
          },
        }, 400),
        (_) => jsonResponse(
          _message([
            {
              'type': 'tool_use',
              'id': 'tu_1',
              'name': 'submit_NoteDraft',
              'input': {'title': 'a', 'content_markdown': 'b'},
            },
          ], stop: 'tool_use'),
        ),
      ]);
      final out = await _provider(rc).generateJson(
        prompt: 'p',
        schema: noteDraftJsonSchema,
        schemaName: 'NoteDraft',
      );
      expect(out, {'title': 'a', 'content_markdown': 'b'});
      final body = rc.requests[1].json;
      expect(body.containsKey('output_config'), isFalse);
      final tool = (body['tools'] as List).single as Map;
      expect(tool['name'], 'submit_NoteDraft');
      expect(tool['input_schema'], isA<Map<String, dynamic>>());
      expect(body['tool_choice'], {'type': 'tool', 'name': 'submit_NoteDraft'});
    },
  );

  test('refusal and max_tokens stop reasons', () async {
    final refusal = RecordingClient([
      (_) => jsonResponse(_message(const [], stop: 'refusal')),
    ]);
    await expectLater(
      _provider(refusal).generateJson(prompt: 'p', schema: noteDraftJsonSchema),
      throwsA(
        isA<AiException>().having((e) => e.kind, 'kind', AiErrorKind.provider),
      ),
    );
    final cut = RecordingClient([
      (_) => jsonResponse(
        _message([
          {'type': 'text', 'text': '{"title":'},
        ], stop: 'max_tokens'),
      ),
    ]);
    await expectLater(
      _provider(cut).generateJson(prompt: 'p', schema: noteDraftJsonSchema),
      throwsA(
        isA<AiException>().having(
          (e) => e.kind,
          'kind',
          AiErrorKind.invalidOutput,
        ),
      ),
    );
  });

  test('error mapping: 401 authentication_error, 529 overloaded', () async {
    final unauthorized = RecordingClient([
      (_) => jsonResponse({
        'type': 'error',
        'error': {
          'type': 'authentication_error',
          'message': 'invalid x-api-key',
        },
      }, 401),
    ]);
    await expectLater(
      _provider(unauthorized).listModels(),
      throwsA(
        isA<AiException>().having(
          (e) => e.kind,
          'kind',
          AiErrorKind.invalidApiKey,
        ),
      ),
    );
    final overloaded = RecordingClient([
      (_) => jsonResponse({
        'type': 'error',
        'error': {'type': 'overloaded_error', 'message': 'Overloaded'},
      }, 529),
    ]);
    await expectLater(
      _provider(overloaded)
          .generateJson(prompt: 'p', schema: noteDraftJsonSchema),
      throwsA(
        isA<AiException>()
            .having((e) => e.kind, 'kind', AiErrorKind.provider)
            .having((e) => e.statusCode, 'status', 529),
      ),
    );
  });

  test('listModels pages with after_id', () async {
    final rc = RecordingClient([
      (_) => jsonResponse({
        'data': [
          {
            'type': 'model',
            'id': 'claude-opus-5-5',
            'display_name': 'Claude Opus 5.5',
          },
        ],
        'has_more': true,
        'first_id': 'claude-opus-5-5',
        'last_id': 'claude-opus-5-5',
      }),
      (_) => jsonResponse({
        'data': [
          {
            'type': 'model',
            'id': 'claude-haiku-4-5-20251001',
            'display_name': 'Claude Haiku 4.5',
          },
        ],
        'has_more': false,
        'last_id': 'claude-haiku-4-5-20251001',
      }),
    ]);
    final models = await _provider(rc).listModels();
    expect(models, ['claude-opus-5-5', 'claude-haiku-4-5-20251001']);
    expect(rc.requests[0].url.path, '/v1/models');
    expect(rc.requests[0].url.queryParameters.containsKey('after_id'), isFalse);
    expect(rc.requests[1].url.queryParameters['after_id'], 'claude-opus-5-5');
    expect(rc.requests[0].headers['anthropic-version'], '2023-06-01');
  });
}
