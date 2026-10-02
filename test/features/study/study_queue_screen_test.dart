import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/data/models/models.dart';
import 'package:quiz_app/features/decks/domain/queue_groups.dart';
import 'package:quiz_app/study/due_queue.dart';

import '../decks/support/deck_fakes.dart';
import '../quizzes/support/fakes.dart';

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

CardReview _review(
  String deckId,
  String cardId, {
  required Duration dueIn,
  CardState state = CardState.review,
}) => CardReview(
  id: '$deckId-$cardId',
  ownerId: userId,
  deckId: deckId,
  cardId: cardId,
  state: state,
  dueAt: fixedNow.add(dueIn),
  stability: 5,
  difficulty: 5,
  scheduledDays: 5,
  reps: 3,
  lastReviewAt: fixedNow.subtract(const Duration(days: 5)),
  createdAt: fixedNow.subtract(const Duration(days: 10)),
  updatedAt: fixedNow,
);

/// Two subjects; s1 has two decks, s2 one (shared).
DeckTestEnv _env() {
  final env = DeckTestEnv();
  env.subjects
    ..add(subject('s1', 'Biology'))
    ..add(subject('s2', 'History'));
  env.decks
    ..put(
      deck(
        'd1',
        [card('a1', 'Cell?', 'Unit of life'), card('a2', 'DNA?', 'Genes')],
        title: 'Cells',
        createdAt: fixedNow.subtract(const Duration(days: 3)),
      ),
    )
    ..put(
      deck(
        'd2',
        [card('b1', 'Organ?', 'Tissue group')],
        title: 'Anatomy',
        createdAt: fixedNow.subtract(const Duration(days: 2)),
      ),
    )
    ..put(
      deck(
        'd3',
        [card('h1', '1066?', 'Hastings'), card('h2', '1492?', 'Columbus')],
        title: 'Dates',
        subjectId: 's2',
        owner: 'alice',
        createdAt: fixedNow.subtract(const Duration(days: 1)),
      ),
    );
  env.reviews
    // d1: a1 due now; a2 new.
    ..put(_review('d1', 'a1', dueIn: const Duration(hours: -2)))
    // d2: b1 due later today (learning step).
    ..put(
      _review(
        'd2',
        'b1',
        dueIn: const Duration(minutes: 30),
        state: CardState.learning,
      ),
    )
    // d3: h1 due now, h2 due in a week.
    ..put(_review('d3', 'h1', dueIn: const Duration(minutes: -5)))
    ..put(_review('d3', 'h2', dueIn: const Duration(days: 7)));
  return env;
}

void main() {
  test('groupDueQueue groups by subject then deck, keeping study order', () {
    final env = _env();
    final groups = groupDueQueue(env.reviews.queue());
    expect(groups.map((g) => g.subjectId), ['s1', 's2']);
    final s1 = groups.first;
    expect(s1.decks.map((d) => d.deck.id), ['d1', 'd2']);
    expect(s1.decks[0].due.map((c) => c.card.id), ['a1']);
    expect(s1.decks[0].fresh.map((c) => c.card.id), ['a2']);
    expect(s1.decks[1].later.map((c) => c.card.id), ['b1']);
    expect((s1.dueCount, s1.newCount, s1.laterCount), (1, 1, 1));
    final s2 = groups.last;
    expect(s2.decks.single.due.map((c) => c.card.id), ['h1']);
    expect(s2.decks.single.now.length, 1);
    expect(groupDueQueue(const DueQueue()), isEmpty);
  });

  testWidgets('queue grouped by subject/deck; Study all runs merged queue', (
    tester,
  ) async {
    _tall(tester);
    final env = _env();
    await tester.pumpWidget(env.deckApp('/study'));
    await tester.pumpAndSettle();

    expect(find.text('3 cards'), findsOneWidget); // a1, h1 due + a2 new
    expect(find.text('2 reviews · 1 new card · 1 later today'), findsOneWidget);
    final bio = find.byKey(const ValueKey('study-subject-s1'));
    expect(
      find.descendant(of: bio, matching: find.text('Biology')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: bio, matching: find.text('1 due · 1 new · 1 later')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: bio, matching: find.text('Cells')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: bio, matching: find.text('Anatomy')),
      findsOneWidget,
    );
    final hist = find.byKey(const ValueKey('study-subject-s2'));
    expect(
      find.descendant(of: hist, matching: find.text('Dates')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: hist, matching: find.text('1 due')),
      findsNWidgets(2),
    ); // subject + deck row

    await tester.tap(find.byKey(const Key('study-all')));
    await tester.pumpAndSettle();
    // Reviews first (oldest due first), then new cards; deck title shown.
    final seen = <String>[];
    for (var i = 0; i < 3; i++) {
      seen.add(
        tester.widget<Text>(find.byKey(const Key('review-front'))).data!,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.digit4);
      await tester.pumpAndSettle();
    }
    expect(seen, ['Cell?', '1066?', 'DNA?']);
    expect(env.reviews.calls.map((c) => c.deckId), ['d1', 'd3', 'd1']);
    expect(find.text('Session complete'), findsOneWidget);

    await tester.tap(find.byKey(const Key('review-done')));
    await tester.pumpAndSettle();
    // Only the later-today card is left.
    expect(find.text('Nothing due right now'), findsOneWidget);
    expect(find.byKey(const Key('study-ahead')), findsOneWidget);
  });

  testWidgets('new-card limit is respected and can be changed', (tester) async {
    _tall(tester);
    final env = DeckTestEnv();
    env.subjects.add(subject('s1', 'Biology'));
    env.decks.put(
      deck('d1', [
        card('c1', 'Q1', 'A1'),
        card('c2', 'Q2', 'A2'),
        card('c3', 'Q3', 'A3'),
      ]),
    );
    env.reviews.newCardsPerDay = 2;
    await tester.pumpWidget(env.deckApp('/study'));
    await tester.pumpAndSettle();
    expect(find.text('2 cards'), findsOneWidget);
    expect(find.text('0 reviews · 2 new cards'), findsOneWidget);

    await tester.tap(find.byKey(const Key('study-all')));
    await tester.pumpAndSettle();
    for (var i = 0; i < 2; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.digit4);
      await tester.pumpAndSettle();
    }
    expect(env.reviews.calls.map((c) => c.cardId), ['c1', 'c2']);
    await tester.tap(find.byKey(const Key('review-done')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('all-caught-up')), findsOneWidget);
    expect(find.textContaining("today's limit"), findsOneWidget);

    // The dialog edits the (device) study settings.
    await tester.tap(find.byKey(const Key('study-limits')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('new-card-limit')), '50');
    await tester.tap(find.byKey(const Key('save-new-card-limit')));
    await tester.pumpAndSettle();
    expect(find.text('New cards per day'), findsNothing);
  });

  testWidgets('empty states: no decks / all caught up', (tester) async {
    _tall(tester);
    final env = DeckTestEnv();
    await tester.pumpWidget(env.deckApp('/study'));
    await tester.pumpAndSettle();
    expect(find.text('No flashcards yet'), findsOneWidget);

    final done = DeckTestEnv();
    done.decks.put(deck('d1', [card('c1', 'Q', 'A')]));
    done.reviews.put(_review('d1', 'c1', dueIn: const Duration(days: 4)));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(done.deckApp('/study'));
    await tester.pumpAndSettle();
    expect(find.text('All caught up'), findsOneWidget);
    expect(
      find.text('Nothing is due today. Come back tomorrow.'),
      findsOneWidget,
    );
  });
}
