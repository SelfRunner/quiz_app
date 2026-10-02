import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/ai/ai_source.dart';
import 'package:quiz_app/ai/llm_chat.dart';
import 'package:quiz_app/ai/llm_provider.dart';
import 'package:quiz_app/ai/providers/anthropic_provider.dart';
import 'package:quiz_app/ai/providers/gemini_provider.dart';
import 'package:quiz_app/ai/providers/http_support.dart';
import 'package:quiz_app/ai/providers/openai_compatible_provider.dart';
import 'package:quiz_app/ai/providers/openai_provider.dart';
import 'package:quiz_app/ai/providers/sse.dart';
import 'package:quiz_app/core/errors/app_exception.dart';

import 'stream_helpers.dart';

typedef Collected = ({String text, LlmChatDone done, int deltas});

Future<Collected> collect(Stream<LlmChatEvent> stream) async {
  final text = StringBuffer();
  LlmChatDone? done;
  var deltas = 0;
  await for (final e in stream) {
    expect(done, isNull, reason: 'nothing after LlmChatDone');
    switch (e) {
      case LlmTextDelta(text: final t):
        text.write(t);
        deltas++;
      case LlmChatDone():
        done = e;
    }
  }
  expect(done, isNotNull, reason: 'stream ends with LlmChatDone');
  return (text: text.toString(), done: done!, deltas: deltas);
}

const _messages = [
  LlmChatMessage.user('What is ATP?'),
  LlmChatMessage.assistant('Energy currency [S1].'),
  LlmChatMessage.user('And mitochondria?'),
];

LlmConfig _config(LlmProviderId id, {String? baseUrl}) => LlmConfig(
  providerId: id,
  apiKey: 'sk-test',
  model: 'm-1',
  baseUrl: baseUrl,
);

final _pdf = LlmFileAttachment(
  label: '[S2] file "lecture.pdf"',
  filename: 'lecture.pdf',
  mimeType: 'application/pdf',
  bytes: Uint8List.fromList([1, 2, 3]),
  kind: AiInputKind.pdf,
);

void main() {
  setUp(HttpLlmProvider.resetStreamingSupport);

  group('parseSse', () {
    Future<List<SseEvent>> parse(String body, int size) =>
        parseSse(Stream.fromIterable(byteChunks(body, size))).toList();

    test('events split at every byte boundary, CRLF and UTF-8', () async {
      const body =
          ': keep-alive\r\n'
          'event: delta\r\n'
          'data: {"t":"Grüße 🧬"}\r\n'
          '\r\n'
          'data: line1\n'
          'data:line2\n'
          '\n'
          'id: 7\n'
          'data: [DONE]\n'
          '\n';
      for (final size in [1, 2, 3, 5, 64]) {
        final events = await parse(body, size);
        expect(events, hasLength(3), reason: 'chunk size $size');
        expect(events[0].event, 'delta');
        expect(jsonDecode(events[0].data), {'t': 'Grüße 🧬'});
        expect(events[1].data, 'line1\nline2');
        expect(events[1].event, isNull);
        expect(events[2].data, '[DONE]');
        expect(events[2].id, '7');
      }
    });

    test('last event without trailing blank line is delivered', () async {
      final events = await parse('data: a\n\ndata: b', 4);
      expect(events.map((e) => e.data), ['a', 'b']);
    });

    test('events without data are ignored', () async {
      final events = await parse('event: ping\n\n: c\n\ndata: x\n\n', 3);
      expect(events.map((e) => e.data), ['x']);
    });
  });

  test('normalizeChatMessages merges, drops leading assistant/blank', () {
    final out = normalizeChatMessages(const [
      LlmChatMessage.assistant('Hi! How can I help?'),
      LlmChatMessage.user('a'),
      LlmChatMessage.user('  '),
      LlmChatMessage.user('b'),
      LlmChatMessage.assistant('c'),
      LlmChatMessage.user('d'),
    ]);
    expect(out.map((m) => '${m.role.name}:${m.text}'), [
      'user:a\n\nb',
      'assistant:c',
      'user:d',
    ]);
    expect(
      normalizeChatMessages(const [LlmChatMessage.assistant('x')]),
      isEmpty,
    );
  });

  // ------------------------------------------------------------ Gemini

  group('Gemini streaming', () {
    Map<String, Object?> chunk(String text, {String? finish}) => {
      'candidates': [
        {
          'content': {
            'role': 'model',
            'parts': [
              {'text': text},
            ],
          },
          'finishReason': ?finish,
        },
      ],
    };

    final body =
        sse({
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': 'thinking...', 'thought': true},
                ],
              },
            },
          ],
        }) +
        sse(chunk('Mitochondria ')) +
        sse(chunk('make ATP — Grüße [S1].', finish: 'STOP'));

    for (final size in [1, 4, 13, 1000]) {
      test('chunk size $size: text, done and request shape', () async {
        final sc = StreamingClient([StreamReply.sse(body, chunkSize: size)]);
        final p = GeminiProvider(
          _config(LlmProviderId.gemini),
          sc.client,
          isWeb: false,
        );
        final r = await collect(
          p.streamChat(
            messages: _messages,
            systemPrompt: 'SYS',
            attachments: [_pdf],
          ),
        );
        expect(r.text, 'Mitochondria make ATP — Grüße [S1].');
        expect(r.done.reason, LlmFinishReason.stop);
        expect(r.done.streamed, isTrue);

        final call = sc.calls.single;
        expect(call.url.path, '/v1beta/models/m-1:streamGenerateContent');
        expect(call.url.queryParameters['alt'], 'sse');
        expect(call.headers['x-goog-api-key'], 'sk-test');
        expect(call.abortTrigger, isNotNull);
        final json = call.json;
        expect(json['systemInstruction'], {
          'parts': [
            {'text': 'SYS'},
          ],
        });
        final contents = json['contents'] as List;
        expect(contents.map((c) => (c as Map)['role']), [
          'user',
          'model',
          'user',
        ]);
        final lastParts = (contents.last as Map)['parts'] as List;
        expect(lastParts[0], {'text': '[S2] file "lecture.pdf"'});
        expect((lastParts[1] as Map)['inlineData'], {
          'mimeType': 'application/pdf',
          'data': base64Encode([1, 2, 3]),
        });
        expect(lastParts.last, {'text': 'And mitochondria?'});
      });
    }

    test('MAX_TOKENS -> length', () async {
      final sc = StreamingClient([
        StreamReply.sse(
          sse(chunk('partial')) + sse(chunk('', finish: 'MAX_TOKENS')),
        ),
      ]);
      final p = GeminiProvider(_config(LlmProviderId.gemini), sc.client);
      final r = await collect(p.streamChat(messages: _messages));
      expect(r.text, 'partial');
      expect(r.done.reason, LlmFinishReason.length);
    });

    test('stream cut before finishReason -> NetworkException', () async {
      final sc = StreamingClient([StreamReply.sse(sse(chunk('half')))]);
      final p = GeminiProvider(_config(LlmProviderId.gemini), sc.client);
      final events = <LlmChatEvent>[];
      await expectLater(
        p.streamChat(messages: _messages).forEach(events.add),
        throwsA(isA<NetworkException>()),
      );
      expect(events.single, isA<LlmTextDelta>());
    });

    test('blocked prompt -> AiException', () async {
      final sc = StreamingClient([
        StreamReply.sse(
          sse({
            'promptFeedback': {'blockReason': 'SAFETY'},
          }),
        ),
      ]);
      final p = GeminiProvider(_config(LlmProviderId.gemini), sc.client);
      await expectLater(
        collect(p.streamChat(messages: _messages)),
        throwsA(
          isA<AiException>().having(
            (e) => e.message,
            'message',
            contains('SAFETY'),
          ),
        ),
      );
    });

    test('HTTP 429 -> rateLimited', () async {
      final sc = StreamingClient([
        StreamReply.json({
          'error': {'code': 429, 'message': 'slow down'},
        }, status: 429),
      ]);
      final p = GeminiProvider(_config(LlmProviderId.gemini), sc.client);
      await expectLater(
        collect(p.streamChat(messages: _messages)),
        throwsA(
          isA<AiException>().having(
            (e) => e.kind,
            'kind',
            AiErrorKind.rateLimited,
          ),
        ),
      );
    });

    test('empty conversation -> ValidationException', () async {
      final sc = StreamingClient([StreamReply.sse('')]);
      final p = GeminiProvider(_config(LlmProviderId.gemini), sc.client);
      await expectLater(
        collect(p.streamChat(messages: const [LlmChatMessage.assistant('hi')])),
        throwsA(isA<ValidationException>()),
      );
      expect(sc.calls, isEmpty);
    });
  });

  // ------------------------------------------------------------ OpenAI

  group('OpenAI Responses streaming', () {
    String delta(String t) => sse({
      'type': 'response.output_text.delta',
      'delta': t,
    }, event: 'response.output_text.delta');

    final body =
        sse({
          'type': 'response.created',
          'response': <String, Object?>{},
        }, event: 'response.created') +
        delta('ATP is ') +
        delta('made in mitochondria [S1].') +
        sse({'type': 'response.output_text.done', 'text': '...'}) +
        sse({
          'type': 'response.completed',
          'response': {'status': 'completed'},
        }, event: 'response.completed');

    for (final size in [1, 9, 2048]) {
      test('chunk size $size', () async {
        final sc = StreamingClient([StreamReply.sse(body, chunkSize: size)]);
        final p = OpenAiProvider(_config(LlmProviderId.openai), sc.client);
        final r = await collect(
          p.streamChat(
            messages: _messages,
            systemPrompt: 'SYS',
            attachments: [_pdf],
            maxOutputTokens: 500,
          ),
        );
        expect(r.text, 'ATP is made in mitochondria [S1].');
        expect(r.done.reason, LlmFinishReason.stop);
        final call = sc.calls.single;
        expect(call.url.toString(), 'https://api.openai.com/v1/responses');
        expect(call.headers['authorization'], 'Bearer sk-test');
        expect(call.headers['accept'], 'text/event-stream');
        final json = call.json;
        expect(json['stream'], isTrue);
        expect(json['store'], isFalse);
        expect(json['instructions'], 'SYS');
        expect(json['max_output_tokens'], 500);
        final input = json['input'] as List;
        expect(input[0], {'role': 'user', 'content': 'What is ATP?'});
        expect(input[1], {
          'role': 'assistant',
          'content': 'Energy currency [S1].',
        });
        final last = (input[2] as Map)['content'] as List;
        expect(last.first, {
          'type': 'input_text',
          'text': '[S2] file "lecture.pdf"',
        });
        expect((last[1] as Map)['type'], 'input_file');
        expect(last.last, {'type': 'input_text', 'text': 'And mitochondria?'});
      });
    }

    test('response.incomplete (max_output_tokens) -> length', () async {
      final sc = StreamingClient([
        StreamReply.sse(
          delta('cut') +
              sse({
                'type': 'response.incomplete',
                'response': {
                  'status': 'incomplete',
                  'incomplete_details': {'reason': 'max_output_tokens'},
                },
              }),
        ),
      ]);
      final p = OpenAiProvider(_config(LlmProviderId.openai), sc.client);
      final r = await collect(p.streamChat(messages: _messages));
      expect(r.done.reason, LlmFinishReason.length);
      expect(r.text, 'cut');
    });

    test('refusal only -> refusal finish', () async {
      final sc = StreamingClient([
        StreamReply.sse(
          sse({'type': 'response.refusal.delta', 'delta': 'No.'}) +
              sse({
                'type': 'response.completed',
                'response': <String, Object?>{},
              }),
        ),
      ]);
      final p = OpenAiProvider(_config(LlmProviderId.openai), sc.client);
      final r = await collect(p.streamChat(messages: _messages));
      expect(r.done.reason, LlmFinishReason.refusal);
      expect(r.done.detail, 'No.');
    });

    test('error event -> AiException (rate limit kind)', () async {
      final sc = StreamingClient([
        StreamReply.sse(
          delta('x') +
              sse({
                'type': 'error',
                'code': 'rate_limit_exceeded',
                'message': 'Too many',
              }, event: 'error'),
        ),
      ]);
      final p = OpenAiProvider(_config(LlmProviderId.openai), sc.client);
      await expectLater(
        collect(p.streamChat(messages: _messages)),
        throwsA(
          isA<AiException>().having(
            (e) => e.kind,
            'kind',
            AiErrorKind.rateLimited,
          ),
        ),
      );
    });

    test('response.failed -> AiException with provider message', () async {
      final sc = StreamingClient([
        StreamReply.sse(
          sse({
            'type': 'response.failed',
            'response': {
              'status': 'failed',
              'error': {'code': 'server_error', 'message': 'boom'},
            },
          }),
        ),
      ]);
      final p = OpenAiProvider(_config(LlmProviderId.openai), sc.client);
      await expectLater(
        collect(p.streamChat(messages: _messages)),
        throwsA(
          isA<AiException>().having(
            (e) => e.message,
            'message',
            contains('boom'),
          ),
        ),
      );
    });

    test(
      'streaming rejected (400 mentioning stream) -> non-streaming fallback, '
      'remembered',
      () async {
        final completed = {
          'status': 'completed',
          'output': [
            {
              'type': 'message',
              'content': [
                {'type': 'output_text', 'text': 'Full answer [S1].'},
              ],
            },
          ],
        };
        final sc = StreamingClient([
          StreamReply.json({
            'error': {
              'message':
                  'Your organization must be verified to stream this model.',
            },
          }, status: 400),
          StreamReply.json(completed),
        ]);
        final p = OpenAiProvider(_config(LlmProviderId.openai), sc.client);
        final r = await collect(p.streamChat(messages: _messages));
        expect(r.text, 'Full answer [S1].');
        expect(r.done.streamed, isFalse);
        expect(r.deltas, 1);
        expect(sc.calls, hasLength(2));
        expect(sc.calls[1].json.containsKey('stream'), isFalse);

        // Next call (even from a new instance) goes straight to the
        // non-streaming request.
        final p2 = OpenAiProvider(_config(LlmProviderId.openai), sc.client);
        final again = await collect(p2.streamChat(messages: _messages));
        expect(again.text, 'Full answer [S1].');
        expect(sc.calls, hasLength(3));
        expect(sc.calls[2].json.containsKey('stream'), isFalse);
      },
    );

    test('other 400s are not retried', () async {
      final sc = StreamingClient([
        StreamReply.json({
          'error': {'message': 'Invalid model m-1'},
        }, status: 400),
      ]);
      final p = OpenAiProvider(_config(LlmProviderId.openai), sc.client);
      await expectLater(
        collect(p.streamChat(messages: _messages)),
        throwsA(isA<AiException>()),
      );
      expect(sc.calls, hasLength(1));
    });

    test('server answering JSON instead of SSE is parsed', () async {
      final sc = StreamingClient([
        StreamReply.json({
          'status': 'completed',
          'output': [
            {
              'type': 'message',
              'content': [
                {'type': 'output_text', 'text': 'Plain JSON'},
              ],
            },
          ],
        }),
      ]);
      final p = OpenAiProvider(_config(LlmProviderId.openai), sc.client);
      final r = await collect(p.streamChat(messages: _messages));
      expect(r.text, 'Plain JSON');
      expect(r.done.streamed, isFalse);
    });
  });

  // --------------------------------------------------------- Anthropic

  group('Anthropic streaming', () {
    String ev(String type, Map<String, Object?> data) =>
        sse({'type': type, ...data}, event: type);
    String text(String t) => ev('content_block_delta', {
      'index': 0,
      'delta': {'type': 'text_delta', 'text': t},
    });

    final body =
        ev('message_start', {
          'message': {'id': 'msg_1', 'content': <Object?>[]},
        }) +
        ev('content_block_start', {
          'index': 0,
          'content_block': {'type': 'text', 'text': ''},
        }) +
        ev('ping', {}) +
        text('Hello ') +
        text('Welt 🌍 [S1][S2]') +
        ev('content_block_stop', {'index': 0}) +
        ev('message_delta', {
          'delta': {'stop_reason': 'end_turn'},
          'usage': {'output_tokens': 9},
        }) +
        ev('message_stop', {});

    for (final size in [1, 6, 4096]) {
      test('chunk size $size', () async {
        final sc = StreamingClient([StreamReply.sse(body, chunkSize: size)]);
        final p = AnthropicProvider(
          _config(LlmProviderId.anthropic),
          sc.client,
          isWeb: true,
        );
        final r = await collect(
          p.streamChat(
            messages: _messages,
            systemPrompt: 'SYS',
            attachments: [_pdf],
          ),
        );
        expect(r.text, 'Hello Welt 🌍 [S1][S2]');
        expect(r.done.reason, LlmFinishReason.stop);
        final call = sc.calls.single;
        expect(call.url.toString(), 'https://api.anthropic.com/v1/messages');
        expect(call.headers['anthropic-version'], '2023-06-01');
        expect(
          call.headers['anthropic-dangerous-direct-browser-access'],
          'true',
        );
        final json = call.json;
        expect(json['stream'], isTrue);
        expect(json['system'], 'SYS');
        expect(json['max_tokens'], 16000);
        final msgs = json['messages'] as List;
        expect(msgs.map((m) => (m as Map)['role']), [
          'user',
          'assistant',
          'user',
        ]);
        final last = (msgs.last as Map)['content'] as List;
        expect(last.first, {'type': 'text', 'text': '[S2] file "lecture.pdf"'});
        expect((last[1] as Map)['type'], 'document');
        expect(last.last, {'type': 'text', 'text': 'And mitochondria?'});
      });
    }

    test('max_tokens stop reason -> length', () async {
      final sc = StreamingClient([
        StreamReply.sse(
          text('cut') +
              ev('message_delta', {
                'delta': {'stop_reason': 'max_tokens'},
              }) +
              ev('message_stop', {}),
        ),
      ]);
      final p = AnthropicProvider(_config(LlmProviderId.anthropic), sc.client);
      final r = await collect(p.streamChat(messages: _messages));
      expect(r.done.reason, LlmFinishReason.length);
    });

    test('error event (overloaded) -> AiException', () async {
      final sc = StreamingClient([
        StreamReply.sse(
          text('a') +
              ev('error', {
                'error': {'type': 'overloaded_error', 'message': 'Overloaded'},
              }),
        ),
      ]);
      final p = AnthropicProvider(_config(LlmProviderId.anthropic), sc.client);
      await expectLater(
        collect(p.streamChat(messages: _messages)),
        throwsA(
          isA<AiException>().having(
            (e) => e.message,
            'message',
            contains('overloaded'),
          ),
        ),
      );
    });

    test('connection lost before message_stop -> NetworkException', () async {
      final sc = StreamingClient([StreamReply.sse(text('partial'))]);
      final p = AnthropicProvider(_config(LlmProviderId.anthropic), sc.client);
      await expectLater(
        collect(p.streamChat(messages: _messages)),
        throwsA(isA<NetworkException>()),
      );
    });

    test('401 -> invalidApiKey', () async {
      final sc = StreamingClient([
        StreamReply.json({
          'type': 'error',
          'error': {
            'type': 'authentication_error',
            'message': 'invalid x-api-key',
          },
        }, status: 401),
      ]);
      final p = AnthropicProvider(_config(LlmProviderId.anthropic), sc.client);
      await expectLater(
        collect(p.streamChat(messages: _messages)),
        throwsA(
          isA<AiException>().having(
            (e) => e.kind,
            'kind',
            AiErrorKind.invalidApiKey,
          ),
        ),
      );
    });
  });

  // ------------------------------------------------ OpenAI-compatible

  group('OpenAI-compatible streaming', () {
    String chunk(String? content, {String? finish}) => sse({
      'id': 'gen-1',
      'choices': [
        {
          'index': 0,
          'delta': {'role': 'assistant', 'content': ?content},
          'finish_reason': finish,
        },
      ],
    });

    final body =
        ': OPENROUTER PROCESSING\n\n'
        '${chunk('Ja, ')}${chunk('die Zelle [S1].')}'
        '${chunk(null, finish: 'stop')}'
        'data: [DONE]\n\n';

    for (final crlf in [false, true]) {
      for (final size in [1, 11]) {
        test('chunk size $size${crlf ? ' CRLF' : ''}', () async {
          final sc = StreamingClient([
            StreamReply.sse(
              crlf ? body.replaceAll('\n', '\r\n') : body,
              chunkSize: size,
            ),
          ]);
          final p = OpenAiCompatibleProvider(
            _config(LlmProviderId.openaiCompatible),
            sc.client,
          );
          final r = await collect(
            p.streamChat(
              messages: _messages,
              systemPrompt: 'SYS',
              maxOutputTokens: 300,
            ),
          );
          expect(r.text, 'Ja, die Zelle [S1].');
          expect(r.done.reason, LlmFinishReason.stop);
          final call = sc.calls.single;
          expect(
            call.url.toString(),
            'https://openrouter.ai/api/v1/chat/completions',
          );
          final json = call.json;
          expect(json['stream'], isTrue);
          expect(json['max_tokens'], 300);
          final msgs = json['messages'] as List;
          expect(msgs.first, {'role': 'system', 'content': 'SYS'});
          expect(msgs.map((m) => (m as Map)['role']), [
            'system',
            'user',
            'assistant',
            'user',
          ]);
        });
      }
    }

    test('mid-stream error object -> mapped AiException', () async {
      final sc = StreamingClient([
        StreamReply.sse(
          chunk('a') +
              sse({
                'error': {'code': 502, 'message': 'Upstream error'},
                'choices': [
                  {
                    'delta': {'content': ''},
                    'finish_reason': 'error',
                  },
                ],
              }),
        ),
      ]);
      final p = OpenAiCompatibleProvider(
        _config(LlmProviderId.openaiCompatible),
        sc.client,
      );
      await expectLater(
        collect(p.streamChat(messages: _messages)),
        throwsA(isA<AiException>()),
      );
    });

    test('no [DONE] but finish_reason length -> length', () async {
      final sc = StreamingClient([
        StreamReply.sse(chunk('x') + chunk(null, finish: 'length')),
      ]);
      final p = OpenAiCompatibleProvider(
        _config(LlmProviderId.openaiCompatible),
        sc.client,
      );
      final r = await collect(p.streamChat(messages: _messages));
      expect(r.done.reason, LlmFinishReason.length);
    });

    test('stream unsupported -> non-streaming fallback', () async {
      final sc = StreamingClient([
        StreamReply.json({
          'error': {'message': 'Streaming is not supported for this model'},
        }, status: 422),
        StreamReply.json({
          'choices': [
            {
              'message': {'content': 'Whole answer'},
              'finish_reason': 'stop',
            },
          ],
        }),
      ]);
      final p = OpenAiCompatibleProvider(
        _config(
          LlmProviderId.openaiCompatible,
          baseUrl: 'http://localhost:11434/v1',
        ),
        sc.client,
      );
      final r = await collect(p.streamChat(messages: _messages));
      expect(r.text, 'Whole answer');
      expect(r.done.streamed, isFalse);
      expect(sc.calls[1].json.containsKey('stream'), isFalse);
      expect(p.streamingUnsupported, isTrue);
    });

    test('cancelling the subscription aborts the request', () async {
      final upstream = StreamController<List<int>>();
      final sc = StreamingClient([StreamReply.controlled(upstream)]);
      final p = OpenAiCompatibleProvider(
        _config(LlmProviderId.openaiCompatible),
        sc.client,
      );
      final first = Completer<LlmChatEvent>();
      final sub = p.streamChat(messages: _messages).listen((e) {
        if (!first.isCompleted) first.complete(e);
      }, onError: (Object e) => fail('unexpected error $e'));
      upstream.add(utf8.encode(chunk('Hel')));
      expect(await first.future, isA<LlmTextDelta>());
      expect(upstream.hasListener, isTrue);

      await sub.cancel();
      await sc.calls.single.abortTrigger!.timeout(const Duration(seconds: 1));
      expect(upstream.hasListener, isFalse);
      await upstream.close();
    });
  });
}
