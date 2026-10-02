import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/data/models/models.dart';
import 'package:quiz_app/study/due_queue.dart';
import 'package:quiz_app/study/local_day.dart';

final utc = fixedOffset(Duration.zero);

Deck deck(String id, List<String> cards, {DateTime? createdAt}) => Deck(
  id: id,
  subjectId: 's',
  ownerId: 'u',
  title: id,
  cards: [for (final c in cards) Flashcard(id: c, front: c, back: c)],
  createdAt: createdAt ?? DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

CardReview review(
  String deckId,
  String cardId, {
  required DateTime due,
  CardState state = CardState.review,
  DateTime? createdAt,
  int scheduledDays = 3,
  DateTime? deletedAt,
  int lapses = 0,
}) => CardReview(
  id: '$deckId/$cardId',
  ownerId: 'u',
  deckId: deckId,
  cardId: cardId,
  state: state,
  dueAt: due,
  stability: 3,
  difficulty: 5,
  scheduledDays: scheduledDays,
  reps: 1,
  lapses: lapses,
  lastReviewAt: due.subtract(Duration(days: scheduledDays)),
  createdAt: createdAt ?? DateTime.utc(2025),
  updatedAt: DateTime.utc(2026),
  deletedAt: deletedAt,
);

void main() {
  final now = DateTime.utc(2026, 3, 10, 12);

  test('orders due now, then new (limited), then later today', () {
    final q = buildDueQueue(
      decks: [
        deck('d2', ['x'], createdAt: DateTime.utc(2026, 2)),
        deck('d1', ['a', 'b', 'c', 'd', 'e']),
      ],
      reviews: [
        review('d1', 'a', due: now.subtract(const Duration(hours: 1))),
        review('d1', 'b', due: now.subtract(const Duration(days: 3))),
        review('d1', 'c', due: DateTime.utc(2026, 3, 10, 20)),
        review('d1', 'd', due: DateTime.utc(2026, 3, 11, 1)), // tomorrow
      ],
      now: now,
      newCardsPerDay: 1,
      toLocal: utc,
    );
    expect(q.dueNow.map((c) => c.card.id), ['b', 'a']);
    expect(q.newCards.map((c) => c.key), ['d1/e'], reason: 'oldest deck first');
    expect(q.laterToday.map((c) => c.card.id), ['c']);
    expect(q.unseenTotal, 2);
    expect(q.count, 4);
    expect(q.all.first.card.id, 'b');
    expect(q.next!.card.id, 'b');
  });

  test('"today" follows the local time zone', () {
    final reviews = [review('d', 'a', due: DateTime.utc(2026, 3, 11, 1))];
    final decks = [
      deck('d', ['a']),
    ];
    // 12:00 UTC: in UTC+0 the card is due tomorrow; in UTC-2 (local time
    // 23:00 the due time is 23:00 the same day) it is due today.
    expect(
      buildDueQueue(
        decks: decks,
        reviews: reviews,
        now: DateTime.utc(2026, 3, 10, 12),
        newCardsPerDay: 0,
        toLocal: utc,
      ).count,
      0,
    );
    expect(
      buildDueQueue(
        decks: decks,
        reviews: reviews,
        now: DateTime.utc(2026, 3, 10, 12),
        newCardsPerDay: 0,
        toLocal: fixedOffset(const Duration(hours: -2)),
      ).laterToday.single.card.id,
      'a',
    );
  });

  test('daily new-card limit counts rows first reviewed today', () {
    final decks = [
      deck('d', ['a', 'b', 'c', 'd']),
    ];
    final reviews = [
      review(
        'd',
        'a',
        due: now.add(const Duration(days: 3)),
        createdAt: now.subtract(const Duration(hours: 2)),
      ),
      review(
        'd',
        'b',
        due: now.add(const Duration(days: 3)),
        createdAt: DateTime.utc(2026, 3, 9, 23),
      ),
    ];
    final q = buildDueQueue(
      decks: decks,
      reviews: reviews,
      now: now,
      newCardsPerDay: 2,
      toLocal: utc,
    );
    expect(q.newIntroducedToday, 1);
    expect(q.newRemainingToday, 1);
    expect(q.newCards.map((c) => c.card.id), ['c']);
    expect(
      buildDueQueue(
        decks: decks,
        reviews: reviews,
        now: now,
        newCardsPerDay: 0,
        toLocal: utc,
      ).newCards,
      isEmpty,
    );
  });

  test('ignores deleted decks, other decks (deckId), removed cards, '
      'tombstoned reviews (card is new again)', () {
    final q = buildDueQueue(
      decks: [
        deck('d', ['a', 'b']),
        deck('e', ['z']),
        deck('gone', ['g']).copyWith(deletedAt: DateTime.utc(2026)),
      ],
      reviews: [
        review('d', 'removed', due: now),
        review('d', 'a', due: now, deletedAt: DateTime.utc(2026)),
        review('gone', 'g', due: now),
        review('e', 'z', due: now),
      ],
      now: now,
      newCardsPerDay: 10,
      deckId: 'd',
      toLocal: utc,
    );
    expect(q.dueNow, isEmpty);
    expect(q.newCards.map((c) => c.card.id), ['a', 'b']);
  });

  test('deck stats', () {
    final d = deck('d', ['a', 'b', 'c', 'd', 'e']);
    final stats = deckStats(
      d,
      [
        review('d', 'a', due: now, scheduledDays: 30, lapses: 2),
        review('d', 'b', due: now.add(const Duration(days: 4))),
        review(
          'd',
          'c',
          due: now.add(const Duration(minutes: 10)),
          state: CardState.relearning,
          scheduledDays: 0,
        ),
        review('other', 'd', due: now),
      ],
      now: now,
      toLocal: utc,
    );
    expect(
      stats,
      const DeckStats(
        total: 5,
        newCount: 2,
        learning: 1,
        review: 2,
        mature: 1,
        dueToday: 2,
        lapses: 2,
      ),
    );
  });

  test('DueQueue equality (stream de-duplication)', () {
    DueQueue build() => buildDueQueue(
      decks: [
        deck('d', ['a']),
      ],
      reviews: const [],
      now: now,
      newCardsPerDay: 5,
      toLocal: utc,
    );
    expect(build(), build());
    expect(build().hashCode, build().hashCode);
  });
}
