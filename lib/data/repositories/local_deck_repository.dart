import '../../core/errors/app_exception.dart';
import '../models/deck.dart';
import '../models/quiz_source.dart';
import 'deck_repository.dart';
import 'repository_support.dart';

/// Hive-backed [DeckRepository] (writes go through the outbox).
class LocalDeckRepository implements DeckRepository {
  LocalDeckRepository(this._ctx) : _cascade = CascadeDeleter(_ctx);

  final DataContext _ctx;
  final CascadeDeleter _cascade;

  @override
  Stream<List<Deck>> watchBySubject(String subjectId) => _ctx.db.decks
      .watchWhere((d) => d.subjectId == subjectId, compare: byUpdatedDesc);

  @override
  Stream<List<Deck>> watchByNote(String noteId) => _ctx.db.decks.watchWhere(
    (d) => d.noteId == noteId,
    compare: byUpdatedDesc,
  );

  @override
  Stream<List<Deck>> watchAllAccessible() =>
      _ctx.db.decks.watchWhere((_) => true, compare: byUpdatedDesc);

  static int byUpdatedDesc(Deck a, Deck b) {
    final c = b.updatedAt.compareTo(a.updatedAt);
    return c != 0 ? c : a.id.compareTo(b.id);
  }

  @override
  Stream<Deck?> watchById(String id) => _ctx.db.decks.watchById(id);

  @override
  Future<Deck?> getById(String id) async => _ctx.db.decks.getLive(id);

  @override
  Future<Deck> create({
    required String subjectId,
    String? noteId,
    required String title,
    String? description,
    List<Flashcard> cards = const [],
    QuizSource? source,
  }) async {
    final userId = _ctx.requireUserId();
    _checkParents(userId, subjectId, noteId);
    validateCards(cards);
    final now = _ctx.clock();
    final deck = Deck(
      id: _ctx.newId(),
      subjectId: subjectId,
      noteId: noteId,
      ownerId: userId,
      title: title.trim(),
      description: description,
      source: source,
      cards: cards,
      createdAt: now,
      updatedAt: now,
    );
    await _ctx.save(_ctx.db.decks, deck);
    return deck;
  }

  @override
  Future<Deck> update(Deck deck) async {
    final userId = _ctx.requireUserId();
    final existing = _ctx.requireLive(_ctx.db.decks, deck.id, 'deck');
    _ctx.ensureOwned(existing, userId, 'deck');
    if (deck.subjectId != existing.subjectId ||
        deck.noteId != existing.noteId) {
      _checkParents(userId, deck.subjectId, deck.noteId);
    }
    validateCards(deck.cards);
    final next = deck.copyWith(
      title: deck.title.trim(),
      ownerId: existing.ownerId,
      createdAt: existing.createdAt,
      updatedAt: _ctx.clock(),
      deletedAt: null,
    );
    await _ctx.save(_ctx.db.decks, next);
    return next;
  }

  @override
  Future<void> delete(String id) async {
    final userId = _ctx.requireUserId();
    final existing = _ctx.db.decks.getLive(id);
    if (existing == null) return;
    _ctx.ensureOwned(existing, userId, 'deck');
    await _cascade.deleteDeck(existing);
  }

  /// Card ids must be present, short and unique (server CHECK `23514`).
  static void validateCards(List<Flashcard> cards) {
    final seen = <String>{};
    for (final card in cards) {
      if (card.id.isEmpty || card.id.length > Flashcard.maxIdLength) {
        throw const ValidationException('A flashcard has an invalid id.');
      }
      if (!seen.add(card.id)) {
        throw const ValidationException('Two flashcards share the same id.');
      }
    }
  }

  void _checkParents(String userId, String subjectId, String? noteId) {
    final subject = _ctx.requireLive(_ctx.db.subjects, subjectId, 'subject');
    _ctx.ensureOwned(subject, userId, 'subject');
    if (noteId == null) return;
    final note = _ctx.requireLive(_ctx.db.notes, noteId, 'note');
    _ctx.ensureOwned(note, userId, 'note');
    if (note.subjectId != subjectId) {
      throw const ValidationException(
        'The note belongs to a different subject.',
      );
    }
  }
}
