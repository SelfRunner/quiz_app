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
  explanation: 'Paris is the capital.',
);
const _multi = Question(
  id: 'multi',
  type: QuestionType.mcqMulti,
  prompt: 'Prime numbers?',
  options: ['2', '4', '5'],
  correctIndices: [0, 2],
);
const _tf = Question(
  id: 'tf',
  type: QuestionType.trueFalse,
  prompt: 'Water is wet.',
  options: ['True', 'False'],
  correctIndices: [0],
);
const _short = Question(
  id: 'short',
  type: QuestionType.shortAnswer,
  prompt: 'Speed of light?',
  answerText: '299,792 km/s',
);

void _size(WidgetTester tester, [Size size = const Size(800, 1400)]) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _tapKey(WidgetTester tester, String key) =>
    _tap(tester, find.byKey(Key(key)));

/// The question currently shown (pools are served in random order).
Question _current(List<Question> questions) =>
    questions.firstWhere((q) => find.text(q.prompt).evaluate().isNotEmpty);

/// Picks the correct options of the current option question.
Future<void> _answerCorrectly(WidgetTester tester, Question q) async {
  for (final i in q.correctIndices) {
    await _tapKey(tester, 'option-$i'); // options are not shuffled
  }
}

void main() {
  testWidgets('exam from the quiz screen: setup dialog, no feedback, free '
      'navigation, flags, submit confirmation, results and saved attempt', (
    tester,
  ) async {
    _size(tester);
    const questions = [_single, _multi, _tf];
    final env = TestEnv()..quizzes.add(quiz('q1', questions));
    await tester.pumpWidget(env.app('/quizzes/q1'));
    await tester.pumpAndSettle();

    // Setup dialog.
    await _tapKey(tester, 'exam-quiz');
    expect(find.text('Exam mode'), findsOneWidget);
    expect(find.text('Every question, in random order.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('exam-count')), '9');
    await tester.pump();
    expect(find.text('Enter a number from 1 to 3'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('start-exam')))
          .onPressed,
      isNull,
    );
    await tester.enterText(find.byKey(const Key('exam-count')), '3');
    await tester.pump();
    await _tapKey(tester, 'limit-10');
    await _tapKey(tester, 'start-exam');

    expect(find.text('Question 1 of 3'), findsOneWidget);
    expect(find.text('10:00'), findsOneWidget);

    // Q1: answer correctly, no feedback; flag it.
    final q1 = _current(questions);
    await _answerCorrectly(tester, q1);
    expect(find.byKey(const Key('answer-feedback')), findsNothing);
    expect(find.text('Correct!'), findsNothing);
    expect(find.byKey(const Key('primary-action')), findsNothing);
    await _tapKey(tester, 'exam-flag');
    expect(find.text('Flagged'), findsOneWidget);

    // Q2: skip. Q3: answer wrong (first wrong option).
    await _tapKey(tester, 'exam-next');
    expect(find.text('Question 2 of 3'), findsOneWidget);
    final q2 = _current(questions);
    await _tapKey(tester, 'exam-next');
    expect(find.text('Question 3 of 3'), findsOneWidget);
    expect(find.byKey(const Key('exam-next')), findsNothing);
    expect(find.byKey(const Key('exam-finish')), findsOneWidget);
    final q3 = _current(questions);
    final wrong = List.generate(
      q3.options.length,
      (i) => i,
    ).firstWhere((i) => !q3.correctIndices.contains(i));
    await _tapKey(tester, 'option-$wrong');

    // Grid: jump back to question 2, then Previous to 1 (still flagged and
    // answered).
    await _tapKey(tester, 'exam-grid-button');
    expect(find.bySemanticsLabel('Question 1, answered, flagged'), findsOne);
    expect(find.bySemanticsLabel('Question 2, unanswered'), findsOne);
    expect(find.text('Answered 2'), findsOneWidget);
    await _tapKey(tester, 'exam-cell-1');
    expect(find.text('Question 2 of 3'), findsOneWidget);
    expect(find.text(q2.prompt), findsOneWidget);
    await _tapKey(tester, 'exam-prev');
    expect(find.text(q1.prompt), findsOneWidget);
    expect(find.text('Flagged'), findsOneWidget);

    // Submit after 95 seconds; the dialog reports the unanswered question.
    env.now = fixedNow.add(const Duration(seconds: 95));
    await tester.pump(const Duration(seconds: 1));
    await _tapKey(tester, 'exam-submit');
    expect(
      find.text(
        '1 of 3 questions unanswered. Unanswered questions count as wrong.',
      ),
      findsOneWidget,
    );
    expect(find.text('1 question flagged for review.'), findsOneWidget);
    expect(env.attempts.saved, isEmpty);
    await _tapKey(tester, 'confirm-submit');

    // Results.
    expect(find.text('Exam score'), findsOneWidget);
    expect(find.text('33%'), findsOneWidget);
    expect(find.text('1 of 3 correct · Time 1m 35s of 10 min'), findsOneWidget);
    expect(find.text('1 unanswered'), findsOneWidget);
    expect(find.text('Saved to your history'), findsOneWidget);
    if (q1 == _single || q2 == _single || q3 == _single) {
      await tester.scrollUntilVisible(
        find.text('Paris is the capital.'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('Paris is the capital.'), findsOneWidget);
    }

    final attempt = env.attempts.saved.single;
    expect(attempt.mode, AttemptMode.exam);
    expect(attempt.timeLimitSeconds, 600);
    expect(attempt.questionIds, [q1.id, q2.id, q3.id]);
    expect(attempt.durationSeconds, 95);
    expect(attempt.completedAt, env.now);
    expect(attempt.total, 3);
    expect(attempt.score, 1);
    expect(
      {for (final a in attempt.answers) a.questionId: a.isCorrect},
      {q1.id: true, q3.id: false},
    );

    // Graded answers went to the Mistakes set.
    expect(env.mistakes.find('q1', q3.id)?.isOpen, isTrue);
    expect(env.mistakes.find('q1', q1.id), isNull);
    expect(env.mistakes.find('q1', q2.id), isNull);
  });

  testWidgets('pool: random N questions are served and saved', (tester) async {
    _size(tester);
    const questions = [_single, _multi, _tf];
    final env = TestEnv()..quizzes.add(quiz('q1', questions));
    await tester.pumpWidget(env.app('/quizzes/q1/play?mode=exam'));
    await tester.pumpAndSettle();

    // Deep link: inline setup page.
    expect(find.text('Exam'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('exam-count')), '2');
    await tester.pump();
    expect(
      find.text('A random selection from the 3 questions.'),
      findsOneWidget,
    );
    await _tapKey(tester, 'exam-shuffle-options');
    await _tapKey(tester, 'start-exam');
    expect(find.text('Question 1 of 2'), findsOneWidget);
    expect(find.byKey(const Key('exam-timer')), findsOneWidget);
    expect(find.text('0:00'), findsOneWidget); // untimed: time spent

    await _tapKey(tester, 'exam-submit');
    expect(
      find.text(
        '2 of 2 questions unanswered. Unanswered questions count as wrong.',
      ),
      findsOneWidget,
    );
    await _tapKey(tester, 'confirm-submit');
    final attempt = env.attempts.saved.single;
    expect(attempt.timeLimitSeconds, isNull);
    expect(attempt.questionIds, hasLength(2));
    expect(
      attempt.questionIds!.every((id) => questions.any((q) => q.id == id)),
      isTrue,
    );
    expect(attempt.questionIds!.toSet(), hasLength(2));
    expect(attempt.total, 2);
    expect(attempt.score, 0);
    expect(find.text('0%'), findsOneWidget);
  });

  testWidgets('timer warns at one minute and auto-submits at zero', (
    tester,
  ) async {
    _size(tester);
    final env = TestEnv()..quizzes.add(quiz('q1', const [_single, _tf]));
    await tester.pumpWidget(env.app('/quizzes/q1/play?mode=exam'));
    await tester.pumpAndSettle();
    await _tapKey(tester, 'limit-5');
    await _tapKey(tester, 'start-exam');
    expect(find.text('5:00'), findsOneWidget);

    // Answer one question correctly.
    final q = _current(const [_single, _tf]);
    await _answerCorrectly(tester, q);

    env.now = fixedNow.add(const Duration(minutes: 2, seconds: 30));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('2:30'), findsOneWidget);
    expect(find.text('1 minute left'), findsNothing);

    env.now = fixedNow.add(const Duration(minutes: 4));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('1:00'), findsOneWidget);
    expect(find.text('1 minute left'), findsOneWidget);
    expect(env.attempts.saved, isEmpty);

    // Open the submit dialog; time running out closes it and submits.
    await _tapKey(tester, 'exam-submit');
    expect(find.text('Submit exam?'), findsOneWidget);
    env.now = fixedNow.add(const Duration(minutes: 5, seconds: 2));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.text('Submit exam?'), findsNothing);
    expect(find.byKey(const Key('exam-results')), findsOneWidget);
    expect(
      find.text('Time is up. Your exam was submitted automatically.'),
      findsOneWidget,
    );
    final attempt = env.attempts.saved.single;
    expect(attempt.durationSeconds, 300); // capped at the limit
    expect(attempt.timeLimitSeconds, 300);
    expect(attempt.completedAt, env.now);
    expect(attempt.score, 1);
    expect(attempt.answers, hasLength(1));
    expect(find.text('50%'), findsOneWidget);

    // The timer is stopped.
    env.now = fixedNow.add(const Duration(minutes: 10));
    await tester.pump(const Duration(seconds: 5));
    expect(env.attempts.saved, hasLength(1));
  });

  testWidgets('short answers are self-graded after submitting', (tester) async {
    _size(tester);
    final env = TestEnv()..quizzes.add(quiz('q1', const [_short]));
    await tester.pumpWidget(env.app('/quizzes/q1/play?mode=exam'));
    await tester.pumpAndSettle();
    await _tapKey(tester, 'start-exam');
    await tester.enterText(
      find.byKey(const Key('exam-short-answer')),
      '300k km/s',
    );
    await tester.pump();
    expect(
      find.textContaining('299,792 km/s'),
      findsNothing,
    ); // no model answer yet
    await _tapKey(tester, 'exam-submit');
    expect(find.text('All questions are answered.'), findsOneWidget);
    await _tapKey(tester, 'confirm-submit');

    expect(find.text('0%'), findsOneWidget);
    expect(find.textContaining('1 answer to self-grade'), findsOneWidget);
    expect(find.textContaining('299,792 km/s'), findsOneWidget);
    expect(env.mistakes.recorded, isEmpty);

    await _tapKey(tester, 'grade-wrong-short');
    expect(find.byKey(const Key('grade-right-short')), findsNothing);
    final last = env.attempts.saved.last;
    expect(last.answers.single.isCorrect, isFalse);
    expect(last.answers.single.textAnswer, '300k km/s');
    expect(env.mistakes.recorded, [
      (quizId: 'q1', questionId: 'short', correct: false),
    ]);
    expect(env.mistakes.find('q1', 'short')!.isOpen, isTrue);
  });

  testWidgets('quitting an exam asks first and discards the attempt', (
    tester,
  ) async {
    _size(tester);
    final env = TestEnv()..quizzes.add(quiz('q1', const [_single]));
    await tester.pumpWidget(env.app('/quizzes/q1'));
    await tester.pumpAndSettle();
    await _tapKey(tester, 'exam-quiz');
    await _tapKey(tester, 'start-exam');
    expect(find.text('Question 1 of 1'), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Quit this exam?'), findsOneWidget);
    await tester.tap(find.text('Quit'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('exam-quiz')), findsOneWidget);
    expect(env.attempts.saved, isEmpty);
    expect(env.attempts.deleted, hasLength(1));
  });

  testWidgets('wide layout shows the question grid beside the question', (
    tester,
  ) async {
    _size(tester, const Size(1280, 900));
    final env = TestEnv()..quizzes.add(quiz('q1', const [_single, _tf]));
    await tester.pumpWidget(env.app('/quizzes/q1/play?mode=exam'));
    await tester.pumpAndSettle();
    await _tapKey(tester, 'start-exam');
    expect(find.byKey(const Key('exam-grid-button')), findsNothing);
    expect(find.byKey(const Key('exam-cell-1')), findsOneWidget);
    await _tapKey(tester, 'exam-cell-1');
    expect(find.text('Question 2 of 2'), findsOneWidget);
  });
}
