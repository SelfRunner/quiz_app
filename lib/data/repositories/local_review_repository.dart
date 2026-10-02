import 'dart:math' as math;

import '../../core/errors/app_exception.dart';
import '../../study/due_queue.dart';
import '../../study/fsrs.dart';
import '../../study/local_day.dart';
import '../../study/study_settings.dart';
import '../local/local_table.dart';
import '../models/card_review.dart';
import '../models/deck.dart';
import 'repository_support.dart';
import 'review_repository.dart';

/// Hive-backed [ReviewRepository]. Review rows are private to the user and
/// keyed by a uuid v5 of (owner, deck, card), so offline devices converge.
class LocalReviewRepository implements ReviewRepository {
  LocalReviewRepository(
    this._ctx, {
    StudySettings Function()? settings,
    this.toLocal = deviceLocal,
    this._random,
  }) : _settings = settings ?? (() => const StudySettings());

  final DataContext _ctx;
  final StudySettings Function() _settings;
  final math.Random? _random;

  /// Local time zone used for "today" (tests inject a fixed offset).
  final ToLocal toLocal;

  @override
  Future<CardReview> recordReview({
    required String deckId,
    required String cardId,
    required Rating rating,
  }) async {
    final userId = _ctx.requireUserId();
    _requireCard(deckId, cardId);
    final now = _ctx.clock();
    final existing = _find(userId, deckId, cardId);
    final live = existing != null && existing.deletedAt == null
        ? existing
        : null;
    final base = live?.toFsrs() ?? FsrsCard.newCard(now);
    final next = _scheduler().review(base, rating, now);
    final row =
        (live ??
                CardReview(
                  id:
                      existing?.id ??
                      CardReview.idFor(
                        ownerId: userId,
                        deckId: deckId,
                        cardId: cardId,
                      ),
                  ownerId: userId,
                  deckId: deckId,
                  cardId: cardId,
                  dueAt: now,
                  createdAt: existing?.createdAt ?? now,
                  updatedAt: now,
                ))
            .withFsrs(next)
            .copyWith(updatedAt: now, deletedAt: null);
    await _ctx.save(_ctx.db.reviews, row);
    return row;
  }

  @override
  Future<Map<Rating, DateTime>> previewDue({
    required String deckId,
    required String cardId,
  }) async {
    final userId = _ctx.requireUserId();
    _requireCard(deckId, cardId);
    final now = _ctx.clock();
    final existing = _find(userId, deckId, cardId);
    final base = existing != null && existing.deletedAt == null
        ? existing.toFsrs()
        : FsrsCard.newCard(now);
    // Without fuzz: labels must not jitter between rebuilds.
    final fsrs = Fsrs(desiredRetention: _settings().desiredRetention);
    return {
      for (final e in fsrs.preview(base, now).entries) e.key: e.value.due,
    };
  }

  @override
  Stream<DueQueue> watchDue({DateTime? now, String? deckId}) {
    final userId = _ctx.currentUserId;
    if (userId == null) return Stream.value(const DueQueue());
    return watchQuery(
      [_ctx.db.decks.box, _ctx.db.reviews.box],
      () => buildDueQueue(
        decks: _ctx.db.decks.where((_) => true),
        reviews: _ownLive(userId),
        now: now ?? _ctx.clock(),
        newCardsPerDay: _settings().newCardsPerDay,
        deckId: deckId,
        toLocal: toLocal,
      ),
      equals: (a, b) => a == b,
    );
  }

  @override
  Stream<int> watchDueCount({DateTime? now}) =>
      watchDue(now: now).map((q) => q.count).distinct();

  @override
  Stream<DeckStats> watchDeckStats(String deckId, {DateTime? now}) {
    final userId = _ctx.currentUserId;
    return watchQuery([_ctx.db.decks.box, _ctx.db.reviews.box], () {
      final deck = _ctx.db.decks.getLive(deckId);
      if (deck == null || userId == null) return const DeckStats();
      return deckStats(
        deck,
        _ownLive(userId).where((r) => r.deckId == deckId),
        now: now ?? _ctx.clock(),
        toLocal: toLocal,
      );
    }, equals: (a, b) => a == b);
  }

  @override
  Stream<List<CardReview>> watchAll() {
    final userId = _ctx.currentUserId;
    if (userId == null) return Stream.value(const []);
    return watchQuery([_ctx.db.decks.box, _ctx.db.reviews.box], () {
      final readable = {for (final d in _ctx.db.decks.where((_) => true)) d.id};
      return _ownLive(userId).where((r) => readable.contains(r.deckId)).toList()
        ..sort((a, b) => a.id.compareTo(b.id));
    }, equals: _listEquals);
  }

  @override
  Future<void> resetCard({
    required String deckId,
    required String cardId,
  }) async {
    final userId = _ctx.requireUserId();
    final existing = _find(userId, deckId, cardId);
    if (existing == null || existing.deletedAt != null) return;
    final now = _ctx.clock();
    await _ctx.save(
      _ctx.db.reviews,
      existing.copyWith(deletedAt: now, updatedAt: now),
    );
  }

  // ---------------------------------------------------------------------------

  Fsrs _scheduler() => _settings().scheduler(random: _random);

  Iterable<CardReview> _ownLive(String userId) =>
      _ctx.db.reviews.where((r) => r.ownerId == userId);

  /// The user's row for a card (live preferred, else a tombstone): usually
  /// the deterministic id, but a row adopted after a `23505` may differ.
  CardReview? _find(String userId, String deckId, String cardId) {
    final byId = _ctx.db.reviews.get(
      CardReview.idFor(ownerId: userId, deckId: deckId, cardId: cardId),
    );
    if (byId != null && byId.deletedAt == null) return byId;
    final rows = _ctx.db.reviews.where(
      (r) => r.ownerId == userId && r.deckId == deckId && r.cardId == cardId,
      includeDeleted: true,
    );
    return rows.where((r) => r.deletedAt == null).firstOrNull ??
        byId ??
        rows.firstOrNull;
  }

  Flashcard _requireCard(String deckId, String cardId) {
    final Deck deck = _ctx.requireLive(_ctx.db.decks, deckId, 'deck');
    final card = deck.cards.where((c) => c.id == cardId).firstOrNull;
    if (card == null) {
      throw const NotFoundException('This card no longer exists.');
    }
    return card;
  }

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
