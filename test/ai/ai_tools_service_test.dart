import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/ai/ai_tools_service.dart';
import 'package:quiz_app/ai/default_ai_tools_service.dart';
import 'package:quiz_app/ai/llm_provider.dart';
import 'package:quiz_app/ai/llm_resolver.dart';
import 'package:quiz_app/ai/providers/default_llm_provider_factory.dart';
import 'package:quiz_app/ai/secure_api_key_store.dart';
import 'package:quiz_app/ai/transcript_service.dart';
import 'package:quiz_app/core/errors/app_exception.dart';
import 'package:quiz_app/data/models/question.dart';
import 'package:quiz_app/data/models/quiz_attempt.dart';

import 'test_helpers.dart';

class _NoTranscripts implements TranscriptService {
  @override
  Future<VideoTranscript> fetchTranscript(String url) =>
      throw const TranscriptUnavailableException('none');
}

Map<String, dynamic> _openAi(Object json) => {
  'status': 'completed',
  'output': [
    {
      'type': 'message',
      'content': [
        {'type': 'output_text', 'text': jsonEncode(json)},
      ],
    },
  ],
};

void main() {
  late SecureApiKeyStore keys;

  setUp(() async {
    keys = SecureApiKeyStore(userId: 'u1', backend: InMemoryKeyValueStore());
    await keys.setApiKey(LlmProviderId.openai, 'sk-openai');
    await keys.setSelectedProvider(LlmProviderId.openai);
  });

  DefaultAiToolsService service(
    RecordingClient rc, {
    int maxNoteChars = 60000,
  }) => DefaultAiToolsService(
    resolver: LlmResolver(
      keyStore: keys,
      providerFactory: DefaultLlmProviderFactory(rc.client, isWeb: false),
      isWeb: false,
    ),
    transcriptService: _NoTranscripts(),
    maxNoteChars: maxNoteChars,
  );

  String prompt(Captured c) => c.json['input'] as String;

  group('transformNote', () {
    test('summarize: structured request and result', () async {
      final rc = RecordingClient([
        (_) => jsonResponse(
          _openAi({'title': 'Cells — summary', 'markdown': '- ATP [x]'}),
        ),
      ]);
      final r = await service(rc).transformNote(
        '## Cells\nMitochondria make ATP.',
        NoteTool.summarize,
        title: 'Cells',
      );
      expect(r.title, 'Cells — summary');
      expect(r.markdown, '- ATP [x]');
      expect(r.inputTruncated, isFalse);
      expect(r.selection.providerId, LlmProviderId.openai);

      final json = rc.requests.single.json;
      final format = (json['text'] as Map)['format'] as Map;
      expect(format['name'], 'NoteToolResult');
      expect(format['strict'], isTrue);
      final schema = format['schema'] as Map;
      expect(schema['required'], ['title', 'markdown']);
      expect(
        (schema['properties'] as Map)['title'],
        containsPair('type', ['string', 'null']),
      );
      expect(json['instructions'], contains('editor of study notes'));
      final p = prompt(rc.requests.single);
      expect(p, startsWith('Summarize the note'));
      expect(p, contains('same language as the note'));
      expect(p, contains('The note "Cells":\n<note>\n## Cells'));
    });

    test('translate needs a language; prompt names it', () async {
      final rc = RecordingClient([
        (_) => jsonResponse(_openAi({'title': 'Zellen', 'markdown': 'Text'})),
      ]);
      await expectLater(
        service(rc).transformNote('x', NoteTool.translate(' ')),
        throwsA(isA<ValidationException>()),
      );
      expect(rc.requests, isEmpty);
      final r = await service(rc)
          .transformNote('Cells', NoteTool.translate('German'));
      expect(r.title, 'Zellen');
      expect(prompt(rc.requests.single), contains('into German'));
      expect(prompt(rc.requests.single), isNot(contains('same language')));
    });

    test(
      'too long: faithful tools reject, summarize uses an excerpt',
      () async {
        final rc = RecordingClient([
          (_) => jsonResponse(_openAi({'markdown': 'Short'})),
        ]);
        final long = 'word ' * 400;
        await expectLater(
          service(
            rc,
            maxNoteChars: 1000,
          ).transformNote(long, NoteTool.simplify),
          throwsA(
            isA<ValidationException>().having(
              (e) => e.message,
              'message',
              contains('too long to simplify'),
            ),
          ),
        );
        final r = await service(
          rc,
          maxNoteChars: 1000,
        ).transformNote(long, NoteTool.studyGuide);
        expect(r.inputTruncated, isTrue);
        expect(r.title, isNull);
        final p = prompt(rc.requests.single);
        expect(p, contains('characters omitted'));
        expect(p, contains('## Self-check questions'));
      },
    );

    test('invalid output -> one repair retry', () async {
      final rc = RecordingClient([
        (_) => jsonResponse(_openAi({'markdown': ''})),
        (_) => jsonResponse(_openAi({'markdown': 'Fixed'})),
      ]);
      final r = await service(rc).transformNote('# A', NoteTool.fixFormatting);
      expect(r.markdown, 'Fixed');
      expect(rc.requests, hasLength(2));
      expect(
        prompt(rc.requests[1]),
        contains('"markdown" must be a non-empty'),
      );
    });

    test('empty note -> ValidationException', () async {
      final rc = RecordingClient([(_) => jsonResponse({})]);
      await expectLater(
        service(rc).transformNote('  ', NoteTool.expand),
        throwsA(isA<ValidationException>()),
      );
    });
  });

  group('explainAnswer', () {
    const q = Question(
      id: 'q1',
      type: QuestionType.mcqSingle,
      prompt: 'Where is ATP made?',
      options: ['Nucleus', 'Mitochondria', 'Ribosome'],
      correctIndices: [1],
      explanation: 'Cellular respiration.',
    );

    test('prompt has options, answer and sources; citations parsed', () async {
      final rc = RecordingClient([
        (_) => jsonResponse(
          _openAi({
            'markdown':
                'ATP is made in the **mitochondria** [S1]; the nucleus '
                'stores DNA [S2]. [S5]',
          }),
        ),
      ]);
      final r = await service(rc).explainAnswer(
        q,
        const QuestionAnswer(
          questionId: 'q1',
          selectedIndices: [0],
          isCorrect: false,
        ),
        sources: [
          const NoteSource(id: 'n1', title: 'Cells', markdown: 'Mito = ATP'),
          FileSource(
            id: 'f1',
            name: 'slides.pdf',
            mimeType: 'application/pdf',
            bytes: Uint8List.fromList([1]),
          ),
        ],
      );
      expect(r.citations.map((c) => (c.marker, c.id)), [
        ('S1', 'n1'),
        ('S2', 'f1'),
      ]);
      expect(r.sources, hasLength(2));

      final json = rc.requests.single.json;
      expect(((json['text'] as Map)['format'] as Map)['name'], 'Explanation');
      expect(json['instructions'], contains('cite them'));
      final content =
          ((json['input'] as List).single as Map)['content'] as List;
      expect(content.first, {
        'type': 'input_text',
        'text': '[S2] file "slides.pdf"',
      });
      final p = (content.last as Map)['text'] as String;
      expect(p, contains('Question type: mcq_single'));
      expect(p, contains('B. Mitochondria (correct)'));
      expect(p, contains("Student's answer: A. Nucleus"));
      expect(p, contains('marked incorrect'));
      expect(p, contains('[S1] note "Cells"'));
    });

    test('without sources: plain prompt, no citations', () async {
      final rc = RecordingClient([
        (_) => jsonResponse(_openAi({'markdown': 'Because.'})),
      ]);
      final r = await service(rc).explainAnswer(q, null);
      expect(r.markdown, 'Because.');
      expect(r.citations, isEmpty);
      final p = prompt(rc.requests.single);
      expect(p, contains("Student's answer: (no answer)"));
      expect(p, isNot(contains('Sources (')));
    });
  });

  group('gradeShortAnswer', () {
    test('valid grade; request uses the grade schema', () async {
      final rc = RecordingClient([
        (_) => jsonResponse(
          _openAi({
            'feedback': 'Right idea.',
            'verdict': 'correct',
            'score': 0.95,
          }),
        ),
      ]);
      final g = await service(rc).gradeShortAnswer(
        'What makes ATP?',
        'Mitochondria',
        'the mitochondrion',
      );
      expect(g.verdict, GradeVerdict.correct);
      expect(g.score, 0.95);
      expect(g.feedback, 'Right idea.');
      expect(g.isCorrect, isTrue);
      expect(g.selection?.providerId, LlmProviderId.openai);
      final format = (rc.requests.single.json['text'] as Map)['format'] as Map;
      expect(format['name'], 'ShortAnswerGrade');
      final props = (format['schema'] as Map)['properties'] as Map;
      expect((props['verdict'] as Map)['enum'], [
        'correct',
        'partial',
        'incorrect',
      ]);
      expect(props.keys.first, 'feedback');
      final p = prompt(rc.requests.single);
      expect(
        p,
        contains('<student_answer>\nthe mitochondrion\n</student_answer>'),
      );
    });

    test(
      'invalid verdict -> repair; second invalid -> invalidOutput',
      () async {
        final rc = RecordingClient([
          (_) => jsonResponse(
            _openAi({'feedback': 'Hmm', 'verdict': 'maybe', 'score': 0.5}),
          ),
        ]);
        await expectLater(
          service(rc).gradeShortAnswer('q', 'a', 'b'),
          throwsA(
            isA<AiException>().having(
              (e) => e.kind,
              'kind',
              AiErrorKind.invalidOutput,
            ),
          ),
        );
        expect(rc.requests, hasLength(2));
      },
    );

    test('blank answer graded locally', () async {
      final rc = RecordingClient([(_) => jsonResponse({})]);
      final g = await service(rc).gradeShortAnswer('q', 'a', '   ');
      expect(g.verdict, GradeVerdict.incorrect);
      expect(g.score, 0);
      expect(g.selection, isNull);
      expect(rc.requests, isEmpty);
    });

    test('Gemini and Anthropic get their schema dialects', () async {
      await keys.setApiKey(LlmProviderId.gemini, 'g');
      await keys.setApiKey(LlmProviderId.anthropic, 'a');
      const grade = {'feedback': 'ok', 'verdict': 'partial', 'score': 0.5};
      final rc = RecordingClient([
        (_) => jsonResponse({
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': jsonEncode(grade)},
                ],
              },
              'finishReason': 'STOP',
            },
          ],
        }),
        (_) => jsonResponse({
          'content': [
            {'type': 'text', 'text': jsonEncode(grade)},
          ],
          'stop_reason': 'end_turn',
        }),
      ]);
      final s = service(rc);
      final g1 = await s.gradeShortAnswer(
        'q',
        'a',
        'b',
        providerId: LlmProviderId.gemini,
      );
      final g2 = await s.gradeShortAnswer(
        'q',
        'a',
        'b',
        providerId: LlmProviderId.anthropic,
      );
      expect(
        [g1.verdict, g2.verdict],
        [GradeVerdict.partial, GradeVerdict.partial],
      );
      final gemSchema =
          (((rc.requests[0].json['generationConfig'] as Map)['responseFormat']
                      as Map)['text']
                  as Map)['schema']
              as Map;
      expect(((gemSchema['properties'] as Map)['score'] as Map)['maximum'], 1);
      final anthSchema =
          ((rc.requests[1].json['output_config'] as Map)['format']
                  as Map)['schema']
              as Map;
      final score = (anthSchema['properties'] as Map)['score'] as Map;
      expect(score.containsKey('maximum'), isFalse);
      expect(score['description'], contains('maximum: 1'));
    });
  });

  group('ToolValidators.grade', () {
    ({GradeVerdict verdict, double score, String feedback})? value(
      Map<String, dynamic> json,
    ) => ToolValidators.grade(json).value;

    test('clamps score into the verdict band', () {
      expect(
        value({'feedback': 'f', 'verdict': 'correct', 'score': 0.3})!.score,
        0.8,
      );
      expect(
        value({'feedback': 'f', 'verdict': 'incorrect', 'score': 0.9})!.score,
        0.2,
      );
      expect(
        value({'feedback': 'f', 'verdict': 'partial', 'score': 0.5})!.score,
        0.5,
      );
    });

    test('lenient verdict names, percent and string scores', () {
      final v = value({
        'feedback': 'f',
        'verdict': 'Partially correct',
        'score': '60%',
      })!;
      expect(v.verdict, GradeVerdict.partial);
      expect(v.score, closeTo(0.6, 1e-9));
      expect(
        value({'feedback': 'f', 'verdict': 'WRONG', 'score': 0})!.verdict,
        GradeVerdict.incorrect,
      );
    });

    test('missing/invalid score: usable value but not valid', () {
      final r = ToolValidators.grade({'feedback': 'f', 'verdict': 'correct'});
      expect(r.isValid, isFalse);
      expect(r.value!.score, 0.9);
      expect(r.errors.single, contains('"score"'));
      final neg = ToolValidators.grade({
        'feedback': 'f',
        'verdict': 'incorrect',
        'score': -3,
      });
      expect(neg.isValid, isFalse);
    });

    test('missing feedback or verdict -> no value', () {
      expect(value({'verdict': 'correct', 'score': 1}), isNull);
      expect(value({'feedback': 'f', 'score': 1}), isNull);
    });
  });
}
