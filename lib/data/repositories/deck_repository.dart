import '../models/deck.dart';
import '../models/quiz_source.dart';

/// Local-first access to flashcard decks (own + shared with the user).
///
/// Streams exclude soft-deleted decks. Shared decks are read-only: `update`
/// / `delete` throw `PermissionDeniedException` (UI checks
/// `deck.isOwnedBy(currentUserId)`).
abstract interface class DeckRepository {
  /// Decks of a subject, including note decks, `updatedAt` desc.
  Stream<List<Deck>> watchBySubject(String subjectId);

  /// Decks attached to a note, `updatedAt` desc.
  Stream<List<Deck>> watchByNote(String noteId);

  /// Every live deck the user can read (own + shared), `updatedAt` desc.
  Stream<List<Deck>> watchAllAccessible();

  Stream<Deck?> watchById(String id);

  Future<Deck?> getById(String id);

  /// Creates a deck in an owned subject (and optionally an owned note of
  /// that subject). Card ids must be non-empty, <= 255 chars and unique
  /// (`ValidationException`).
  Future<Deck> create({
    required String subjectId,
    String? noteId,
    required String title,
    String? description,
    List<Flashcard> cards = const [],
    QuizSource? source,
  });

  /// Saves title/description/cards/source (and moves, same rules as
  /// create). Bumps `updatedAt`.
  Future<Deck> update(Deck deck);

  /// Soft delete (owner only). Review state of the deck is kept but hidden.
  Future<void> delete(String id);
}
