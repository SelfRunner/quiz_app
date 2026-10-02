/// "Due today" queue and per-deck statistics for flashcards (pure).
library;

import 'package:meta/meta.dart';

import '../data/models/card_review.dart';
import '../data/models/deck.dart';
import 'local_day.dart';

/// One card to study: a [card] of [deck] with the user's [review] state
/// (null = never reviewed).
@immutable
class DueCard {
  const DueCard({required this.deck, required this.card, this.review});

  final Deck deck;
  final Flashcard card;
  final CardReview? review;

  bool get isNew => review == null || review!.state == CardState.newCard;

  /// Due time; null for new cards.
  DateTime? get dueAt => isNew ? null : review!.dueAt;

  CardState get state => review?.state ?? CardState.newCard;

  /// `deckId/cardId`, unique within a queue.
  String get key => '${deck.id}/${card.id}';

  @override
  bool operator ==(Object other) =>
      other is DueCard &&
      other.deck == deck &&
      other.card == card &&
      other.review == review;

  @override
  int get hashCode => Object.hash(deck, card, review);

  @override
  String toString() => 'DueCard($key, ${state.name}, due: $dueAt)';
}

/// The cards to study today, in study order: [dueNow], then [newCards],
/// then [laterToday].
@immutable
class DueQueue {
  const DueQueue({
    this.dueNow = const [],
    this.newCards = const [],
    this.laterToday = const [],
    this.newIntroducedToday = 0,
    this.newRemainingToday = 0,
    this.unseenTotal = 0,
  });

  /// Reviewed cards due at or before `now`, oldest due first.
  final List<DueCard> dueNow;

  /// Never-reviewed cards, limited by the daily new-card allowance.
  final List<DueCard> newCards;

  /// Cards due later today (e.g. learning steps), soonest first.
  final List<DueCard> laterToday;

  /// New cards first reviewed today (counted against the daily limit).
  final int newIntroducedToday;

  /// New cards still allowed today (`limit - introduced`, >= 0).
  final int newRemainingToday;

  /// All never-reviewed cards in scope (before the daily limit).
  final int unseenTotal;

  List<DueCard> get all => [...dueNow, ...newCards, ...laterToday];

  /// Number of cards to study today (badge count).
  int get count => dueNow.length + newCards.length + laterToday.length;

  bool get isEmpty => count == 0;

  /// The next card to show at `now`, or null when nothing is due yet.
  DueCard? get next => dueNow.firstOrNull ?? newCards.firstOrNull;

  @override
  bool operator ==(Object other) =>
      other is DueQueue &&
      _listEquals(other.dueNow, dueNow) &&
      _listEquals(other.newCards, newCards) &&
      _listEquals(other.laterToday, laterToday) &&
      other.newIntroducedToday == newIntroducedToday &&
      other.newRemainingToday == newRemainingToday &&
      other.unseenTotal == unseenTotal;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(dueNow),
    Object.hashAll(newCards),
    Object.hashAll(laterToday),
    newIntroducedToday,
    newRemainingToday,
    unseenTotal,
  );
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Builds today's queue.
///
/// - [decks]: readable live decks (own + shared).
/// - [reviews]: the user's live `card_reviews` rows (any deck).
/// - Reviews whose deck is not in [decks] (revoked/deleted) or whose card
///   was removed from the deck are ignored.
/// - New cards (no review row, or a row in state new) are taken in deck
///   order (decks by `createdAt`), limited to `newCardsPerDay` minus the
///   rows first created today (local day of `createdAt`).
/// - [deckId] restricts the queue to one deck (the daily limit stays
///   global).
DueQueue buildDueQueue({
  required Iterable<Deck> decks,
  required Iterable<CardReview> reviews,
  required DateTime now,
  required int newCardsPerDay,
  String? deckId,
  ToLocal toLocal = deviceLocal,
}) {
  final today = localDay(now, toLocal);
  final liveReviews = reviews.where((r) => r.deletedAt == null).toList();
  final introduced = liveReviews
      .where(
        (r) =>
            r.state != CardState.newCard &&
            localDay(r.createdAt, toLocal) == today,
      )
      .length;
  final remaining = (newCardsPerDay - introduced).clamp(0, 1 << 30);

  final byCard = <String, CardReview>{
    for (final r in liveReviews) '${r.deckId}/${r.cardId}': r,
  };
  final scoped =
      decks
          .where((d) => d.deletedAt == null)
          .where((d) => deckId == null || d.id == deckId)
          .toList()
        ..sort((a, b) {
          final c = a.createdAt.compareTo(b.createdAt);
          return c != 0 ? c : a.id.compareTo(b.id);
        });

  final dueNow = <DueCard>[];
  final later = <DueCard>[];
  final unseen = <DueCard>[];
  for (final deck in scoped) {
    for (final card in deck.cards) {
      final review = byCard['${deck.id}/${card.id}'];
      final item = DueCard(deck: deck, card: card, review: review);
      if (item.isNew) {
        unseen.add(item);
      } else if (!review!.dueAt.isAfter(now)) {
        dueNow.add(item);
      } else if (!localDay(review.dueAt, toLocal).isAfter(today)) {
        later.add(item);
      }
    }
  }
  int byDue(DueCard a, DueCard b) {
    final c = a.dueAt!.compareTo(b.dueAt!);
    return c != 0 ? c : a.key.compareTo(b.key);
  }

  dueNow.sort(byDue);
  later.sort(byDue);
  return DueQueue(
    dueNow: dueNow,
    newCards: unseen.take(remaining).toList(),
    laterToday: later,
    newIntroducedToday: introduced,
    newRemainingToday: remaining,
    unseenTotal: unseen.length,
  );
}

/// Card counts of one deck for the current user.
@immutable
class DeckStats {
  const DeckStats({
    this.total = 0,
    this.newCount = 0,
    this.learning = 0,
    this.review = 0,
    this.mature = 0,
    this.dueToday = 0,
    this.lapses = 0,
  });

  /// Cards in the deck.
  final int total;

  /// Never reviewed.
  final int newCount;

  /// In learning or relearning steps.
  final int learning;

  /// Graduated (state review).
  final int review;

  /// Review cards with an interval of at least [matureDays] days.
  final int mature;

  /// Reviewed cards due by the end of today (new cards not included).
  final int dueToday;

  /// Total lapses over the deck's cards.
  final int lapses;

  /// Interval from which a card counts as mature (Anki convention).
  static const int matureDays = 21;

  @override
  bool operator ==(Object other) =>
      other is DeckStats &&
      other.total == total &&
      other.newCount == newCount &&
      other.learning == learning &&
      other.review == review &&
      other.mature == mature &&
      other.dueToday == dueToday &&
      other.lapses == lapses;

  @override
  int get hashCode =>
      Object.hash(total, newCount, learning, review, mature, dueToday, lapses);

  @override
  String toString() =>
      'DeckStats(total: $total, new: $newCount, learning: $learning, '
      'review: $review, mature: $mature, due: $dueToday, lapses: $lapses)';
}

/// Statistics of [deck] from the user's live [reviews] (other decks'
/// reviews and reviews of removed cards are ignored).
DeckStats deckStats(
  Deck deck,
  Iterable<CardReview> reviews, {
  required DateTime now,
  ToLocal toLocal = deviceLocal,
}) {
  final today = localDay(now, toLocal);
  final byCard = {
    for (final r in reviews)
      if (r.deckId == deck.id && r.deletedAt == null) r.cardId: r,
  };
  var newCount = 0, learning = 0, review = 0, mature = 0, due = 0, lapses = 0;
  for (final card in deck.cards) {
    final r = byCard[card.id];
    if (r == null || r.state == CardState.newCard) {
      newCount++;
      continue;
    }
    lapses += r.lapses;
    if (r.state == CardState.review) {
      review++;
      if (r.scheduledDays >= DeckStats.matureDays) mature++;
    } else {
      learning++;
    }
    if (!localDay(r.dueAt, toLocal).isAfter(today)) due++;
  }
  return DeckStats(
    total: deck.cards.length,
    newCount: newCount,
    learning: learning,
    review: review,
    mature: mature,
    dueToday: due,
    lapses: lapses,
  );
}
