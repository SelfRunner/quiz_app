import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/data/models/models.dart';

import 'support/fakes.dart';

const _single = Question(
  id: 'single',
  type: QuestionType.mcqSingle,
  prompt: 'Capital of France?',
  options: ['Berlin', 'Paris', 'Rome'],
  correctIndices: [1],
);
const _tf = Question(
  id: 'tf',
  type: QuestionType.trueFalse,
  prompt: 'Water is wet.',
  options: ['True', 'False'],
  correctIndices: [0],
);

void _size(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  final f = find.byKey(Key(key));
  await tester.ensureVisible(f);
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> _tapText(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text));
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

/// Picks option [i], checks and continues.
Future<void> _answer(WidgetTester tester, int i) async {
  await _tapKey(tester, 'option-$i');
  await _tapKey(tester, 'primary-action'); // Check
  await _tapKey(tester, 'primary-action'); // Next / See results
}

void main() {
  testWidgets('practice saves mode + duration and records mistakes', (
    tester,
  ) async {
    _size(tester);
    final env = TestEnv()..quizzes.add(quiz('q1', const [_single, _tf]));
    await tester.pumpWidget(env.app('/quizzes/q1/play'));
    await tester.pumpAndSettle();
    await _tapKey(tester, 'start-quiz');
    env.now = fixedNow.add(const Duration(seconds: 42));
    await _answer(tester, 1); // correct
    await _answer(tester, 1); // wrong
    expect(find.text('50%'), findsOneWidget);

    final attempt = env.attempts.saved.single;
    expect(attempt.mode, AttemptMode.practice);
    expect(attempt.durationSeconds, 42);
    expect(attempt.questionIds, isNull);
    expect(env.mistakes.find('q1', 'tf')!.wrongCount, 1);
    expect(env.mistakes.find('q1', 'single'), isNull);

    // "Retry missed" rounds are not saved but still count for mistakes.
    await _tapText(tester, 'Retry missed (1)');
    await _answer(tester, 0); // correct
    expect(env.attempts.saved, hasLength(1));
    expect(env.mistakes.find('q1', 'tf')!.correctStreak, 1);
  });

  testWidgets('mistakes lifecycle: wrong answer opens, mistakes mode plays '
      'only open ones, two correct in a row resolve', (tester) async {
    _size(tester);
    final env = TestEnv()..quizzes.add(quiz('q1', const [_single, _tf]));
    await tester.pumpWidget(env.app('/quizzes/q1'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('practice-mistakes')), findsNothing);

    // Practice: get the true/false question wrong.
    await _tapKey(tester, 'play-quiz');
    await _tapKey(tester, 'start-quiz');
    await _answer(tester, 1); // correct
    await _answer(tester, 1); // wrong
    await _tapText(tester, 'Done');
    final opened = env.mistakes.find('q1', 'tf')!;
    expect(opened.isOpen, isTrue);
    expect(opened.wrongCount, 1);
    expect(opened.lastWrongAt, fixedNow);

    // The quiz screen offers the mistakes.
    expect(find.text('Practice mistakes (1)'), findsOneWidget);
    await _tapKey(tester, 'practice-mistakes');
    expect(find.text('Practise mistakes'), findsOneWidget);
    expect(find.text('1 question'), findsOneWidget);
    await _tapKey(tester, 'start-quiz');
    expect(find.text('Water is wet.'), findsOneWidget);
    expect(find.text('Capital of France?'), findsNothing);
    await _answer(tester, 0); // correct #1
    expect(find.text('100%'), findsOneWidget);
    expect(find.text('Saved to your history'), findsOneWidget);
    var attempt = env.attempts.saved.last;
    expect(attempt.mode, AttemptMode.mistakes);
    expect(attempt.questionIds, ['tf']);
    expect(attempt.total, 1);
    expect(env.mistakes.find('q1', 'tf')!.isOpen, isTrue);
    expect(env.mistakes.find('q1', 'tf')!.correctStreak, 1);

    // Retry: still open, second correct answer resolves it.
    await _tapText(tester, 'Retry');
    expect(find.text('Water is wet.'), findsOneWidget);
    await _answer(tester, 0); // correct #2
    attempt = env.attempts.saved.last;
    expect(attempt.mode, AttemptMode.mistakes);
    expect(env.attempts.saved, hasLength(3));
    final resolved = env.mistakes.find('q1', 'tf')!;
    expect(resolved.isOpen, isFalse);
    expect(resolved.resolvedAt, isNotNull);

    // Back on the quiz screen: no mistakes left; history shows badges.
    await _tapText(tester, 'Done');
    expect(find.byKey(const Key('practice-mistakes')), findsNothing);
    expect(find.text('Mistakes'), findsNWidgets(2));
  });

  testWidgets('a wrong answer after a correct one resets the streak', (
    tester,
  ) async {
    _size(tester);
    final env = TestEnv()..quizzes.add(quiz('q1', const [_tf]));
    await env.mistakes.recordAnswer(
      quizId: 'q1',
      questionId: 'tf',
      correct: false,
    );
    await tester.pumpWidget(env.app('/quizzes/q1/play?mode=mistakes'));
    await tester.pumpAndSettle();
    await _tapKey(tester, 'start-quiz');
    await _answer(tester, 0); // correct
    await _tapText(tester, 'Retry');
    await _answer(tester, 1); // wrong
    final m = env.mistakes.find('q1', 'tf')!;
    expect(m.isOpen, isTrue);
    expect(m.correctStreak, 0);
    expect(m.wrongCount, 2);
  });

  testWidgets('mistakes mode without open mistakes shows an empty state', (
    tester,
  ) async {
    _size(tester);
    final env = TestEnv()..quizzes.add(quiz('q1', const [_tf]));
    await tester.pumpWidget(env.app('/quizzes/q1/play?mode=mistakes'));
    await tester.pumpAndSettle();
    expect(find.text('No open mistakes in this quiz. Nice work!'), findsOne);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('start-quiz')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('attempt history shows mode badges and durations', (
    tester,
  ) async {
    _size(tester);
    final env = TestEnv()..quizzes.add(quiz('q1', const [_single, _tf]));
    QuizAttempt attempt(
      String id,
      AttemptMode mode,
      int minutesAgo, {
      int? limit,
      int? duration,
    }) {
      final t = fixedNow.subtract(Duration(minutes: minutesAgo));
      return QuizAttempt(
        id: id,
        quizId: 'q1',
        ownerId: userId,
        score: 1,
        total: 2,
        mode: mode,
        timeLimitSeconds: limit,
        durationSeconds: duration,
        startedAt: t.subtract(const Duration(minutes: 3)),
        completedAt: t,
        createdAt: t,
        updatedAt: t,
      );
    }

    await env.attempts.save(attempt('a1', AttemptMode.practice, 30));
    await env.attempts.save(
      attempt('a2', AttemptMode.exam, 20, limit: 600, duration: 250),
    );
    await env.attempts.save(
      attempt('a3', AttemptMode.mistakes, 10, duration: 75),
    );
    await tester.pumpWidget(env.app('/quizzes/q1'));
    await tester.pumpAndSettle();
    expect(find.text('Exam'), findsNWidgets(2)); // button + badge
    expect(find.text('Mistakes'), findsOneWidget);
    expect(find.text('1 of 2 correct · 4m 10s of 10 min'), findsOneWidget);
    expect(find.text('1 of 2 correct · 1m 15s'), findsOneWidget);
    expect(find.text('1 of 2 correct · 3m 0s'), findsOneWidget);
  });
}
