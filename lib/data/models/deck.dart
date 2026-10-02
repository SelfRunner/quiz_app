import 'package:freezed_annotation/freezed_annotation.dart';

import 'quiz_source.dart';
import 'syncable.dart';

part 'deck.freezed.dart';
part 'deck.g.dart';

/// One flashcard embedded in `Deck.cards` (jsonb array element).
///
/// [id] is a stable key (uuid v4 string, 1..255 chars, unique within the
/// deck): keep it when editing [front]/[back]; `card_reviews.card_id`
/// references it and `copy_*` keep it.
@freezed
abstract class Flashcard with _$Flashcard {
  const factory Flashcard({
    required String id,
    required String front,
    required String back,
    String? hint,
  }) = _Flashcard;

  factory Flashcard.fromJson(Map<String, dynamic> json) =>
      _$FlashcardFromJson(json);

  /// Maximum length of a card id (server CHECK).
  static const int maxIdLength = 255;
}

/// Row of `public.decks`: a flashcard deck in a subject, optionally attached
/// to a note. Synced, shared and copied exactly like quizzes.
@freezed
abstract class Deck with _$Deck implements Syncable {
  const factory Deck({
    required String id,
    required String subjectId,
    String? noteId,
    required String ownerId,
    required String title,
    String? description,

    /// Provenance of an AI-generated deck (same shape as quizzes).
    QuizSource? source,
    @Default(<Flashcard>[]) List<Flashcard> cards,

    /// Normalized tags (see `normalizeTags`), owner's values (Wave 3).
    @Default(<String>[]) List<String> tags,

    /// Pinned to the top of lists (owner's value, Wave 3).
    @Default(false) bool pinned,
    required DateTime createdAt,
    required DateTime updatedAt,
    DateTime? deletedAt,
  }) = _Deck;

  factory Deck.fromJson(Map<String, dynamic> json) => _$DeckFromJson(json);
}
