import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/data/models/models.dart';
import 'package:quiz_app/data/repositories/mistake_repository.dart';
import 'package:quiz_app/features/study/presentation/mistakes_screen.dart';

import '../quizzes/support/fakes.dart';

Question _q(String id, String prompt) => Question(
  id: id,
  type: QuestionType.trueFalse,
  prompt: prompt,
  options: const ['True', 'False'],
  correctIndices: const [0],
);

void _size(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _wrong(TestEnv env, String quizId, String qid, DateTime at) {
  env.now = at;
  return env.mistakes.recordAnswer(
    quizId: quizId,
    questionId: qid,
    correct: false,
  );
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  final f = find.byKey(Key(key));
  await tester.ensureVisible(f);
  await tester.tap(f);
  await tester.pumpAndSettle();
}

/// Physics: Mechanics (2 open, a1 twice wrong), Optics (1 open);
/// Chemistry: Atoms (1 open, 1 resolved).
Future<TestEnv> _seed() async {
  final env = TestEnv();
  env.subjects
    ..add(subject('s1', 'Physics'))
    ..add(subject('s2', 'Chemistry'));
  env.quizzes
    ..add(
      quiz('qa', [
        _q('a1', 'Force equals?'),
        _q('a2', 'Unit of work?'),
      ], title: 'Mechanics'),
    )
    ..add(quiz('qb', [_q('b1', 'Speed of light?')], title: 'Optics'))
    ..add(
      quiz(
        'qc',
        [_q('c1', 'Proton charge?'), _q('c2', 'Electron mass?')],
        title: 'Atoms',
        subjectId: 's2',
      ),
    );
  final day = DateTime.utc(2026, 1, 1, 12);
  await _wrong(env, 'qa', 'a1', day);
  await _wrong(env, 'qa', 'a1', day.add(const Duration(days: 2)));
  await _wrong(env, 'qa', 'a2', day);
  await _wrong(env, 'qb', 'b1', day.add(const Duration(days: 1)));
  await _wrong(env, 'qc', 'c1', day);
  await _wrong(env, 'qc', 'c2', day);
  for (var i = 0; i < 2; i++) {
    await env.mistakes.recordAnswer(
      quizId: 'qc',
      questionId: 'c2',
      correct: true,
    );
  }
  env.now = fixedNow;
  return env;
}

void main() {
  test('groupMistakesBySubject keeps first-seen order', () {
    final qa = quiz('qa', [_q('a1', 'A')]);
    final qb = quiz('qb', [_q('b1', 'B')], subjectId: 's2');
    final qc = quiz('qc', [_q('c1', 'C')]);
    MistakeGroup group(Quiz quiz) => MistakeGroup(
      quiz: quiz,
      entries: [
        MistakeEntry(
          mistake: Mistake(
            id: quiz.id,
            ownerId: userId,
            quizId: quiz.id,
            questionId: quiz.questions.first.id,
            wrongCount: 1,
            createdAt: fixedNow,
            updatedAt: fixedNow,
          ),
          question: quiz.questions.first,
        ),
      ],
    );
    final grouped = groupMistakesBySubject(
      [group(qa), group(qb), group(qc)],
      {'s1': subject('s1', 'Physics')},
    );
    expect(grouped.map((g) => g.subjectId), ['s1', 's2']);
    expect(grouped.first.groups.map((g) => g.quiz.id), ['qa', 'qc']);
    expect(grouped.first.count, 2);
    expect(grouped.last.subject, isNull);
  });

  testWidgets('groups open mistakes by subject and quiz; resolved history is '
      'collapsed', (tester) async {
    _size(tester);
    final env = await _seed();
    await tester.pumpWidget(env.app('/mistakes'));
    await tester.pumpAndSettle();

    expect(find.text('4 open mistakes in 3 quizzes'), findsOneWidget);

    final physics = find.byKey(const Key('mistakes-subject-s1'));
    final chemistry = find.byKey(const Key('mistakes-subject-s2'));
    expect(
      find.descendant(of: physics, matching: find.textContaining('Physics')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: physics, matching: find.text('Mechanics')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: physics, matching: find.text('Optics')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: chemistry, matching: find.text('Atoms')),
      findsOneWidget,
    );
    // Most recent wrong answer first: Physics (Mechanics, Jan 3) on top.
    expect(
      tester.getTopLeft(physics).dy,
      lessThan(tester.getTopLeft(chemistry).dy),
    );

    final mechanics = find.byKey(const Key('mistakes-quiz-qa'));
    expect(
      find.descendant(
        of: mechanics,
        matching: find.text('2 mistakes · last wrong Jan 3, 2026'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('mistake-qa-a1')),
        matching: find.text('Wrong 2× · Jan 3, 2026'),
      ),
      findsOneWidget,
    );
    expect(find.text('Unit of work?'), findsOneWidget);

    // Resolved: collapsed until expanded.
    expect(find.text('Electron mass?'), findsNothing);
    await _tapKey(tester, 'resolved-mistakes');
    expect(find.text('Electron mass?'), findsOneWidget);
    expect(find.text('Atoms · resolved Jan 1, 2026'), findsOneWidget);
  });

  testWidgets('"I know this" resolves a mistake', (tester) async {
    _size(tester);
    final env = await _seed();
    await tester.pumpWidget(env.app('/mistakes'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('mistake-qb-b1')),
        matching: find.byTooltip('I know this'),
      ),
    );
    await tester.pumpAndSettle();
    expect(env.mistakes.find('qb', 'b1')!.isOpen, isFalse);
    expect(find.byKey(const Key('mistakes-quiz-qb')), findsNothing);
    expect(find.text('3 open mistakes in 2 quizzes'), findsOneWidget);
  });

  testWidgets('per-quiz Practice opens the mistakes mode of that quiz', (
    tester,
  ) async {
    _size(tester);
    final env = await _seed();
    await tester.pumpWidget(env.app('/mistakes'));
    await tester.pumpAndSettle();
    await _tapKey(tester, 'practice-quiz-qa');
    expect(find.text('Practise mistakes'), findsOneWidget);
    expect(find.text('2 questions'), findsOneWidget);
  });

  testWidgets('Practice all plays every open mistake and saves one '
      'mistakes-mode attempt per quiz', (tester) async {
    _size(tester);
    final env = await _seed();
    await tester.pumpWidget(env.app('/mistakes'));
    await tester.pumpAndSettle();
    await _tapKey(tester, 'practice-all-mistakes');
    expect(find.text('Practise all mistakes'), findsOneWidget);
    expect(find.text('4 questions'), findsOneWidget);
    await _tapKey(tester, 'start-quiz');

    // Answer "Speed of light?" wrong, everything else right.
    for (var i = 0; i < 4; i++) {
      final wrong = find.text('Speed of light?').evaluate().isNotEmpty;
      await _tapKey(tester, wrong ? 'option-1' : 'option-0');
      await _tapKey(tester, 'primary-action');
      await _tapKey(tester, 'primary-action');
    }
    expect(find.text('75%'), findsOneWidget);
    expect(find.text('Saved to your history'), findsOneWidget);

    final saved = env.attempts.saved;
    expect(saved, hasLength(3));
    expect(saved.every((a) => a.mode == AttemptMode.mistakes), isTrue);
    final byQuiz = {for (final a in saved) a.quizId: a};
    expect(byQuiz['qa']!.questionIds, ['a1', 'a2']);
    expect(byQuiz['qa']!.score, 2);
    expect(byQuiz['qb']!.questionIds, ['b1']);
    expect(byQuiz['qb']!.score, 0);
    expect(byQuiz['qc']!.questionIds, ['c1']);
    expect(byQuiz['qc']!.answers.single.questionId, 'c1');

    expect(env.mistakes.find('qa', 'a1')!.correctStreak, 1);
    expect(env.mistakes.find('qb', 'b1')!.wrongCount, 2);

    // Done returns to the Mistakes screen.
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('4 open mistakes in 3 quizzes'), findsOneWidget);
  });

  testWidgets('Explain on a mistake row explains the correct answer', (
    tester,
  ) async {
    _size(tester);
    final env = await _seed();
    await tester.pumpWidget(env.app('/mistakes'));
    await tester.pumpAndSettle();
    await _tapKey(tester, 'explain-b1');
    expect(find.text('Explanation'), findsOneWidget);
    expect(
      find.textContaining('because of the facts', findRichText: true),
      findsOneWidget,
    );
    final call = env.tools.explainCalls.single;
    expect(call.question.prompt, 'Speed of light?');
    expect(call.answer, isNull);
  });

  testWidgets('Practice all: Explain after checking uses the question\'s '
      'quiz notes', (tester) async {
    _size(tester);
    final env = await _seed();
    env.notes.add(
      Note(
        id: 'n-optics',
        subjectId: 's1',
        ownerId: userId,
        title: 'Optics notes',
        contentMd: 'Light is fast.',
        createdAt: fixedNow,
        updatedAt: fixedNow,
      ),
    );
    env.quizzes.add(
      env.quizzes.all
          .firstWhere((q) => q.id == 'qb')
          .copyWith(noteId: 'n-optics'),
    );
    await tester.pumpWidget(env.app('/mistakes'));
    await tester.pumpAndSettle();
    await _tapKey(tester, 'practice-all-mistakes');
    await _tapKey(tester, 'start-quiz');
    while (find.text('Speed of light?').evaluate().isEmpty) {
      await _tapKey(tester, 'option-0');
      await _tapKey(tester, 'primary-action');
      await _tapKey(tester, 'primary-action');
    }
    await _tapKey(tester, 'option-1');
    await _tapKey(tester, 'primary-action');
    await tester.tap(find.text('Explain'));
    await tester.pumpAndSettle();
    final call = env.tools.explainCalls.single;
    expect(call.question.prompt, 'Speed of light?');
    expect(call.answer!.selectedIndices, [1]);
    expect([for (final s in call.sources) s.id], ['n-optics']);
  });

  testWidgets('empty state', (tester) async {
    _size(tester);
    final env = TestEnv();
    await tester.pumpWidget(env.app('/mistakes'));
    await tester.pumpAndSettle();
    expect(find.text('No mistakes to review'), findsOneWidget);
    expect(find.byKey(const Key('practice-all-mistakes')), findsNothing);
    expect(find.byKey(const Key('resolved-mistakes')), findsNothing);
  });
}
