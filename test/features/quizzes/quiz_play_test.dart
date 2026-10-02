import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/data/models/question.dart';
import 'package:quiz_app/features/quizzes/domain/quiz_session.dart';

import 'support/fakes.dart';

const _questions = [
  Question(
    id: 'single',
    type: QuestionType.mcqSingle,
    prompt: 'Capital of France?',
    options: ['Berlin', 'Paris', 'Rome'],
    correctIndices: [1],
    explanation: 'Paris is the capital.',
  ),
  Question(
    id: 'multi',
    type: QuestionType.mcqMulti,
    prompt: 'Prime numbers?',
    options: ['2', '4', '5'],
    correctIndices: [0, 2],
  ),
  Question(
    id: 'tf',
    type: QuestionType.trueFalse,
    prompt: 'Water is wet.',
    options: ['True', 'False'],
    correctIndices: [0],
  ),
  Question(
    id: 'short',
    type: QuestionType.shortAnswer,
    prompt: 'Speed of light?',
    answerText: '299,792 km/s',
  ),
];

Future<TestEnv> _pumpPlay(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final env = TestEnv()..quizzes.add(quiz('q1', _questions));
  await tester.pumpWidget(env.app('/quizzes/q1/play'));
  await tester.pumpAndSettle();
  return env;
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

void main() {
  group('QuizSession', () {
    test('grades selections against original indices when shuffled', () {
      final s = QuizSession(
        questions: _questions,
        startedAt: fixedNow,
        shuffleOptions: true,
      );
      final item = s.current;
      final display = item.optionOrder.indexOf(1); // 'Paris'
      s.toggleOption(display);
      expect(s.check(), isTrue);
      expect(s.answers().first.selectedIndices, [1]);
    });

    test('multi needs the exact set', () {
      final s = QuizSession(questions: [_questions[1]], startedAt: fixedNow)
        ..toggleOption(0)
        ..toggleOption(1)
        ..toggleOption(2)
        ..toggleOption(1); // untoggle
      expect(s.check(), isTrue);
      expect(s.correctCount, 1);
      expect(s.missedQuestions, isEmpty);
    });

    test('true/false keeps its order when shuffling options', () {
      final s = QuizSession(
        questions: [_questions[2]],
        startedAt: fixedNow,
        shuffleOptions: true,
      );
      expect(s.current.optionOrder, [0, 1]);
    });
  });

  testWidgets('plays all question types, scores and saves the attempt', (
    tester,
  ) async {
    final env = await _pumpPlay(tester);
    expect(find.text('4 questions'), findsOneWidget);
    await _tapKey(tester, 'start-quiz');

    // Single choice: correct.
    expect(find.text('Capital of France?'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('primary-action')))
          .onPressed,
      isNull,
      reason: 'Check is disabled until an option is picked',
    );
    await _tapKey(tester, 'option-1');
    await _tapKey(tester, 'primary-action'); // Check
    expect(find.text('Correct!'), findsOneWidget);
    expect(find.text('Paris is the capital.'), findsOneWidget);
    await _tapKey(tester, 'primary-action'); // Next

    // Multi: only one of two correct options -> wrong.
    await _tapKey(tester, 'option-0');
    await _tapKey(tester, 'primary-action');
    expect(find.text('Not quite'), findsOneWidget);
    await _tapKey(tester, 'primary-action');

    // True/false: correct.
    await _tapKey(tester, 'option-0');
    await _tapKey(tester, 'primary-action');
    expect(find.text('Correct!'), findsOneWidget);
    await _tapKey(tester, 'primary-action');

    // Short answer: reveal, then self-grade.
    await tester.enterText(
      find.byKey(const Key('short-answer-input')),
      '300k km/s',
    );
    await _tapKey(tester, 'primary-action'); // Show answer
    expect(find.text('299,792 km/s'), findsOneWidget);
    await tester.tap(find.text('I got it'));
    await tester.pumpAndSettle();
    expect(find.text('See results'), findsOneWidget);
    await _tapKey(tester, 'primary-action');

    expect(find.text('75%'), findsOneWidget);
    expect(find.textContaining('3 of 4 correct'), findsOneWidget);
    expect(find.text('Saved to your history'), findsOneWidget);

    expect(env.attempts.saved, hasLength(1));
    final attempt = env.attempts.saved.single;
    expect(attempt.quizId, 'q1');
    expect(attempt.ownerId, userId);
    expect(attempt.score, 3);
    expect(attempt.total, 4);
    expect(attempt.completedAt, fixedNow);
    expect(attempt.answers.map((a) => a.isCorrect), [true, false, true, true]);
    expect(attempt.answers[1].selectedIndices, [0]);
    expect(attempt.answers[3].textAnswer, '300k km/s');

    // Retry missed only: one question, practice round, not saved.
    await tester.tap(find.text('Retry missed (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Prime numbers?'), findsOneWidget);
    await _tapKey(tester, 'option-0');
    await _tapKey(tester, 'option-2');
    await _tapKey(tester, 'primary-action');
    expect(find.text('Correct!'), findsOneWidget);
    await _tapKey(tester, 'primary-action'); // See results
    expect(find.text('100%'), findsOneWidget);
    expect(find.textContaining('Practice round'), findsOneWidget);
    expect(env.attempts.saved, hasLength(1));
  });

  testWidgets('short answer self-graded as missed counts as wrong', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final env = TestEnv()..quizzes.add(quiz('q2', [_questions[3]]));
    await tester.pumpWidget(env.app('/quizzes/q2/play'));
    await tester.pumpAndSettle();
    await _tapKey(tester, 'start-quiz');
    await _tapKey(tester, 'primary-action'); // Show answer
    await tester.tap(find.text('I missed it'));
    await tester.pumpAndSettle();
    expect(find.text('Not quite'), findsOneWidget);
    await _tapKey(tester, 'primary-action');
    expect(find.text('0%'), findsOneWidget);
    expect(env.attempts.saved.single.answers.single.isCorrect, isFalse);
    expect(env.attempts.saved.single.score, 0);
  });

  testWidgets('keyboard: digits pick options, Enter checks and continues', (
    tester,
  ) async {
    await _pumpPlay(tester);
    await _tapKey(tester, 'start-quiz');
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Correct!'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Prime numbers?'), findsOneWidget);
  });

  testWidgets('quitting mid-quiz asks for confirmation', (tester) async {
    final env = await _pumpPlay(tester);
    await _tapKey(tester, 'start-quiz');
    await _tapKey(tester, 'option-0');
    await _tapKey(tester, 'primary-action');
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Quit this quiz?'), findsOneWidget);
    await tester.tap(find.text('Keep playing'));
    await tester.pumpAndSettle();
    expect(find.text('Capital of France?'), findsOneWidget);
    expect(env.attempts.saved, isEmpty);
  });
}
