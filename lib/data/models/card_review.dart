import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../study/fsrs.dart';
import 'syncable.dart';

export '../../study/fsrs.dart' show CardState, Rating;

part 'card_review.freezed.dart';
part 'card_review.g.dart';

/// Row of `public.card_reviews`: the current user's private spaced-repetition
/// state (FSRS) for one card of a deck. Never shared.
///
/// The [id] is deterministic ([CardReview.idFor]) so that devices reviewing
/// the same card offline converge on one row (last write wins).
@freezed
abstract class CardReview with _$CardReview implements Syncable {
  const factory CardReview({
    required String id,

    /// The reviewing user.
    required String ownerId,
    required String deckId,

    /// `Flashcard.id` within the deck.
    required String cardId,
    @JsonKey(unknownEnumValue: CardState.newCard)
    @Default(CardState.newCard)
    CardState state,
    required DateTime dueAt,
    @Default(0) double stability,
    @Default(0) double difficulty,
    @Default(0) int elapsedDays,
    @Default(0) int scheduledDays,
    @Default(0) int reps,
    @Default(0) int lapses,
    DateTime? lastReviewAt,
    required DateTime createdAt,
    required DateTime updatedAt,
    DateTime? deletedAt,
  }) = _CardReview;

  const CardReview._();

  factory CardReview.fromJson(Map<String, dynamic> json) =>
      _$CardReviewFromJson(json);

  /// Deterministic row id (uuid v5, URL namespace) shared by every device:
  /// `v5(url, 'quizapp:card_review:{ownerId}:{deckId}:{cardId}')`.
  static String idFor({
    required String ownerId,
    required String deckId,
    required String cardId,
  }) => const Uuid().v5(
    Namespace.url.value,
    'quizapp:card_review:$ownerId:$deckId:$cardId',
  );

  /// Scheduler view of this row.
  FsrsCard toFsrs() => FsrsCard(
    state: state,
    due: dueAt,
    stability: stability,
    difficulty: difficulty,
    elapsedDays: elapsedDays,
    scheduledDays: scheduledDays,
    reps: reps,
    lapses: lapses,
    lastReview: lastReviewAt,
  );

  /// This row with the scheduling fields of [card].
  CardReview withFsrs(FsrsCard card) => copyWith(
    state: card.state,
    dueAt: card.due,
    stability: card.stability,
    difficulty: card.difficulty,
    elapsedDays: card.elapsedDays,
    scheduledDays: card.scheduledDays,
    reps: card.reps,
    lapses: card.lapses,
    lastReviewAt: card.lastReview,
  );
}
