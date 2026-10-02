import '../../study/due_queue.dart';
import '../models/card_review.dart';

/// The current user's private flashcard review state (FSRS), over all decks
/// they can read (own + shared). Local-first; rows sync via `card_reviews`.
abstract interface class ReviewRepository {
  /// Records an answer for [cardId] of [deckId] now, schedules the card
  /// with FSRS (current `StudySettings`) and returns the saved row. The row
  /// id is deterministic (`CardReview.idFor`). Throws `NotFoundException`
  /// when the deck or card no longer exists.
  Future<CardReview> recordReview({
    required String deckId,
    required String cardId,
    required Rating rating,
  });

  /// Next due time per rating if [cardId] were answered now (button
  /// labels). Throws `NotFoundException` like [recordReview].
  Future<Map<Rating, DateTime>> previewDue({
    required String deckId,
    required String cardId,
  });

  /// Today's queue across all readable decks (or one deck with [deckId]):
  /// due reviews, new cards within the daily new-card limit, cards due later
  /// today. [now] defaults to the clock at each re-evaluation; re-emits on
  /// any deck/review change.
  Stream<DueQueue> watchDue({DateTime? now, String? deckId});

  /// `watchDue().count` (badge).
  Stream<int> watchDueCount({DateTime? now});

  /// Card counts of one deck for the current user.
  Stream<DeckStats> watchDeckStats(String deckId, {DateTime? now});

  /// The user's live review rows of readable decks (stats).
  Stream<List<CardReview>> watchAll();

  /// Forgets the review state of a card (it becomes new again).
  Future<void> resetCard({required String deckId, required String cardId});
}
