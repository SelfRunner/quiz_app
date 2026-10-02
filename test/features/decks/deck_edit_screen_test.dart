import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../quizzes/support/fakes.dart';
import 'support/deck_fakes.dart';

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Opens the editor on top of the deck screen (so leaving can pop).
Future<DeckTestEnv> _open(WidgetTester tester) async {
  _tall(tester);
  final env = DeckTestEnv();
  env.subjects.add(subject('s1', 'Biology'));
  env.decks.put(
    deck('d1', [
      card('c1', 'Mitochondria', 'Powerhouse'),
      card('c2', 'Nucleus', 'Control center', hint: 'N'),
    ], title: 'Cells'),
  );
  await tester.pumpWidget(env.deckApp('/decks/d1'));
  await tester.pumpAndSettle();
  await _tap(tester, find.byKey(const Key('edit-deck')));
  expect(find.text('Edit deck'), findsOneWidget);
  return env;
}

void main() {
  testWidgets('edit, add, bulk add, duplicate, delete + undo, save', (
    tester,
  ) async {
    final env = await _open(tester);
    expect(find.byKey(const Key('save-deck')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('deck-title')), 'Cell parts');
    await tester.enterText(
      find.byKey(const ValueKey('card-back-c1')),
      'Makes ATP',
    );

    // Add a card by hand.
    await _tap(tester, find.byKey(const Key('add-card')));
    final fronts = find.byWidgetPredicate(
      (w) =>
          w is TextField &&
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('card-front-'),
    );
    expect(fronts, findsNWidgets(3));
    final newFront = tester.widget<TextField>(fronts.last);
    final newId = (newFront.key! as ValueKey<String>).value.substring(
      'card-front-'.length,
    );
    await tester.enterText(fronts.last, 'Ribosome');
    await tester.enterText(
      find.byKey(ValueKey('card-back-$newId')),
      'Makes proteins',
    );

    // Bulk add: two valid lines, one invalid.
    await _tap(tester, find.byKey(const Key('bulk-add-cards')));
    await tester.enterText(
      find.byKey(const Key('bulk-text')),
      'Golgi :: Packaging\nnot a card\nLysosome :: Digestion :: Recycling',
    );
    await tester.pump();
    expect(
      find.text('2 cards · line 2 skipped (need front :: back)'),
      findsOneWidget,
    );
    await _tap(tester, find.byKey(const Key('bulk-add')));
    expect(fronts, findsNWidgets(5));
    expect(find.text('Added 2 cards'), findsOneWidget);

    // Duplicate the first card, then delete the copy and undo, then delete.
    await _tap(tester, find.byKey(const ValueKey('card-menu-c1')));
    await _tap(tester, find.text('Duplicate'));
    expect(fronts, findsNWidgets(6));
    await _tap(tester, find.byKey(const ValueKey('card-menu-c2')));
    await _tap(tester, find.text('Delete'));
    expect(fronts, findsNWidgets(5));
    expect(find.byKey(const ValueKey('card-front-c2')), findsNothing);
    await _tap(tester, find.text('Undo'));
    expect(find.byKey(const ValueKey('card-front-c2')), findsOneWidget);

    // Remove the hint of c2.
    expect(find.byKey(const ValueKey('card-hint-c2')), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('card-hint-toggle-c2')));
    expect(find.byKey(const ValueKey('card-hint-c2')), findsNothing);

    await _tap(tester, find.byKey(const Key('save-deck')));
    final saved = env.decks.updates.last;
    expect(saved.title, 'Cell parts');
    expect(saved.cards.map((c) => c.front), [
      'Mitochondria',
      'Mitochondria',
      'Nucleus',
      'Ribosome',
      'Golgi',
      'Lysosome',
    ]);
    // Existing ids are kept, new cards get fresh unique ids.
    expect(saved.cards[0].id, 'c1');
    expect(saved.cards[2].id, 'c2');
    expect(saved.cards.map((c) => c.id).toSet(), hasLength(6));
    expect(saved.cards[0].back, 'Makes ATP');
    expect(saved.cards[2].hint, isNull);
    expect(saved.cards[5].hint, 'Recycling');
    expect(find.text('Deck saved'), findsOneWidget);
  });

  testWidgets('half-empty cards block saving; blank cards are dropped', (
    tester,
  ) async {
    final env = await _open(tester);
    await _tap(tester, find.byKey(const Key('add-card'))); // left blank
    await tester.enterText(find.byKey(const ValueKey('card-back-c1')), ' ');
    await tester.pump();
    await _tap(tester, find.byKey(const Key('save-deck')));
    expect(env.decks.updates, isEmpty);
    expect(find.text('The back is empty.'), findsOneWidget);
    expect(
      find.text('Fill in both sides of 1 card marked in red.'),
      findsOneWidget,
    );

    await tester.enterText(find.byKey(const ValueKey('card-back-c1')), 'ATP');
    await tester.pump();
    await _tap(tester, find.byKey(const Key('save-deck')));
    expect(env.decks.updates.single.cards.map((c) => c.id), ['c1', 'c2']);
  });

  testWidgets('reorder by dragging the handle', (tester) async {
    final env = await _open(tester);
    final handles = find.byIcon(Icons.drag_indicator);
    expect(handles, findsNWidgets(2));
    final gesture = await tester.startGesture(tester.getCenter(handles.first));
    await tester.pump(const Duration(milliseconds: 100));
    for (var i = 0; i < 20; i++) {
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(const Key('save-deck')));
    expect(env.decks.updates.single.cards.map((c) => c.id), ['c2', 'c1']);
  });

  testWidgets('unsaved changes guard: keep editing or discard', (tester) async {
    final env = await _open(tester);
    await tester.enterText(find.byKey(const Key('deck-title')), 'Changed');
    await tester.pump();

    final navigator = tester.state<NavigatorState>(
      find.byType(Navigator).first,
    );
    await navigator.maybePop();
    await tester.pumpAndSettle();
    expect(find.text('Unsaved changes'), findsOneWidget);
    await _tap(tester, find.text('Keep editing'));
    expect(find.text('Edit deck'), findsOneWidget);

    await navigator.maybePop();
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(const Key('discard-changes')));
    expect(find.text('Edit deck'), findsNothing);
    expect(env.decks.updates, isEmpty);
    // Back on the deck screen, unchanged.
    expect(find.text('Cells'), findsWidgets);
  });

  testWidgets('shared decks are read-only', (tester) async {
    _tall(tester);
    final env = DeckTestEnv();
    env.decks.put(deck('d2', [card('c1', 'Q', 'A')], owner: 'other'));
    await tester.pumpWidget(env.deckApp('/decks/d2/edit'));
    await tester.pumpAndSettle();
    expect(find.text('Read-only deck'), findsOneWidget);
    expect(find.byKey(const Key('save-deck')), findsNothing);
  });
}
