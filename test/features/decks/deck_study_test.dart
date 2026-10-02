import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/study/fsrs.dart';

import '../quizzes/support/fakes.dart';
import 'support/deck_fakes.dart';

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _key(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
}

Finder _text(String key) => find.byKey(Key(key));

String _front(WidgetTester tester) =>
    tester.widget<Text>(_text('review-front')).data!;

void main() {
  testWidgets('keyboard flow: Space reveals, 1-4 rate, intervals, summary', (
    tester,
  ) async {
    _tall(tester);
    final env = DeckTestEnv();
    env.decks.put(
      deck('d1', [
        card('c1', 'Powerhouse?', 'Mitochondria'),
        card('c2', 'Control center?', 'Nucleus', hint: 'Starts with N'),
      ]),
    );
    await tester.pumpWidget(env.deckApp('/decks/d1/study'));
    await tester.pumpAndSettle();

    // Front only.
    expect(_front(tester), 'Powerhouse?');
    expect(_text('review-back'), findsNothing);
    expect(_text('rate-good'), findsNothing);
    expect(find.text('2 left'), findsOneWidget);

    await _key(tester, LogicalKeyboardKey.space);
    expect(find.text('Mitochondria'), findsOneWidget);
    // Next intervals from the scheduler preview (new card: 1m / 10m steps).
    expect(
      find.descendant(of: _text('rate-again'), matching: find.text('1m')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: _text('rate-good'), matching: find.text('10m')),
      findsOneWidget,
    );
    final easy = Fsrs().preview(
      FsrsCard.newCard(fixedNow),
      fixedNow,
    )[Rating.easy]!;
    expect(easy.state, CardState.review);

    // 4 = Easy: graduates, not shown again this session.
    await _key(tester, LogicalKeyboardKey.digit4);
    expect(env.reviews.calls.single, (
      deckId: 'd1',
      cardId: 'c1',
      rating: Rating.easy,
    ));
    expect(_front(tester), 'Control center?');

    // Hint before revealing.
    await _key(tester, LogicalKeyboardKey.keyH);
    expect(_text('review-hint'), findsOneWidget);

    // Rating keys do nothing before the answer is shown.
    await _key(tester, LogicalKeyboardKey.digit1);
    expect(env.reviews.calls, hasLength(1));

    // Enter also reveals; 1 = Again: 1-minute step, comes back at the end.
    await _key(tester, LogicalKeyboardKey.enter);
    await _key(tester, LogicalKeyboardKey.digit1);
    expect(env.reviews.calls.last.rating, Rating.again);
    expect(_front(tester), 'Control center?');
    expect(find.text('1 left'), findsOneWidget);

    // Tap the card to reveal, tap Good (10m step: comes back once more).
    await tester.tap(_text('review-front'));
    await tester.pumpAndSettle();
    await tester.tap(_text('rate-good'));
    await tester.pumpAndSettle();
    expect(env.reviews.calls.last.rating, Rating.good);
    expect(_front(tester), 'Control center?');

    // Space twice: reveal, then Space = Good -> graduates.
    await _key(tester, LogicalKeyboardKey.space);
    await _key(tester, LogicalKeyboardKey.space);
    expect(env.reviews.calls.map((c) => (c.cardId, c.rating)), [
      ('c1', Rating.easy),
      ('c2', Rating.again),
      ('c2', Rating.good),
      ('c2', Rating.good),
    ]);
    expect(env.reviews.rows['d1/c2']!.state, CardState.review);

    expect(_text('review-summary'), findsOneWidget);
    expect(find.text('Session complete'), findsOneWidget);
    expect(find.textContaining('2 cards · 4 reviews'), findsOneWidget);
    expect(tester.widget<Text>(_text('summary-good')).data, '2');
    expect(tester.widget<Text>(_text('summary-again')).data, '1');
  });

  testWidgets('shared decks can be studied; caught-up state afterwards', (
    tester,
  ) async {
    _tall(tester);
    final env = DeckTestEnv();
    env.decks.put(deck('d2', [card('c1', 'Q1', 'A1')], owner: 'someone-else'));
    await tester.pumpWidget(env.deckApp('/decks/d2/study'));
    await tester.pumpAndSettle();
    await _key(tester, LogicalKeyboardKey.space);
    await _key(tester, LogicalKeyboardKey.digit4);
    expect(env.reviews.calls.single.deckId, 'd2');
    expect(find.text('Session complete'), findsOneWidget);

    // Re-opening: nothing due.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(env.deckApp('/decks/d2/study'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('deck-caught-up')), findsOneWidget);
    expect(find.text('All caught up'), findsOneWidget);
  });

  testWidgets('a card deleted mid-session is skipped', (tester) async {
    _tall(tester);
    final env = DeckTestEnv();
    final d = env.decks.put(
      deck('d1', [card('c1', 'Q1', 'A1'), card('c2', 'Q2', 'A2')]),
    );
    await tester.pumpWidget(env.deckApp('/decks/d1/study'));
    await tester.pumpAndSettle();
    env.decks.put(d.copyWith(cards: [d.cards[1]]));
    await tester.pumpAndSettle();
    await _key(tester, LogicalKeyboardKey.space);
    await _key(tester, LogicalKeyboardKey.digit3);
    expect(find.text('This card no longer exists — skipped.'), findsOneWidget);
    expect(_front(tester), 'Q2');
    expect(env.reviews.calls, isEmpty);
  });
}
