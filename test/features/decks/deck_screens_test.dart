import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/data/models/models.dart';
import 'package:quiz_app/features/decks/widgets/deck_list_section.dart';

import '../quizzes/support/fakes.dart';
import 'support/deck_fakes.dart';

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Widget _section({String? noteId, bool readOnly = false}) => Scaffold(
  body: SingleChildScrollView(
    child: DeckListSection(subjectId: 's1', noteId: noteId, readOnly: readOnly),
  ),
);

void main() {
  group('DeckListSection', () {
    testWidgets('subject-level decks with counts; new deck opens the editor', (
      tester,
    ) async {
      _tall(tester);
      final env = DeckTestEnv();
      env.decks
        ..put(
          deck('d1', [
            card('c1', 'Q1', 'A1'),
            card('c2', 'Q2', 'A2'),
          ], title: 'Cells'),
        )
        ..put(deck('d2', const [], title: 'Note deck', noteId: 'n1'));
      env.reviews.put(
        CardReview(
          id: 'r1',
          ownerId: userId,
          deckId: 'd1',
          cardId: 'c1',
          state: CardState.review,
          dueAt: fixedNow.subtract(const Duration(hours: 1)),
          stability: 3,
          lastReviewAt: fixedNow.subtract(const Duration(days: 3)),
          createdAt: fixedNow,
          updatedAt: fixedNow,
        ),
      );
      await tester.pumpWidget(env.deckApp('/', home: _section()));
      await tester.pumpAndSettle();

      expect(find.text('Cells'), findsOneWidget);
      expect(find.text('Note deck'), findsNothing); // note-level
      expect(find.text('2 cards · 1 due · 1 new'), findsOneWidget);
      expect(find.byKey(const ValueKey('deck-study-d1')), findsOneWidget);

      await _tap(tester, find.byKey(const Key('deck-new')));
      expect(env.decks.created.single.title, 'Untitled deck');
      expect(env.decks.created.single.subjectId, 's1');
      expect(find.text('Edit deck'), findsOneWidget);
    });

    testWidgets('note decks; AI generate opens the deck generator', (
      tester,
    ) async {
      _tall(tester);
      final env = DeckTestEnv();
      env.subjects.add(subject('s1', 'Biology'));
      env.decks.put(deck('d2', const [], title: 'Note deck', noteId: 'n1'));
      await tester.pumpWidget(env.deckApp('/', home: _section(noteId: 'n1')));
      await tester.pumpAndSettle();
      expect(find.text('Note deck'), findsOneWidget);
      expect(find.text('0 cards'), findsOneWidget);
      await _tap(tester, find.text('Generate with AI'));
      expect(find.text('Generate flashcards with AI'), findsOneWidget);
    });

    testWidgets('read-only hides create and AI; AI locked when not set up', (
      tester,
    ) async {
      _tall(tester);
      final env = DeckTestEnv();
      await tester.pumpWidget(env.deckApp('/', home: _section(readOnly: true)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('deck-new')), findsNothing);
      expect(find.text('Generate with AI'), findsNothing);
      expect(find.text('No flashcard decks yet'), findsOneWidget);

      final locked = DeckTestEnv()..aiReady = false;
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(locked.deckApp('/', home: _section()));
      await tester.pumpAndSettle();
      await _tap(tester, find.byKey(const Key('deck-generate-ai')));
      expect(find.text('Set up AI'), findsOneWidget);
    });
  });

  group('DeckDetailScreen', () {
    testWidgets('stats, cards, study, delete (owner)', (tester) async {
      _tall(tester);
      final env = DeckTestEnv();
      env.subjects.add(subject('s1', 'Biology'));
      env.decks.put(
        deck('d1', [
          card('c1', 'Powerhouse?', 'Mitochondria'),
          card('c2', 'Control center?', 'Nucleus'),
          card('c3', 'Protein factory?', 'Ribosome'),
        ], title: 'Cells').copyWith(
          description: 'Organelles',
          source: const QuizSource(
            provider: 'openai',
            model: 'gpt-test',
            notes: [QuizSourceRef(id: 'n1', name: 'Lecture 1')],
          ),
        ),
      );
      await env.reviews.recordReview(
        deckId: 'd1',
        cardId: 'c1',
        rating: Rating.easy,
      );
      await tester.pumpWidget(env.deckApp('/decks/d1'));
      await tester.pumpAndSettle();

      expect(find.text('Cells'), findsWidgets);
      expect(find.text('Organelles'), findsOneWidget);
      expect(find.text('Biology'), findsOneWidget);
      final stats = find.byKey(const Key('deck-stats'));
      Finder stat(String label) =>
          find.descendant(of: stats, matching: find.text(label));
      expect(stat('Cards'), findsOneWidget);
      expect(stat('New'), findsOneWidget);
      expect(
        find.descendant(of: stats, matching: find.text('3')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: stats, matching: find.text('2')),
        findsOneWidget,
      ); // new
      expect(stat('Est. recall'), findsOneWidget);
      expect(
        find.descendant(of: stats, matching: find.text('100%')),
        findsOneWidget,
      );
      expect(find.text('Study · 2'), findsOneWidget);
      expect(find.text('Powerhouse?'), findsOneWidget);
      expect(find.textContaining('Due in'), findsOneWidget);
      expect(find.text('New'), findsNWidgets(3)); // 2 rows + stat label
      expect(find.byKey(const Key('deck-source')), findsOneWidget);
      expect(find.text('Generated with OpenAI · gpt-test'), findsOneWidget);
      expect(find.text('Lecture 1'), findsOneWidget);
      expect(find.byKey(const Key('share-deck')), findsOneWidget);

      await _tap(tester, find.byKey(const Key('study-deck')));
      expect(find.byKey(const Key('review-front')), findsOneWidget);
      await _tap(tester, find.byTooltip('Close'));

      await _tap(tester, find.byKey(const Key('deck-more')));
      await _tap(tester, find.text('Delete deck'));
      await _tap(tester, find.byKey(const Key('confirm-delete-deck')));
      expect(env.decks.rows['d1']!.deletedAt, isNotNull);
    });

    testWidgets('shared deck: copy instead of owner actions', (tester) async {
      _tall(tester);
      final env = DeckTestEnv();
      env.decks.put(deck('d1', [card('c1', 'Q', 'A')], owner: 'alice'));
      await tester.pumpWidget(env.deckApp('/decks/d1'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('share-deck')), findsNothing);
      expect(find.byKey(const Key('edit-deck')), findsNothing);
      expect(find.byTooltip('Copy to my account'), findsOneWidget);
      expect(find.text('Shared with you'), findsOneWidget);
      expect(find.text('Study · 1'), findsOneWidget);
    });

    testWidgets('missing deck', (tester) async {
      _tall(tester);
      final env = DeckTestEnv();
      await tester.pumpWidget(env.deckApp('/decks/nope'));
      await tester.pumpAndSettle();
      expect(find.text('Deck not found'), findsOneWidget);
    });
  });
}
