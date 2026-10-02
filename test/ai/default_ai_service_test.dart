import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/ai/ai_providers.dart';
import 'package:quiz_app/ai/ai_service.dart';
import 'package:quiz_app/ai/default_ai_service.dart';
import 'package:quiz_app/ai/llm_provider.dart';
import 'package:quiz_app/ai/providers/default_llm_provider_factory.dart';
import 'package:quiz_app/ai/secure_api_key_store.dart';
import 'package:quiz_app/ai/transcript_service.dart';
import 'package:quiz_app/core/errors/app_exception.dart';
import 'package:quiz_app/data/models/models.dart';

import 'test_helpers.dart';

class FakeTranscriptService implements TranscriptService {
  final calls = <String>[];

  @override
  Future<VideoTranscript> fetchTranscript(String url) async {
    calls.add(url);
    return const VideoTranscript(
      videoId: 'dQw4w9WgXcQ',
      title: 'Cell biology 101',
      text: 'The mitochondria is the powerhouse of the cell.',
      languageCode: 'en',
    );
  }
}

Map<String, dynamic> _openAiText(Object json) => {
  'status': 'completed',
  'output': [
    {
      'type': 'message',
      'content': [
        {
          'type': 'output_text',
          'text': json is String ? json : jsonEncode(json),
        },
      ],
    },
  ],
};

Map<String, dynamic> _geminiText(Object json) => {
  'candidates': [
    {
      'content': {
        'parts': [
          {'text': jsonEncode(json)},
        ],
      },
      'finishReason': 'STOP',
    },
  ],
};

void main() {
  late SecureApiKeyStore keys;
  late FakeTranscriptService transcripts;

  setUp(() {
    keys = SecureApiKeyStore(userId: 'u1', backend: InMemoryKeyValueStore());
    transcripts = FakeTranscriptService();
  });

  DefaultAiService service(RecordingClient rc) => DefaultAiService(
    keyStore: keys,
    providerFactory: DefaultLlmProviderFactory(rc.client, isWeb: false),
    transcriptService: transcripts,
  );

  group('selection', () {
    test('no key anywhere -> missingApiKey', () async {
      final rc = RecordingClient([(_) => jsonResponse({})]);
      await expectLater(
        service(rc).generateQuiz(const QuizGenerationRequest(contextText: 'x')),
        throwsA(
          isA<AiException>().having(
            (e) => e.kind,
            'kind',
            AiErrorKind.missingApiKey,
          ),
        ),
      );
      expect(rc.requests, isEmpty);
    });

    test('selected provider without key -> missingApiKey', () async {
      await keys.setApiKey(LlmProviderId.openai, 'sk');
      await keys.setSelectedProvider(LlmProviderId.anthropic);
      final rc = RecordingClient([(_) => jsonResponse({})]);
      await expectLater(
        service(rc).generateNote(const NoteGenerationRequest(contextText: 'x')),
        throwsA(
          isA<AiException>()
              .having((e) => e.kind, 'kind', AiErrorKind.missingApiKey)
              .having((e) => e.message, 'msg', contains('Anthropic')),
        ),
      );
    });

    test('resolveSelection: override > stored > first configured', () async {
      final s = service(RecordingClient([(_) => jsonResponse({})]));
      await keys.setApiKey(LlmProviderId.anthropic, 'k');
      expect(
        await s.resolveSelection(),
        const AiSelection(
          providerId: LlmProviderId.anthropic,
          model: 'claude-sonnet-5-5',
        ),
      );
      await keys.setSelectedProvider(LlmProviderId.openai);
      await keys.setSelectedModel(LlmProviderId.openai, 'gpt-custom');
      expect(
        await s.resolveSelection(),
        const AiSelection(
          providerId: LlmProviderId.openai,
          model: 'gpt-custom',
        ),
      );
      expect(
        (await s.resolveSelection(
          providerId: LlmProviderId.gemini,
          model: 'gemini-x',
        )).model,
        'gemini-x',
      );
    });
  });

  group('input validation', () {
    setUp(() => keys.setApiKey(LlmProviderId.openai, 'sk'));

    test('no context and no URL', () async {
      final rc = RecordingClient([(_) => jsonResponse({})]);
      await expectLater(
        service(rc)
            .generateQuiz(const QuizGenerationRequest(contextText: '  ')),
        throwsA(isA<ValidationException>()),
      );
    });

    test('bad YouTube URL', () async {
      final rc = RecordingClient([(_) => jsonResponse({})]);
      await expectLater(
        service(rc).generateQuiz(
          const QuizGenerationRequest(youtubeUrl: 'https://vimeo.com/1'),
        ),
        throwsA(isA<ValidationException>()),
      );
    });

    test('question count out of range', () async {
      final rc = RecordingClient([(_) => jsonResponse({})]);
      await expectLater(
        service(rc).generateQuiz(
          const QuizGenerationRequest(contextText: 'x', questionCount: 0),
        ),
        throwsA(isA<ValidationException>()),
      );
    });
  });

  group('YouTube routing', () {
    test('Gemini receives the video natively, no transcript fetch', () async {
      await keys.setApiKey(LlmProviderId.gemini, 'g');
      await keys.setSelectedProvider(LlmProviderId.gemini);
      final rc = RecordingClient([
        (_) => jsonResponse(_geminiText(validQuizJson(n: 3))),
      ]);
      final draft = await service(rc).generateQuiz(
        const QuizGenerationRequest(
          youtubeUrl: 'https://youtu.be/dQw4w9WgXcQ?si=abc',
          questionCount: 3,
        ),
      );
      expect(draft.questions, hasLength(3));
      expect(transcripts.calls, isEmpty);
      final parts =
          ((rc.requests.single.json['contents'] as List).single as Map)['parts']
              as List;
      expect(parts.first, {'text': 'Attachment 1: YouTube video'});
      expect(parts[1], {
        'fileData': {'fileUri': 'https://www.youtube.com/watch?v=dQw4w9WgXcQ'},
      });
      expect((parts.last as Map)['text'], contains('attached YouTube video'));
    });

    test('OpenAI gets the transcript in the prompt', () async {
      await keys.setApiKey(LlmProviderId.openai, 'sk');
      final rc = RecordingClient([
        (_) => jsonResponse(_openAiText(validQuizJson(n: 2))),
      ]);
      await service(rc).generateQuiz(
        const QuizGenerationRequest(
          youtubeUrl: 'https://www.youtube.com/shorts/dQw4w9WgXcQ',
          contextText: 'Extra notes',
          questionCount: 2,
          topic: 'Biology',
          difficulty: Difficulty.hard,
          language: 'German',
          questionTypes: {QuestionType.mcqSingle},
        ),
      );
      expect(transcripts.calls, [
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      ]);
      final body = rc.requests.single.json;
      final input = body['input'] as String;
      expect(input, contains('powerhouse of the cell'));
      expect(input, contains('Cell biology 101'));
      expect(input, contains('Extra notes'));
      expect(input, contains('exactly 2 questions'));
      expect(input, contains('Biology'));
      expect(input, contains('German'));
      expect(input, contains('mcq_single'));
      expect(input, isNot(contains('short_answer:')));
      expect(body['instructions'], contains('JSON'));
    });
  });

  group('repair retry', () {
    setUp(() => keys.setApiKey(LlmProviderId.openai, 'sk'));

    test('validation errors are sent back once, then succeeds', () async {
      final bad = validQuizJson(n: 2);
      ((bad['questions'] as List).first as Map)['correct_indices'] = [0, 1];
      final rc = RecordingClient([
        (_) => jsonResponse(_openAiText(bad)),
        (_) => jsonResponse(_openAiText(validQuizJson(n: 2))),
      ]);
      final draft = await service(rc).generateQuiz(
        const QuizGenerationRequest(contextText: 'cells', questionCount: 2),
      );
      expect(draft.questions, hasLength(2));
      expect(rc.requests, hasLength(2));
      final repair = rc.requests[1].json['input'] as String;
      expect(repair, contains('Previous answer'));
      expect(repair, contains('questions[0]'));
      expect(repair, contains('exactly 1'));
      expect(repair, contains('cells')); // original prompt kept
    });

    test('non-JSON output triggers a repair', () async {
      final rc = RecordingClient([
        (_) => jsonResponse(_openAiText('Sure! Here are your notes.')),
        (_) => jsonResponse(
          _openAiText({'title': 'Cells', 'content_markdown': '## A\n- b'}),
        ),
      ]);
      final note = await service(rc)
          .generateNote(const NoteGenerationRequest(contextText: 'cells'));
      expect(note.title, 'Cells');
      expect(
        rc.requests[1].json['input'],
        contains('Sure! Here are your notes.'),
      );
    });

    test('second attempt with some valid questions is accepted', () async {
      final bad = validQuizJson(n: 3);
      ((bad['questions'] as List).first as Map)['options'] = ['only one'];
      final rc = RecordingClient([(_) => jsonResponse(_openAiText(bad))]);
      final draft = await service(rc).generateQuiz(
        const QuizGenerationRequest(contextText: 'cells', questionCount: 3),
      );
      expect(rc.requests, hasLength(2));
      expect(draft.questions, hasLength(2));
    });

    test('two unusable answers -> invalidOutput, only one retry', () async {
      final rc = RecordingClient([(_) => jsonResponse(_openAiText('nope'))]);
      await expectLater(
        service(rc).generateQuiz(const QuizGenerationRequest(contextText: 'x')),
        throwsA(
          isA<AiException>()
              .having((e) => e.kind, 'kind', AiErrorKind.invalidOutput)
              .having((e) => e.message, 'msg', contains('twice')),
        ),
      );
      expect(rc.requests, hasLength(2));
    });

    test('truncated output is not retried', () async {
      final rc = RecordingClient([
        (_) => jsonResponse({
          ..._openAiText('{"title": "x'),
          'status': 'incomplete',
          'incomplete_details': {'reason': 'max_output_tokens'},
        }),
      ]);
      await expectLater(
        service(rc).generateQuiz(const QuizGenerationRequest(contextText: 'x')),
        throwsA(
          isA<AiException>().having(
            (e) => e.message,
            'msg',
            contains('output space'),
          ),
        ),
      );
      expect(rc.requests, hasLength(1));
    });

    test('provider errors are not retried', () async {
      final rc = RecordingClient([
        (_) => jsonResponse({
          'error': {'message': 'bad key'},
        }, 401),
      ]);
      await expectLater(
        service(rc).generateQuiz(const QuizGenerationRequest(contextText: 'x')),
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
  });

  group('settings helpers', () {
    test('listModels with an unsaved key', () async {
      final rc = RecordingClient([
        (_) => jsonResponse({
          'data': [
            {'id': 'gpt-5.5'},
          ],
        }),
      ]);
      final models = await service(rc)
          .listModels(LlmProviderId.openai, apiKey: 'sk-new');
      expect(models, ['gpt-5.5']);
      expect(rc.requests.single.headers['authorization'], 'Bearer sk-new');
    });

    test('listModels without any key -> missingApiKey', () async {
      final rc = RecordingClient([(_) => jsonResponse({})]);
      await expectLater(
        service(rc).listModels(LlmProviderId.anthropic),
        throwsA(
          isA<AiException>().having(
            (e) => e.kind,
            'kind',
            AiErrorKind.missingApiKey,
          ),
        ),
      );
    });

    test(
      'testConnection uses stored base URL / headers; OpenRouter /key',
      () async {
        await keys.setApiKey(LlmProviderId.openaiCompatible, 'sk-or');
        await keys.setExtraHeaders(LlmProviderId.openaiCompatible, {
          'X-Title': 'Quiz',
        });
        final rc = RecordingClient([
          (_) => jsonResponse({
            'data': {'label': 'x'},
          }),
        ]);
        await service(rc).testConnection(LlmProviderId.openaiCompatible);
        final r = rc.requests.single;
        expect(r.url.toString(), 'https://openrouter.ai/api/v1/key');
        expect(r.headers['X-Title'], 'Quiz');
      },
    );

    test('never sends a key to an http:// remote base URL', () async {
      final rc = RecordingClient([
        (_) => jsonResponse({'data': <Object>[]}),
      ]);
      await expectLater(
        service(rc).testConnection(
          LlmProviderId.openaiCompatible,
          apiKey: 'sk-or',
          baseUrl: 'http://api.example.com/v1',
        ),
        throwsA(isA<ValidationException>()),
      );
      expect(rc.requests, isEmpty);

      await service(rc).listModels(
        LlmProviderId.openaiCompatible,
        baseUrl: 'http://localhost:11434/v1',
      );
      expect(
        rc.requests.single.url.toString(),
        'http://localhost:11434/v1/models',
      );
    });

    test('testConnection surfaces invalid keys', () async {
      final rc = RecordingClient([
        (_) => jsonResponse({
          'error': {
            'code': 403,
            'message': 'denied',
            'status': 'PERMISSION_DENIED',
          },
        }, 403),
      ]);
      await expectLater(
        service(rc).testConnection(LlmProviderId.gemini, apiKey: 'bad'),
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

  test('Riverpod wiring builds DefaultAiService from overridable deps', () {
    final rc = RecordingClient([(_) => jsonResponse({})]);
    final container = ProviderContainer(
      overrides: [
        aiHttpClientProvider.overrideWithValue(rc.client),
        apiKeyStoreProvider.overrideWithValue(keys),
        transcriptServiceProvider.overrideWithValue(transcripts),
      ],
    );
    addTearDown(container.dispose);
    expect(container.read(aiServiceProvider), isA<DefaultAiService>());
    expect(
      container.read(llmProviderFactoryProvider),
      isA<DefaultLlmProviderFactory>(),
    );
  });
}
