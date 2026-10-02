import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/core/widgets/locked_feature.dart';
import 'package:quiz_app/data/models/models.dart';
import 'package:quiz_app/features/ai_generate/presentation/ai_generate_screen.dart';
import 'package:quiz_app/features/quizzes/widgets/question_list_editor.dart';
import 'package:quiz_app/features/quizzes/widgets/quiz_list_section.dart';

import 'support/fakes.dart';

const _q = Question(
  id: 'a',
  type: QuestionType.mcqSingle,
  prompt: 'First?',
  options: ['x', 'y'],
  correctIndices: [0],
);

void _size(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Widget _section(TestEnv env) => env.app(
  '/',
  home: const Scaffold(
    body: SingleChildScrollView(child: QuizListSection(subjectId: 's1')),
  ),
);

/// Host for [QuestionListEditor] with a regenerate callback.
class _EditorHost extends StatelessWidget {
  const _EditorHost({required this.onRegenerate});

  final void Function(Question q) onRegenerate;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: QuestionListEditor(
      questions: const [_q],
      onChanged: (_) {},
      newId: nextId,
      onRegenerate: onRegenerate,
    ),
  );
}

void main() {
  group('QuizListSection "Generate with AI"', () {
    testWidgets('is locked when AI is not set up and opens the setup sheet', (
      tester,
    ) async {
      _size(tester);
      final env = TestEnv()..aiReady = false;
      await tester.pumpWidget(_section(env));
      await tester.pumpAndSettle();

      final gate = find.byKey(const Key('quiz-generate-ai'));
      expect(
        find.descendant(of: gate, matching: find.byKey(LockedFeature.badgeKey)),
        findsOneWidget,
      );
      await tester.tap(find.text('Generate with AI'));
      await tester.pumpAndSettle();

      expect(find.text('Set up AI'), findsOneWidget);
      expect(
        find.text('Add an API key in Settings to use AI.'),
        findsOneWidget,
      );
      expect(find.byType(AiGenerateScreen), findsNothing);

      await tester.tap(find.text('Open Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Settings page'), findsOneWidget);
    });

    testWidgets('opens the generator when AI is ready', (tester) async {
      _size(tester);
      final env = TestEnv();
      await tester.pumpWidget(_section(env));
      await tester.pumpAndSettle();

      expect(find.byKey(LockedFeature.badgeKey), findsNothing);
      await tester.tap(find.text('Generate with AI'));
      await tester.pumpAndSettle();
      expect(find.text('Set up AI'), findsNothing);
      expect(find.byType(AiGenerateScreen), findsOneWidget);
    });
  });

  group('QuestionCard "Regenerate"', () {
    Future<List<Question>> openRegenerate(
      WidgetTester tester,
      TestEnv env,
    ) async {
      _size(tester);
      final calls = <Question>[];
      await tester.pumpWidget(
        env.app('/', home: _EditorHost(onRegenerate: calls.add)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('More actions'));
      await tester.pumpAndSettle();
      return calls;
    }

    testWidgets('shows a lock and opens the setup sheet when AI is not '
        'set up', (tester) async {
      final env = TestEnv()..aiReady = false;
      final calls = await openRegenerate(tester, env);
      final item = find.byKey(const Key('question-regenerate'));
      expect(
        find.descendant(of: item, matching: find.byKey(LockedFeature.badgeKey)),
        findsOneWidget,
      );
      await tester.tap(find.text('Regenerate'));
      await tester.pumpAndSettle();
      expect(find.text('Set up AI'), findsOneWidget);
      expect(calls, isEmpty);
    });

    testWidgets('regenerates when AI is ready', (tester) async {
      final env = TestEnv();
      final calls = await openRegenerate(tester, env);
      expect(find.byKey(LockedFeature.badgeKey), findsNothing);
      await tester.tap(find.text('Regenerate'));
      await tester.pumpAndSettle();
      expect(find.text('Set up AI'), findsNothing);
      expect(calls.single.id, 'a');
    });
  });
}
