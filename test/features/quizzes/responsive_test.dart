import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/data/models/models.dart';

import 'support/fakes.dart';

const _questions = [
  Question(
    id: 'a',
    type: QuestionType.mcqMulti,
    prompt: 'A fairly long question prompt that should wrap on small phones?',
    options: ['Option one is long-ish', 'Two', 'Three', 'Four'],
    correctIndices: [0, 1],
    explanation: 'Because.',
  ),
  Question(
    id: 'b',
    type: QuestionType.shortAnswer,
    prompt: 'Short?',
    answerText: 'Answer',
  ),
];

/// Renders every screen at phone and desktop sizes; layout overflows fail
/// the test.
void main() {
  for (final size in const [Size(360, 740), Size(1440, 900)]) {
    testWidgets('screens lay out at ${size.width}x${size.height}', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final env = TestEnv()
        ..subjects.add(subject('s1', 'Subject'))
        ..quizzes.add(
          quiz(
            'q1',
            _questions,
            title: 'A quiz with a reasonably long title',
          ).copyWith(
            source: const QuizSource(
              provider: 'openai',
              model: 'gpt',
              contextText: 'ctx',
            ),
          ),
        );
      await env.attempts.save(
        QuizAttempt(
          id: 'at1',
          quizId: 'q1',
          ownerId: userId,
          score: 1,
          total: 2,
          startedAt: fixedNow,
          completedAt: fixedNow,
          createdAt: fixedNow,
          updatedAt: fixedNow,
        ),
      );

      for (final location in [
        '/quizzes/q1',
        '/quizzes/q1/edit',
        '/quizzes/q1/play',
        '/ai/generate?kind=quiz',
        '/ai/generate?kind=note&subjectId=s1',
      ]) {
        await tester.pumpWidget(env.app(location), duration: Duration.zero);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: location);
        await tester.pumpWidget(const SizedBox());
      }

      // Question editor dialog.
      await tester.pumpWidget(env.app('/quizzes/q1/edit'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Edit question').first);
      await tester.pumpAndSettle();
      expect(find.text('Edit question'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());

      // AI note preview.
      await tester.pumpWidget(env.app('/ai/generate?kind=note&subjectId=s1'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('ai-context')), 'text');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('ai-generate')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ai-generate')));
      await tester.pumpAndSettle();
      expect(find.text('Review note'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());

      // AI quiz preview.
      await tester.pumpWidget(env.app('/ai/generate?kind=quiz&subjectId=s1'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('ai-context')), 'text');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('ai-generate')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ai-generate')));
      await tester.pumpAndSettle();
      expect(find.text('Review quiz'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());

      // Play through the question pages too.
      await tester.pumpWidget(env.app('/quizzes/q1/play'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('start-quiz')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('option-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('primary-action')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('primary-action')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('primary-action')));
      await tester.pumpAndSettle();
      expect(find.text('I got it'), findsOneWidget);
      await tester.tap(find.text('I got it'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('primary-action')));
      await tester.pumpAndSettle();
      expect(find.text('50%'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
