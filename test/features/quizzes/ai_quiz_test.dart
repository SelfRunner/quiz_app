import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:quiz_app/ai/ai_tools_service.dart';
import 'package:quiz_app/core/errors/app_exception.dart';
import 'package:quiz_app/core/widgets/locked_feature.dart';
import 'package:quiz_app/data/data_providers.dart';
import 'package:quiz_app/data/local/hive_boxes.dart';
import 'package:quiz_app/data/models/models.dart';
import 'package:quiz_app/features/quizzes/application/ai_grading.dart';
import 'package:quiz_app/features/quizzes/application/answer_explainer.dart';
import 'package:quiz_app/features/quizzes/domain/quiz_session.dart';

import 'support/fakes.dart';

const _single = Question(
  id: 'single',
  type: QuestionType.mcqSingle,
  prompt: 'Capital of France?',
  options: ['Berlin', 'Paris', 'Rome'],
  correctIndices: [1],
);
const _short = Question(
  id: 'short',
  type: QuestionType.shortAnswer,
  prompt: 'Speed of light?',
  answerText: '299,792 km/s',
);
const _short2 = Question(
  id: 'short2',
  type: QuestionType.shortAnswer,
  prompt: 'Boiling point of water?',
  answerText: '100 °C at sea level',
);

ShortAnswerGrade _grade(GradeVerdict v, String feedback) => ShortAnswerGrade(
  verdict: v,
  score: switch (v) {
    GradeVerdict.correct => 1,
    GradeVerdict.partial => 0.5,
    GradeVerdict.incorrect => 0,
  },
  feedback: feedback,
  selection: testSelection,
);

void _size(WidgetTester tester, [Size size = const Size(800, 1400)]) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _tapKey(WidgetTester tester, String key) =>
    _tap(tester, find.byKey(Key(key)));

Note _note(String id, String title, String content) => Note(
  id: id,
  subjectId: 's1',
  ownerId: userId,
  title: title,
  contentMd: content,
  createdAt: fixedNow,
  updatedAt: fixedNow,
);

/// Practice play of [questions] (quiz `q1`, linked to note `n1` and the
/// source notes `n1`, `n2`).
Future<TestEnv> _play(
  WidgetTester tester,
  List<Question> questions, {
  bool aiReady = true,
  bool aiGrading = false,
}) async {
  _size(tester);
  final env = TestEnv()
    ..aiReady = aiReady
    ..aiGrading = aiGrading;
  env.notes.add(_note('n1', 'Geography notes', 'Paris is the capital.'));
  env.quizzes.add(
    quiz('q1', questions, noteId: 'n1').copyWith(
      source: const QuizSource(
        notes: [
          QuizSourceRef(id: 'n1', name: 'Geography notes'),
          QuizSourceRef(id: 'n2', name: 'Deleted note'),
        ],
      ),
    ),
  );
  await tester.pumpWidget(env.app('/quizzes/q1/play'));
  await tester.pumpAndSettle();
  await _tapKey(tester, 'start-quiz');
  return env;
}

void main() {
  group('Explain this', () {
    testWidgets('after checking an answer: explanation with the quiz notes '
        'as sources and citation chips that open the note', (tester) async {
      final env = await _play(tester, const [_single]);
      await _tapKey(tester, 'option-0'); // Berlin (wrong)
      await _tapKey(tester, 'primary-action');
      expect(find.byKey(const Key('explain-single')), findsOneWidget);

      await _tapKey(tester, 'explain-single');
      expect(find.text('Explanation'), findsOneWidget);
      expect(
        find.textContaining('because of the notes', findRichText: true),
        findsOneWidget,
      );
      final call = env.tools.explainCalls.single;
      expect(call.question.prompt, 'Capital of France?');
      expect(call.answer!.selectedIndices, [0]);
      expect(call.answer!.isCorrect, isFalse);
      // n2 is not available locally and is skipped.
      expect([for (final s in call.sources) s.id], ['n1']);
      expect((call.sources.single as NoteSource).markdown, contains('Paris'));
      expect(find.textContaining('gpt-test'), findsOneWidget);

      await _tapKey(tester, 'explain-citation-1');
      expect(find.text('Note n1'), findsOneWidget);
    });

    testWidgets('is cached per question and answer for the session', (
      tester,
    ) async {
      final env = await _play(tester, const [_single]);
      await _tapKey(tester, 'option-1');
      await _tapKey(tester, 'primary-action');
      await _tapKey(tester, 'explain-single');
      expect(env.tools.explainCalls, hasLength(1));
      Navigator.of(tester.element(find.text('Explanation'))).pop();
      await tester.pumpAndSettle();

      // Same question + answer from the results review: no new request.
      await _tapKey(tester, 'primary-action'); // See results
      expect(find.byKey(const Key('result-percent')), findsOneWidget);
      await _tapKey(tester, 'explain-single');
      expect(
        find.textContaining('because of the notes', findRichText: true),
        findsOneWidget,
      );
      expect(env.tools.explainCalls, hasLength(1));
    });

    testWidgets('shows progress, then an error with retry', (tester) async {
      final env = await _play(tester, const [_single]);
      var completer = Completer<AiExplanation>();
      env.tools.onExplain = (_, _, _) => completer.future;
      await _tapKey(tester, 'option-1');
      await _tapKey(tester, 'primary-action');
      await tester.tap(find.byKey(const Key('explain-single')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('explain-loading')), findsOneWidget);

      completer.completeError(
        const NetworkException('You appear to be offline.'),
      );
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('explain-error')), findsOneWidget);
      expect(find.textContaining('offline'), findsOneWidget);

      // Failures are not cached: retry makes a new request.
      completer = Completer<AiExplanation>();
      await tester.tap(find.byKey(const Key('explain-retry')));
      await tester.pump();
      completer.complete(FakeAiToolsService.defaultExplanation(const []));
      await tester.pumpAndSettle();
      expect(env.tools.explainCalls, hasLength(2));
      expect(
        find.textContaining('because of the facts', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('is locked when AI is not set up', (tester) async {
      final env = await _play(tester, const [_single], aiReady: false);
      await _tapKey(tester, 'option-1');
      await _tapKey(tester, 'primary-action');
      final gate = find.ancestor(
        of: find.byKey(const Key('explain-single')),
        matching: find.byType(LockedFeature),
      );
      expect(
        find.descendant(of: gate, matching: find.byKey(LockedFeature.badgeKey)),
        findsOneWidget,
      );
      await _tap(tester, find.text('Explain'));
      expect(find.text('Set up AI'), findsOneWidget);
      expect(find.text('Explanation'), findsNothing);
      expect(env.tools.explainCalls, isEmpty);
    });

    testWidgets('exam results review has Explain per question', (tester) async {
      _size(tester);
      final env = TestEnv()..quizzes.add(quiz('q1', const [_single]));
      await tester.pumpWidget(env.app('/quizzes/q1/play?mode=exam'));
      await tester.pumpAndSettle();
      await _tapKey(tester, 'start-exam');
      await _tapKey(tester, 'option-2');
      await _tapKey(tester, 'exam-submit');
      await _tapKey(tester, 'confirm-submit');
      await _tapKey(tester, 'explain-single');
      expect(
        find.textContaining('because of the facts', findRichText: true),
        findsOneWidget,
      );
      expect(env.tools.explainCalls.single.answer!.selectedIndices, [2]);
    });

    test('cache keys depend on the question and the answer', () {
      const a = ExplainTarget(
        question: _single,
        answer: QuestionAnswer(questionId: 'single', selectedIndices: [0]),
      );
      const same = ExplainTarget(
        question: _single,
        answer: QuestionAnswer(
          questionId: 'single',
          selectedIndices: [0],
          isCorrect: false,
        ),
      );
      const other = ExplainTarget(
        question: _single,
        answer: QuestionAnswer(questionId: 'single', selectedIndices: [1]),
      );
      const none = ExplainTarget(question: _single);
      expect(a.cacheKey, same.cacheKey);
      expect(a.cacheKey, isNot(other.cacheKey));
      expect(a.cacheKey, isNot(none.cacheKey));
    });

    test('cache shares in-flight requests and drops failures', () async {
      final cache = ExplanationCache();
      var calls = 0;
      Future<AiExplanation> ok() async {
        calls++;
        return FakeAiToolsService.defaultExplanation(const []);
      }

      final f1 = cache.getOrCreate('k', ok);
      final f2 = cache.getOrCreate('k', ok);
      expect(identical(f1, f2), isTrue);
      await f1;
      expect(calls, 1);

      final failing = cache.getOrCreate(
        'bad',
        () async => throw const NetworkException('offline'),
      );
      await expectLater(failing, throwsA(isA<NetworkException>()));
      expect(cache.peek('bad'), isNull);
      expect(cache.peek('k'), isNotNull);
    });
  });

  group('AI grading (practice)', () {
    Future<void> answerShort(WidgetTester tester, String text) async {
      await tester.enterText(find.byKey(const Key('short-answer-input')), text);
      await tester.pump();
      await _tapKey(tester, 'primary-action'); // Show answer
    }

    testWidgets('partial verdict, accepted: half a point', (tester) async {
      final env = await _play(tester, const [_short], aiGrading: true);
      env.tools.onGrade = (_, _) async =>
          _grade(GradeVerdict.partial, 'Right order of magnitude.');
      await answerShort(tester, '300,000 km/s');

      final call = env.tools.gradeCalls.single;
      expect(call.question, 'Speed of light?');
      expect(call.modelAnswer, '299,792 km/s');
      expect(call.answer, '300,000 km/s');
      expect(find.text('AI grade: Partly correct'), findsOneWidget);
      expect(find.textContaining('Right order of magnitude.'), findsOneWidget);
      expect(find.text('I got it'), findsNothing);

      await _tapKey(tester, 'ai-grade-accept');
      expect(find.text('Partly correct'), findsOneWidget);
      await _tapKey(tester, 'primary-action'); // See results
      expect(find.text('50%'), findsOneWidget);
      expect(find.textContaining('0.5 of 1 correct'), findsOneWidget);
      final saved = env.attempts.saved.single;
      expect(saved.score, 0.5);
      expect(saved.answers.single.isCorrect, isFalse);
      expect(saved.answers.single.textAnswer, '300,000 km/s');
    });

    testWidgets('override: mark an incorrect verdict right', (tester) async {
      final env = await _play(tester, const [_short], aiGrading: true);
      env.tools.onGrade = (_, _) async =>
          _grade(GradeVerdict.incorrect, 'Missing units.');
      await answerShort(tester, 'c');
      expect(find.text('AI grade: Incorrect'), findsOneWidget);
      await _tapKey(tester, 'ai-grade-right');
      expect(find.text('Correct!'), findsOneWidget);
      expect(find.textContaining('You marked it right.'), findsOneWidget);
      await _tapKey(tester, 'primary-action');
      expect(env.attempts.saved.single.score, 1);
      expect(env.attempts.saved.single.answers.single.isCorrect, isTrue);
    });

    testWidgets('falls back to self-grading when grading fails', (
      tester,
    ) async {
      final env = await _play(tester, const [_short], aiGrading: true);
      env.tools.onGrade = (_, _) async =>
          throw const NetworkException('You appear to be offline.');
      await answerShort(tester, '300,000 km/s');
      expect(find.byKey(const Key('ai-grade-error')), findsOneWidget);
      expect(find.textContaining('offline'), findsOneWidget);
      await _tap(tester, find.text('I got it'));
      expect(find.text('Correct!'), findsOneWidget);
      await _tapKey(tester, 'primary-action');
      expect(env.attempts.saved.single.score, 1);
    });

    testWidgets('"Grade myself" while the AI is still grading', (tester) async {
      final env = await _play(tester, const [_short], aiGrading: true);
      final pending = Completer<ShortAnswerGrade>();
      env.tools.onGrade = (_, _) => pending.future;
      await tester.enterText(
        find.byKey(const Key('short-answer-input')),
        'fast',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('primary-action')));
      await tester.pump();
      expect(find.byKey(const Key('ai-grading')), findsOneWidget);
      await tester.tap(find.byKey(const Key('ai-grade-skip')));
      await tester.pump();
      pending.complete(_grade(GradeVerdict.correct, 'Yes'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ai-verdict')), findsNothing);
      expect(find.text('I missed it'), findsOneWidget);
    });

    testWidgets('off by default: self-grading, no AI calls', (tester) async {
      final env = await _play(tester, const [_short]);
      await answerShort(tester, '300,000 km/s');
      expect(find.text('I got it'), findsOneWidget);
      expect(env.tools.gradeCalls, isEmpty);
    });

    testWidgets('blank answers are self-graded', (tester) async {
      final env = await _play(tester, const [_short], aiGrading: true);
      await _tapKey(tester, 'primary-action');
      expect(find.text('I got it'), findsOneWidget);
      expect(env.tools.gradeCalls, isEmpty);
    });

    testWidgets('setting is locked until AI is ready, toggles otherwise', (
      tester,
    ) async {
      _size(tester);
      final locked = TestEnv()
        ..aiReady = false
        ..quizzes.add(quiz('q1', const [_short]));
      await tester.pumpWidget(locked.app('/quizzes/q1/play'));
      await tester.pumpAndSettle();
      final tile = find.byKey(const Key('ai-grading-switch'));
      expect(tester.widget<SwitchListTile>(tile).onChanged, isNull);
      expect(find.text('Set up AI in Settings to use this.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());

      final env = TestEnv()..quizzes.add(quiz('q1', const [_short]));
      await tester.pumpWidget(env.app('/quizzes/q1/play'));
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(tile).value, isFalse);
      await _tap(tester, tile);
      expect(tester.widget<SwitchListTile>(tile).value, isTrue);
      await _tapKey(tester, 'start-quiz');
      await answerShort(tester, 'fast');
      expect(env.tools.gradeCalls, hasLength(1));
    });
  });

  group('AI grading (exam)', () {
    Future<TestEnv> submitExam(
      WidgetTester tester,
      Future<ShortAnswerGrade> Function(String question, String answer) onGrade,
    ) async {
      _size(tester);
      final env = TestEnv()
        ..aiGrading = true
        ..quizzes.add(quiz('q1', const [_single, _short, _short2]));
      env.tools.onGrade = onGrade;
      await tester.pumpWidget(env.app('/quizzes/q1/play?mode=exam'));
      await tester.pumpAndSettle();
      await _tapKey(tester, 'start-exam');
      for (var i = 0; i < 3; i++) {
        if (find.text(_single.prompt).evaluate().isNotEmpty) {
          await _tapKey(tester, 'option-1');
        } else {
          await tester.enterText(
            find.byKey(const Key('exam-short-answer')),
            find.text(_short.prompt).evaluate().isNotEmpty ? 'fast' : 'hot',
          );
          await tester.pump();
        }
        if (i < 2) await _tapKey(tester, 'exam-next');
      }
      await _tapKey(tester, 'exam-submit');
      await tester.tap(find.byKey(const Key('confirm-submit')));
      await tester.pump();
      await tester.pump();
      return env;
    }

    testWidgets('grades written answers in a batch with progress; '
        'overrides update the score', (tester) async {
      final pending = <String, Completer<ShortAnswerGrade>>{};
      final env = await submitExam(
        tester,
        (q, _) => (pending[q] = Completer<ShortAnswerGrade>()).future,
      );
      await tester.pump();
      expect(find.byKey(const Key('ai-grading-progress')), findsOneWidget);
      expect(find.textContaining('0 of 2'), findsOneWidget);
      expect(env.tools.gradeCalls, hasLength(2));

      pending[_short.prompt]!.complete(_grade(GradeVerdict.correct, 'Yes.'));
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('1 of 2'), findsOneWidget);

      pending[_short2.prompt]!.complete(
        _grade(GradeVerdict.partial, 'Mention the pressure.'),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ai-grading-progress')), findsNothing);
      expect(find.text('AI grade: Correct'), findsOneWidget);
      expect(find.text('AI grade: Partly correct'), findsOneWidget);
      // 1 (mcq) + 1 (correct) + 0.5 (partial) of 3.
      expect(find.textContaining('2.5 of 3 correct'), findsOneWidget);
      expect(find.text('83%'), findsOneWidget);
      var last = env.attempts.saved.last;
      expect(last.score, 2.5);
      final byId = {for (final a in last.answers) a.questionId: a};
      expect(byId['short']!.isCorrect, isTrue);
      expect(byId['short2']!.isCorrect, isFalse);
      expect(
        env.mistakes.recorded,
        containsAll([
          (quizId: 'q1', questionId: 'short', correct: true),
          (quizId: 'q1', questionId: 'short2', correct: false),
        ]),
      );

      // Override the partial grade.
      await _tapKey(tester, 'ai-grade-right-short2');
      expect(find.textContaining('3 of 3 correct'), findsOneWidget);
      expect(find.textContaining('You marked it right.'), findsOneWidget);
      last = env.attempts.saved.last;
      expect(last.score, 3);
      expect(
        last.answers.firstWhere((a) => a.questionId == 'short2').isCorrect,
        isTrue,
      );
    });

    testWidgets('failed grades fall back to self-grading', (tester) async {
      final env = await submitExam(
        tester,
        (q, _) async => q == _short.prompt
            ? _grade(GradeVerdict.incorrect, 'No.')
            : throw const AiException(
                'Rate limited',
                kind: AiErrorKind.rateLimited,
              ),
      );
      await tester.pumpAndSettle();
      expect(find.text('AI grade: Incorrect'), findsOneWidget);
      expect(find.byKey(const Key('ai-grade-error-short2')), findsOneWidget);
      expect(find.byKey(const Key('grade-right-short2')), findsOneWidget);
      expect(find.byKey(const Key('grade-right-short')), findsNothing);
      await _tapKey(tester, 'grade-right-short2');
      expect(find.textContaining('2 of 3 correct'), findsOneWidget);
      expect(env.attempts.saved.last.score, 2);
    });
  });

  group('QuizSession partial credit', () {
    test('partial counts half and as missed', () {
      final s =
          QuizSession(questions: const [_short, _short2], startedAt: fixedNow)
            ..reveal()
            ..selfGrade(correct: false, partial: true)
            ..next()
            ..reveal()
            ..selfGrade(correct: true);
      expect(s.isPartial('short'), isTrue);
      expect(s.credit, 1.5);
      expect(s.fraction, 0.75);
      expect(s.missedQuestions.map((q) => q.id), ['short']);
      final attempt = s.toAttempt(
        QuizAttempt(
          id: 'a',
          quizId: 'q1',
          ownerId: userId,
          startedAt: fixedNow,
          createdAt: fixedNow,
          updatedAt: fixedNow,
        ),
        completedAt: fixedNow,
      );
      expect(attempt.score, 1.5);
    });
  });

  group('AI grading setting', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('ai_grade_prefs');
      Hive.init(dir.path);
      await Hive.openBox<String>(HiveBoxes.prefs);
    });

    tearDown(() async {
      await Hive.close();
      await dir.delete(recursive: true);
    });

    test('is off by default and persisted per user', () {
      ProviderContainer forUser(String id) {
        final c = ProviderContainer(
          overrides: [currentUserIdProvider.overrideWithValue(id)],
        );
        addTearDown(c.dispose);
        return c;
      }

      final u1 = forUser('u1');
      expect(u1.read(aiGradeShortAnswersProvider), isFalse);
      u1.read(aiGradeShortAnswersProvider.notifier).set(true);
      expect(u1.read(aiGradeShortAnswersProvider), isTrue);
      expect(
        Hive.box<String>(HiveBoxes.prefs)
            .get(AiGradeShortAnswersSetting.prefsKeyFor('u1')),
        'true',
      );
      expect(forUser('u2').read(aiGradeShortAnswersProvider), isFalse);
      expect(forUser('u1').read(aiGradeShortAnswersProvider), isTrue);
    });
  });
}
