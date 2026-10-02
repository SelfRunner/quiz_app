import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/data/models/models.dart';
import 'package:quiz_app/features/quizzes/widgets/question_list_editor.dart';
import 'package:quiz_app/features/quizzes/widgets/quiz_list_section.dart';

import 'support/fakes.dart';

const _q1 = Question(
  id: 'a',
  type: QuestionType.mcqSingle,
  prompt: 'First?',
  options: ['x', 'y'],
  correctIndices: [0],
);
const _q2 = Question(
  id: 'b',
  type: QuestionType.trueFalse,
  prompt: 'Second?',
  options: ['True', 'False'],
  correctIndices: [1],
);

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

QuizAttempt _attempt(String id, String quizId, double score, int minutesAgo) {
  final t = fixedNow.subtract(Duration(minutes: minutesAgo));
  return QuizAttempt(
    id: id,
    quizId: quizId,
    ownerId: userId,
    score: score,
    total: 5,
    startedAt: t.subtract(const Duration(minutes: 2)),
    completedAt: t,
    createdAt: t,
    updatedAt: t,
  );
}

void main() {
  testWidgets('QuizListSection lists all quizzes of the subject (note '
      'quizzes labeled, after subject-level ones) and creates a new quiz', (
    tester,
  ) async {
    _tall(tester);
    final env = TestEnv();
    env.quizzes
      ..add(quiz('q1', [_q1, _q2], title: 'Subject quiz'))
      ..add(quiz('q2', [_q1], title: 'Note quiz', noteId: 'n1'))
      ..add(quiz('q3', [_q1], title: 'Other subject', subjectId: 's2'));
    env.notes.add(
      Note(
        id: 'n1',
        subjectId: 's1',
        ownerId: userId,
        title: 'Lecture 1',
        createdAt: fixedNow,
        updatedAt: fixedNow,
      ),
    );
    await env.attempts.save(_attempt('a1', 'q1', 4, 10)); // 80%
    await env.attempts.save(_attempt('a2', 'q1', 3, 5)); // 60%, latest
    await tester.pumpWidget(
      env.app(
        '/',
        home: const Scaffold(
          body: SingleChildScrollView(child: QuizListSection(subjectId: 's1')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Subject quiz'), findsOneWidget);
    expect(find.text('Note quiz'), findsOneWidget);
    expect(find.text('Other subject'), findsNothing);
    expect(find.text('2 questions · Best 80% · Last 60%'), findsOneWidget);
    expect(
      find.textContaining('From note: Lecture 1 · 1 question'),
      findsOneWidget,
    );
    // Subject-level quizzes first.
    expect(
      tester.getTopLeft(find.text('Subject quiz')).dy,
      lessThan(tester.getTopLeft(find.text('Note quiz')).dy),
    );
    await tester.tap(find.text('Note quiz'));
    await tester.pumpAndSettle();
    expect(find.text('Practice mistakes (1)'), findsNothing);
    expect(find.byKey(const Key('exam-quiz')), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Generate with AI'), findsOneWidget);

    await tester.tap(find.text('New quiz'));
    await tester.pumpAndSettle();
    expect(find.text('Edit quiz'), findsOneWidget);
    expect(
      env.quizzes.all.where((q) => q.title == 'Untitled quiz'),
      hasLength(1),
    );
  });

  testWidgets('QuizListSection read-only hides create actions; note filter', (
    tester,
  ) async {
    final env = TestEnv();
    env.quizzes
      ..add(quiz('q1', [_q1], title: 'Subject quiz'))
      ..add(quiz('q2', [_q1], title: 'Note quiz', noteId: 'n1'));
    await tester.pumpWidget(
      env.app(
        '/',
        home: const Scaffold(
          body: QuizListSection(subjectId: 's1', noteId: 'n1', readOnly: true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Note quiz'), findsOneWidget);
    expect(find.text('Subject quiz'), findsNothing);
    expect(find.text('New quiz'), findsNothing);
    expect(find.text('Generate with AI'), findsNothing);
  });

  testWidgets('QuizDetailScreen shows info and history; delete', (
    tester,
  ) async {
    _tall(tester);
    final env = TestEnv();
    env.subjects.add(subject('s1', 'Physics'));
    env.quizzes.add(
      quiz('q1', [_q1, _q2], title: 'Mechanics').copyWith(
        source: const QuizSource(
          provider: 'gemini',
          model: 'gemini-x',
          youtubeUrl: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
          contextText: 'Newton laws',
        ),
      ),
    );
    await env.attempts.save(_attempt('a1', 'q1', 2, 10)); // 40%
    await env.attempts.save(_attempt('a2', 'q1', 5, 5)); // 100%
    await tester.pumpWidget(env.app('/quizzes/q1'));
    await tester.pumpAndSettle();

    expect(find.text('Mechanics'), findsWidgets);
    expect(find.text('Physics'), findsOneWidget);
    expect(find.text('Single choice · 1'), findsOneWidget);
    expect(find.text('True / False · 1'), findsOneWidget);
    expect(find.text('+60% vs previous'), findsOneWidget);
    expect(find.text('5 of 5 correct · 2m 0s'), findsOneWidget);
    expect(
      find.text('Generated with Google Gemini · gemini-x'),
      findsOneWidget,
    );
    expect(find.text('Newton laws'), findsOneWidget);
    expect(find.byTooltip('Share'), findsOneWidget);

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete quiz'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(env.quizzes.all, isEmpty);
    expect(find.text('Subject s1'), findsOneWidget);
  });

  testWidgets('QuizDetailScreen for a shared quiz hides owner actions', (
    tester,
  ) async {
    final env = TestEnv();
    env.quizzes.add(quiz('q1', [_q1], owner: 'someone-else'));
    await tester.pumpWidget(env.app('/quizzes/q1'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Share'), findsNothing);
    expect(find.byTooltip('Edit'), findsNothing);
    expect(find.byKey(const Key('play-quiz')), findsOneWidget);
  });

  testWidgets('QuizEditScreen edits, validates and saves', (tester) async {
    _tall(tester);
    final env = TestEnv();
    env.quizzes.add(
      quiz('q1', [
        _q1,
        _q2.copyWith(prompt: ''), // invalid
      ], title: 'Old'),
    );
    await tester.pumpWidget(env.app('/quizzes/q1/edit'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('quiz-title')), 'New title');
    await tester.pump();
    await tester.tap(find.byKey(const Key('save-quiz')));
    await tester.pumpAndSettle();
    expect(find.text('Enter the question text.'), findsOneWidget);
    expect(env.quizzes.updates, isEmpty);

    // Fix the invalid question via its editor.
    await tester.tap(find.byTooltip('Edit question').at(1));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('question-prompt')),
      'Fixed statement',
    );
    await tester.tap(find.byKey(const Key('question-editor-save')));
    await tester.pumpAndSettle();

    // Duplicate the first question.
    await tester.tap(find.byTooltip('More actions').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Duplicate'));
    await tester.pumpAndSettle();
    expect(find.byType(QuestionCard), findsNWidgets(3));

    await tester.tap(find.byKey(const Key('save-quiz')));
    await tester.pumpAndSettle();
    final saved = env.quizzes.updates.single;
    expect(saved.title, 'New title');
    expect(saved.questions.map((q) => q.prompt), [
      'First?',
      'First?',
      'Fixed statement',
    ]);
    expect(saved.questions[0].id, isNot(saved.questions[1].id));
  });

  testWidgets('QuizEditScreen guards unsaved changes', (tester) async {
    final env = TestEnv();
    env.quizzes.add(quiz('q1', [_q1]));
    await tester.pumpWidget(env.app('/quizzes/q1'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('quiz-title')), 'Changed');
    await tester.pump();

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Unsaved changes'), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.text('Edit quiz'), findsNothing);
    expect(env.quizzes.updates, isEmpty);
  });
}
