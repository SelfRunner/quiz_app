import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/data/models/models.dart';
import 'package:quiz_app/features/ai_generate/domain/deck_generation.dart';

import '../decks/support/deck_fakes.dart';
import '../quizzes/support/fakes.dart';

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  group('validateDeckDraft', () {
    test('normalizes, drops unusable and duplicate cards, caps the count', () {
      final r = validateDeckDraft({
        'title': '  Cells ',
        'description': '',
        'cards': [
          {'front': ' Q1 ', 'back': ' A1 ', 'hint': ' '},
          {'front': 'Q1', 'back': 'A1', 'hint': null}, // duplicate
          {'front': '', 'back': 'x', 'hint': null}, // no front
          'junk',
          {'front': 'Q2', 'back': 'A2', 'hint': 'h'},
          {'front': 'Q3', 'back': 'A3', 'hint': null},
        ],
      }, maxCards: 2);
      expect(r.isValid, isTrue);
      final d = r.value!;
      expect(d.title, 'Cells');
      expect(d.description, isNull);
      expect(d.cards.map((c) => (c.front, c.back, c.hint)), [
        ('Q1', 'A1', null),
        ('Q2', 'A2', 'h'),
      ]);
    });

    test('fails without a title or usable cards', () {
      final r = validateDeckDraft({
        'title': '',
        'cards': [
          {'front': 'Q', 'back': ''},
        ],
      });
      expect(r.isValid, isFalse);
      expect(r.errors, hasLength(2));
    });

    test('request carries count, style, schema', () {
      final req = deckGenerationRequest(
        sources: const [],
        count: 12,
        style: DeckCardStyle.cloze,
        language: 'de',
      );
      expect(req.task, contains('exactly 12 cards'));
      expect(req.task, contains('Cloze deletion'));
      expect(req.schemaName, 'DeckDraft');
      expect(req.schema['required'], ['title', 'description', 'cards']);
      expect(req.language, 'de');
    });
  });

  testWidgets('deck: sources + options -> editable preview -> save', (
    tester,
  ) async {
    _tall(tester);
    final env = DeckTestEnv();
    env.subjects.add(subject('s1', 'Biology'));
    await tester.pumpWidget(env.deckApp('/ai/generate?kind=deck&subjectId=s1'));
    await tester.pumpAndSettle();

    expect(find.text('Generate flashcards with AI'), findsOneWidget);
    expect(find.text('Card style'), findsOneWidget);
    expect(find.byKey(const Key('ai-card-count')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('ai-card-count'))).data,
      '$defaultDeckCards',
    );

    // Sources are required.
    await _tap(tester, find.byKey(const Key('ai-generate')));
    expect(find.byKey(const Key('ai-source-error')), findsOneWidget);
    expect(env.deckAi.structuredRequests, isEmpty);

    await tester.enterText(
      find.byKey(const Key('ai-context')),
      'Mitochondria produce ATP. The nucleus holds DNA.',
    );
    await _tap(tester, find.text('Cloze'));
    await tester.enterText(find.byKey(const Key('ai-language')), 'English');
    await tester.enterText(
      find.byKey(const Key('ai-instructions')),
      'Organelles only',
    );
    await _tap(tester, find.byKey(const Key('ai-generate')));

    final req = env.deckAi.structuredRequests.single;
    expect(req.task, contains('exactly $defaultDeckCards cards'));
    expect(req.task, contains(DeckCardStyle.cloze.instruction));
    expect(req.language, 'English');
    expect(req.extraInstructions, 'Organelles only');
    expect(req.topic, 'Biology');
    expect(req.model, 'gpt-test');
    expect(req.sources, hasLength(1));

    // Preview: editable cards.
    expect(find.text('Review deck'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('draft-title')))
          .controller!
          .text,
      'Cells',
    );
    final fronts = find.byWidgetPredicate(
      (w) =>
          w is TextField &&
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('card-front-'),
    );
    expect(fronts, findsNWidgets(2));
    await tester.enterText(fronts.first, 'What is the powerhouse of the cell?');
    await _tap(tester, find.byKey(const Key('add-card')));
    // A half-filled new card blocks saving.
    await tester.enterText(fronts.last, 'Ribosome?');
    await tester.pump();
    await _tap(tester, find.byKey(const Key('ai-save')));
    expect(env.decks.created, isEmpty);
    expect(find.text('The back is empty.'), findsOneWidget);
    await tester.enterText(fronts.last, '');
    await tester.pump();

    await _tap(tester, find.byKey(const Key('ai-save')));
    final saved = env.decks.created.single;
    expect(saved.subjectId, 's1');
    expect(saved.noteId, isNull);
    expect(saved.title, 'Cells');
    expect(saved.description, 'Cell biology basics');
    expect(saved.cards.map((c) => (c.front, c.back, c.hint)), [
      ('What is the powerhouse of the cell?', 'Mitochondria', null),
      ('Control center of the cell?', 'Nucleus', 'N…'),
    ]);
    expect(saved.cards.map((c) => c.id).toSet(), hasLength(2));
    expect(saved.source?.provider, 'openai');
    expect(saved.source?.model, 'gpt-test');
    expect(saved.source?.contextText, startsWith('Mitochondria produce ATP'));

    // Lands on the new deck.
    expect(find.text('Deck saved'), findsOneWidget);
    expect(find.byKey(const Key('study-deck')), findsOneWidget);
  });

  testWidgets('deck for a note: note preselected, saved with note + refs', (
    tester,
  ) async {
    _tall(tester);
    final env = DeckTestEnv();
    env.subjects.add(subject('s1', 'Biology'));
    env.notes.add(
      Note(
        id: 'n1',
        subjectId: 's1',
        ownerId: userId,
        title: 'Organelles',
        contentMd: 'Mitochondria produce ATP.',
        createdAt: fixedNow,
        updatedAt: fixedNow,
      ),
    );
    await tester.pumpWidget(
      env.deckApp('/ai/generate?kind=deck&subjectId=s1&noteId=n1'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Flashcards for the note "Organelles"'), findsOneWidget);
    expect(find.byKey(const ValueKey('note-chip-n1')), findsOneWidget);

    await _tap(tester, find.byKey(const Key('ai-generate')));
    expect(env.deckAi.structuredRequests.single.topic, 'Organelles');
    await _tap(tester, find.byKey(const Key('ai-save')));
    final saved = env.decks.created.single;
    expect(saved.noteId, 'n1');
    expect(saved.source?.notes, const [
      QuizSourceRef(id: 'n1', name: 'Organelles'),
    ]);
  });

  testWidgets('invalid AI output shows an error and keeps the form', (
    tester,
  ) async {
    _tall(tester);
    final env = DeckTestEnv();
    env.subjects.add(subject('s1', 'Biology'));
    env.deckAi.deckJson = {
      'title': 'x',
      'description': null,
      'cards': <Object?>[],
    };
    await tester.pumpWidget(env.deckApp('/ai/generate?kind=deck&subjectId=s1'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('ai-context')), 'Some text');
    await _tap(tester, find.byKey(const Key('ai-generate')));
    expect(find.byKey(const Key('ai-generate')), findsOneWidget);
    expect(env.decks.created, isEmpty);
    expect(find.text('Review deck'), findsNothing);
  });
}
