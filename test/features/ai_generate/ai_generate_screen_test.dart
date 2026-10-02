import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/core/errors/app_exception.dart';
import 'package:quiz_app/data/models/models.dart';

import '../quizzes/support/fakes.dart';

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Note _note() => Note(
  id: 'n1',
  subjectId: 's1',
  ownerId: userId,
  title: 'Cells',
  contentMd: 'Mitochondria are the powerhouse of the cell.',
  createdAt: fixedNow,
  updatedAt: fixedNow,
);

void main() {
  testWidgets('quiz: generate -> progress -> edit preview -> save', (
    tester,
  ) async {
    _tall(tester);
    final env = TestEnv()..subjects.add(subject('s1', 'Astronomy'));
    final pending = Completer<QuizDraft>();
    env.ai.onQuiz = (_) => pending.future;
    await tester.pumpWidget(env.app('/ai/generate?kind=quiz&subjectId=s1'));
    await tester.pumpAndSettle();

    expect(find.text('Using OpenAI'), findsOneWidget);
    expect(find.text('gpt-test'), findsOneWidget);
    expect(find.text('Astronomy'), findsWidgets);

    // Validation: needs some source material.
    await tester.tap(find.byKey(const Key('ai-generate')));
    await tester.pumpAndSettle();
    expect(
      find.text('Paste some text or add a YouTube link to generate from.'),
      findsOneWidget,
    );
    expect(env.ai.quizRequests, isEmpty);

    await tester.enterText(
      find.byKey(const Key('ai-context')),
      'The solar system has eight planets.',
    );
    await tester.enterText(find.byKey(const Key('ai-youtube')), 'not a link');
    await tester.pump();
    expect(
      find.text("That doesn't look like a YouTube video link."),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const Key('ai-youtube')),
      'https://youtu.be/dQw4w9WgXcQ',
    );
    await tester.tap(find.text('Short answer'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('ai-generate')));
    await tester.pump();

    expect(find.text('Generating your quiz…'), findsOneWidget);
    final request = env.ai.quizRequests.single;
    expect(request.contextText, 'The solar system has eight planets.');
    expect(request.youtubeUrl, 'https://www.youtube.com/watch?v=dQw4w9WgXcQ');
    expect(request.questionTypes, isNot(contains(QuestionType.shortAnswer)));
    expect(request.topic, 'Astronomy');
    expect(request.model, 'gpt-test');

    pending.complete(sampleDraft);
    await tester.pumpAndSettle();
    expect(find.text('Review quiz'), findsOneWidget);
    expect(find.text('Largest planet?'), findsOneWidget);
    expect(find.text('Pluto is a planet.'), findsOneWidget);

    // Edit: rename, delete the second question.
    await tester.enterText(find.byKey(const Key('draft-title')), 'My planets');
    await tester.tap(find.byTooltip('More actions').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Pluto is a planet.'), findsNothing);

    await tester.tap(find.byKey(const Key('ai-save')));
    await tester.pumpAndSettle();

    final saved = env.quizzes.all.single;
    expect(saved.title, 'My planets');
    expect(saved.subjectId, 's1');
    expect(saved.noteId, isNull);
    expect(saved.questions.map((q) => q.prompt), ['Largest planet?']);
    expect(saved.source!.provider, 'openai');
    expect(saved.source!.model, 'gpt-test');
    expect(saved.source!.contextText, 'The solar system has eight planets.');
    expect(
      saved.source!.youtubeUrl,
      'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
    );
    // Navigated to the new quiz.
    expect(find.byKey(const Key('play-quiz')), findsOneWidget);
  });

  testWidgets('quiz: cancel returns to the form and ignores the result', (
    tester,
  ) async {
    _tall(tester);
    final env = TestEnv()..subjects.add(subject('s1', 'Astronomy'));
    final pending = Completer<QuizDraft>();
    env.ai.onQuiz = (_) => pending.future;
    await tester.pumpWidget(env.app('/ai/generate?kind=quiz&subjectId=s1'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('ai-context')), 'text');
    await tester.tap(find.byKey(const Key('ai-generate')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('ai-cancel')));
    await tester.pump();
    pending.complete(sampleDraft);
    await tester.pumpAndSettle();
    expect(find.text('Generate quiz with AI'), findsOneWidget);
    expect(find.text('Largest planet?'), findsNothing);
  });

  testWidgets('quiz for a note: prefilled context, regenerate a question', (
    tester,
  ) async {
    _tall(tester);
    final env = TestEnv()..notes.add(_note());
    var call = 0;
    env.ai.onQuiz = (r) async {
      call++;
      if (call == 1) return sampleDraft;
      return const QuizDraft(
        title: 'x',
        questions: [
          QuestionDraft(
            type: QuestionType.mcqSingle,
            prompt: 'Smallest planet?',
            options: ['Mercury', 'Earth'],
            correctIndices: [0],
          ),
        ],
      );
    };
    await tester.pumpWidget(env.app('/ai/generate?kind=quiz&noteId=n1'));
    await tester.pumpAndSettle();
    expect(
      find.text('Mitochondria are the powerhouse of the cell.'),
      findsOneWidget,
    );
    expect(find.text('Quiz for the note "Cells"'), findsOneWidget);

    await tester.tap(find.byKey(const Key('ai-generate')));
    await tester.pumpAndSettle();
    expect(env.ai.quizRequests.first.topic, 'Cells');

    await tester.tap(find.byTooltip('More actions').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Regenerate'));
    await tester.pumpAndSettle();
    final regen = env.ai.quizRequests.last;
    expect(regen.questionCount, 1);
    expect(regen.questionTypes, {QuestionType.mcqSingle});
    expect(regen.extraInstructions, contains('Largest planet?'));
    expect(find.text('Smallest planet?'), findsOneWidget);
    expect(find.text('Largest planet?'), findsNothing);

    await tester.tap(find.byKey(const Key('ai-save')));
    await tester.pumpAndSettle();
    final saved = env.quizzes.all.single;
    expect(saved.noteId, 'n1');
    expect(saved.subjectId, 's1');
    expect(saved.questions.first.prompt, 'Smallest planet?');
  });

  testWidgets('note: generate -> markdown preview -> save -> note editor', (
    tester,
  ) async {
    _tall(tester);
    final env = TestEnv()
      ..subjects.add(subject('s1', 'Biology'))
      ..subjects.add(subject('s2', 'History'));
    env.ai.onNote = (_) async => const NoteDraft(
      title: 'Cell notes',
      contentMarkdown: '# Cells\n\nThey are small.',
    );
    await tester.pumpWidget(env.app('/ai/generate?kind=note'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('ai-context')), 'Cells...');
    await tester.tap(find.byKey(const Key('ai-generate')));
    await tester.pumpAndSettle();
    expect(find.text('Choose where to save the result.'), findsOneWidget);
    expect(env.ai.noteRequests, isEmpty);

    await tester.tap(find.byKey(const Key('ai-subject')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('History').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ai-generate')));
    await tester.pumpAndSettle();

    expect(find.text('Review note'), findsOneWidget);
    await tester.tap(find.text('Preview'));
    await tester.pumpAndSettle();
    expect(find.text('They are small.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('ai-save')));
    await tester.pumpAndSettle();
    final note = env.notes.created.single;
    expect(note.subjectId, 's2');
    expect(note.title, 'Cell notes');
    expect(note.contentMd, '# Cells\n\nThey are small.');
    expect(find.text('Note editor ${note.id}'), findsOneWidget);
  });

  testWidgets('errors are mapped to friendly messages with actions', (
    tester,
  ) async {
    _tall(tester);
    final env = TestEnv()..subjects.add(subject('s1', 'Astronomy'));
    env.ai.onQuiz = (_) async => throw const AiException(
      'Invalid API key (401).',
      kind: AiErrorKind.invalidApiKey,
    );
    await tester.pumpWidget(env.app('/ai/generate?kind=quiz&subjectId=s1'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('ai-context')), 'text');
    await tester.tap(find.byKey(const Key('ai-generate')));
    await tester.pumpAndSettle();

    expect(find.text('The API key was rejected'), findsOneWidget);
    expect(find.text('Invalid API key (401).'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);

    // Rate limits offer retry.
    env.ai.onQuiz = (_) async => throw const AiException(
      'Too many requests',
      kind: AiErrorKind.rateLimited,
    );
    await tester.tap(find.byKey(const Key('ai-generate')));
    await tester.pumpAndSettle();
    expect(find.text('Rate limit or quota reached'), findsOneWidget);
    env.ai.onQuiz = null; // next call succeeds
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Review quiz'), findsOneWidget);
  });

  testWidgets('no provider configured links to settings', (tester) async {
    _tall(tester);
    final env = TestEnv()..subjects.add(subject('s1', 'Astronomy'));
    env.ai.selection = null;
    await tester.pumpWidget(env.app('/ai/generate?kind=quiz&subjectId=s1'));
    await tester.pumpAndSettle();
    expect(find.text('No AI provider set up'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('ai-generate')))
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Open settings'));
    await tester.pumpAndSettle();
    expect(find.text('Settings page'), findsOneWidget);
  });
}
