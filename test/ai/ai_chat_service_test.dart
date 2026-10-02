import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/ai/ai_chat_service.dart';
import 'package:quiz_app/ai/chat_context.dart';
import 'package:quiz_app/ai/default_ai_chat_service.dart';
import 'package:quiz_app/ai/llm_provider.dart';
import 'package:quiz_app/ai/llm_resolver.dart';
import 'package:quiz_app/ai/providers/default_llm_provider_factory.dart';
import 'package:quiz_app/ai/secure_api_key_store.dart';
import 'package:quiz_app/ai/transcript_service.dart';
import 'package:quiz_app/core/errors/app_exception.dart';

import 'stream_helpers.dart';

class _Transcripts implements TranscriptService {
  _Transcripts({this.fail = false});
  final bool fail;

  @override
  Future<VideoTranscript> fetchTranscript(String url) async {
    if (fail) {
      throw const TranscriptUnavailableException('This video has no captions.');
    }
    return const VideoTranscript(
      videoId: 'dQw4w9WgXcQ',
      title: 'Cell talk',
      text: 'Ribosomes make proteins.',
      languageCode: 'en',
    );
  }
}

String _openAiBody(List<String> deltas, {String end = 'completed'}) =>
    deltas
        .map((d) => sse({'type': 'response.output_text.delta', 'delta': d}))
        .join() +
    (end == 'completed'
        ? sse({'type': 'response.completed', 'response': <String, Object?>{}})
        : sse({
            'type': 'response.incomplete',
            'response': {
              'incomplete_details': {'reason': end},
            },
          }));

Future<List<ChatDelta>> _collect(Stream<ChatDelta> s) => s.toList();

void main() {
  late SecureApiKeyStore keys;

  setUp(() async {
    keys = SecureApiKeyStore(userId: 'u1', backend: InMemoryKeyValueStore());
    await keys.setApiKey(LlmProviderId.openai, 'sk-openai');
    await keys.setSelectedProvider(LlmProviderId.openai);
  });

  DefaultAiChatService service(
    StreamingClient sc, {
    ChatBudget budget = const ChatBudget(),
    TranscriptService? transcripts,
  }) => DefaultAiChatService(
    resolver: LlmResolver(
      keyStore: keys,
      providerFactory: DefaultLlmProviderFactory(sc.client, isWeb: false),
      isWeb: false,
    ),
    transcriptService: transcripts ?? _Transcripts(),
    budget: budget,
  );

  final pdf = FileSource(
    id: 'att-1',
    name: 'lecture.pdf',
    mimeType: 'application/pdf',
    bytes: Uint8List.fromList([1, 2, 3]),
  );
  final audio = FileSource(
    id: 'att-2',
    name: 'talk.mp3',
    mimeType: 'audio/mpeg',
    bytes: Uint8List.fromList([4]),
  );

  test('streams deltas, numbers sources and parses citations', () async {
    final sc = StreamingClient([
      StreamReply.sse(
        _openAiBody([
          'Mitochondria make ATP [S',
          '1]. The slides agree [S2][S3]',
          ' and [S7].',
        ]),
        chunkSize: 5,
      ),
    ]);
    final events = await _collect(
      service(sc).send(
        history: const [
          ChatTurn.user('What is ATP?'),
          ChatTurn.assistant('Energy currency [S1].'),
        ],
        userMessage: 'Where is it made?',
        context: [
          const NoteSource(id: 'note-1', title: 'Cells', markdown: '# Cells'),
          pdf,
          audio,
        ],
      ),
    );

    final started = events.first as ChatStarted;
    expect(started.selection.providerId, LlmProviderId.openai);
    expect(started.sources.map((s) => (s.marker, s.type, s.id, s.status)), [
      ('S1', AiSourceType.note, 'note-1', ChatSourceStatus.full),
      ('S2', AiSourceType.file, 'att-1', ChatSourceStatus.full),
      ('S3', AiSourceType.file, 'att-2', ChatSourceStatus.unreadable),
    ]);
    expect(started.sources[2].note, contains("can't read audio"));

    final text = events.whereType<ChatTextDelta>().map((d) => d.text).join();
    expect(
      text,
      'Mitochondria make ATP [S1]. The slides agree [S2][S3] and [S7].',
    );
    final result = (events.last as ChatCompleted).result;
    expect(result.text, text);
    expect(result.truncated, isFalse);
    expect(result.streamed, isTrue);
    expect(result.citations, const [
      ChatCitation(
        number: 1,
        type: AiSourceType.note,
        id: 'note-1',
        title: 'Cells',
      ),
      ChatCitation(
        number: 2,
        type: AiSourceType.file,
        id: 'att-1',
        title: 'lecture.pdf',
      ),
    ], reason: 'S3 is unreadable and S7 does not exist');

    final json = sc.calls.single.json;
    expect(json['instructions'], contains('[S1]'));
    final input = json['input'] as List;
    expect(input, hasLength(3));
    expect(input[0], {'role': 'user', 'content': 'What is ATP?'});
    final last = (input[2] as Map)['content'] as List;
    expect(last[0], {'type': 'input_text', 'text': '[S2] file "lecture.pdf"'});
    expect((last[1] as Map)['type'], 'input_file');
    final prompt = (last.last as Map)['text'] as String;
    expect(prompt, contains('[S1] note "Cells"\n<source id="S1">\n# Cells'));
    expect(prompt, contains('[S2] file "lecture.pdf": attached'));
    expect(prompt, contains('[S3] file "talk.mp3": unavailable'));
    expect(prompt, endsWith('My question:\nWhere is it made?'));
  });

  test('budget: later sources excerpted or omitted (not citable)', () async {
    final sc = StreamingClient([
      StreamReply.sse(_openAiBody(['A [S1] B [S2] C [S3]'])),
    ]);
    final events = await _collect(
      service(
        sc,
        budget: const ChatBudget(maxContextChars: 1500, minExcerptChars: 1000),
      ).send(
        history: const [],
        userMessage: 'Summarize',
        context: [
          NoteSource(id: 'a', title: 'A', markdown: 'a' * 2500),
          TextSource(
            id: 'b',
            label: 'B',
            text: 'b' * 2500,
            type: AiSourceType.file,
          ),
          const TextSource(text: 'short'),
        ],
      ),
    );
    final started = events.first as ChatStarted;
    expect(started.sources.map((s) => s.status), [
      ChatSourceStatus.excerpt,
      ChatSourceStatus.omitted,
      ChatSourceStatus.full,
    ]);
    expect(started.sources[1].type, AiSourceType.file);
    final result = (events.last as ChatCompleted).result;
    expect(result.citations.map((c) => c.id), ['a', null]);
    final input = sc.calls.single.json['input'] as List;
    final prompt = (input.last as Map)['content'] as String;
    expect(prompt, contains('characters omitted to fit the context'));
    expect(prompt, contains('[S2] file "B": omitted'));
    expect(prompt, isNot(contains('b' * 100)));
  });

  test('history over budget: oldest turns dropped', () async {
    final sc = StreamingClient([
      StreamReply.sse(_openAiBody(['ok'])),
    ]);
    final events = await _collect(
      service(sc, budget: const ChatBudget(maxHistoryChars: 12)).send(
        history: const [
          ChatTurn.user('first q'),
          ChatTurn.assistant('first a'),
          ChatTurn.user('second'),
        ],
        userMessage: 'third',
        context: const [],
      ),
    );
    final result = (events.last as ChatCompleted).result;
    expect(result.droppedHistoryTurns, 2);
    final input = sc.calls.single.json['input'] as List;
    // "second" and "third" merge into one user message (no assistant
    // between them after trimming).
    expect(input.single, {'role': 'user', 'content': 'second\n\nthird'});
    expect(sc.calls.single.json['instructions'], isNot(contains('[S1]')));
  });

  test('max_output_tokens -> truncated result', () async {
    final sc = StreamingClient([
      StreamReply.sse(_openAiBody(['Long answer'], end: 'max_output_tokens')),
    ]);
    final events = await _collect(
      service(sc).send(history: const [], userMessage: 'q', context: const []),
    );
    expect((events.last as ChatCompleted).result.truncated, isTrue);
  });

  test('refusal with no text -> AiException', () async {
    final sc = StreamingClient([
      StreamReply.sse(
        sse({'type': 'response.refusal.delta', 'delta': 'I cannot help.'}) +
            sse({
              'type': 'response.completed',
              'response': <String, Object?>{},
            }),
      ),
    ]);
    await expectLater(
      _collect(
        service(sc)
            .send(history: const [], userMessage: 'q', context: const []),
      ),
      throwsA(
        isA<AiException>().having(
          (e) => e.message,
          'message',
          contains('declined'),
        ),
      ),
    );
  });

  test('empty message -> ValidationException, nothing sent', () async {
    final sc = StreamingClient([StreamReply.sse('')]);
    await expectLater(
      _collect(
        service(sc)
            .send(history: const [], userMessage: '  ', context: const []),
      ),
      throwsA(isA<ValidationException>()),
    );
    expect(sc.calls, isEmpty);
  });

  test('no key -> missingApiKey', () async {
    await keys.deleteApiKey(LlmProviderId.openai);
    final sc = StreamingClient([StreamReply.sse('')]);
    await expectLater(
      _collect(
        service(sc)
            .send(history: const [], userMessage: 'q', context: const []),
      ),
      throwsA(
        isA<AiException>().having(
          (e) => e.kind,
          'kind',
          AiErrorKind.missingApiKey,
        ),
      ),
    );
  });

  test('YouTube: transcript for OpenAI, failure becomes unreadable', () async {
    final sc = StreamingClient([
      StreamReply.sse(_openAiBody(['ok [S1]'])),
    ]);
    final events = await _collect(
      service(sc).send(
        history: const [],
        userMessage: 'q',
        context: const [
          YoutubeSource('https://youtu.be/dQw4w9WgXcQ', id: 'yt'),
          YoutubeSource('https://youtu.be/aaaaaaaaaaa'),
        ],
      ),
    );
    final started = events.first as ChatStarted;
    expect(started.sources[0].title, 'Cell talk');
    expect(started.sources[0].status, ChatSourceStatus.full);
    final prompt =
        ((sc.calls.single.json['input'] as List).last as Map)['content']
            as String;
    expect(prompt, contains('Ribosomes make proteins.'));

    final sc2 = StreamingClient([
      StreamReply.sse(_openAiBody(['ok'])),
    ]);
    final events2 = await _collect(
      service(sc2, transcripts: _Transcripts(fail: true)).send(
        history: const [],
        userMessage: 'q',
        context: const [YoutubeSource('https://youtu.be/dQw4w9WgXcQ')],
      ),
    );
    final ref = (events2.first as ChatStarted).sources.single;
    expect(ref.status, ChatSourceStatus.unreadable);
    expect(ref.note, contains('no captions'));
  });

  test('Gemini gets YouTube natively as a labelled fileData part', () async {
    await keys.setApiKey(LlmProviderId.gemini, 'g-key');
    await keys.setSelectedProvider(LlmProviderId.gemini);
    final sc = StreamingClient([
      StreamReply.sse(
        sse({
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': 'Video says hi [S1].'},
                ],
              },
              'finishReason': 'STOP',
            },
          ],
        }),
      ),
    ]);
    final events = await _collect(
      service(sc).send(
        history: const [],
        userMessage: 'q',
        context: const [
          YoutubeSource('https://www.youtube.com/watch?v=dQw4w9WgXcQ', id: 'v'),
        ],
      ),
    );
    final result = (events.last as ChatCompleted).result;
    expect(result.citations.single.type, AiSourceType.youtube);
    expect(result.citations.single.id, 'v');
    final contents = sc.calls.single.json['contents'] as List;
    final parts = (contents.single as Map)['parts'] as List;
    expect(parts[0], {'text': '[S1] youtube "YouTube video"'});
    expect((parts[1] as Map)['fileData'], {
      'fileUri': 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
    });
  });

  test('cancelling aborts the HTTP request', () async {
    final upstream = StreamController<List<int>>();
    final sc = StreamingClient([StreamReply.controlled(upstream)]);
    final gotText = Completer<void>();
    final sub = service(sc)
        .send(history: const [], userMessage: 'q', context: const [])
        .listen((e) {
          if (e is ChatTextDelta && !gotText.isCompleted) gotText.complete();
        });
    // Wait for the request to be sent.
    while (sc.calls.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    upstream.add(
      utf8.encode(sse({'type': 'response.output_text.delta', 'delta': 'Hi'})),
    );
    await gotText.future;
    await sub.cancel();
    await sc.calls.single.abortTrigger!.timeout(const Duration(seconds: 1));
    expect(upstream.hasListener, isFalse);
    await upstream.close();
  });
}
