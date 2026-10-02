import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:uuid/uuid.dart';

import 'syncable.dart';

part 'mistake.freezed.dart';
part 'mistake.g.dart';

/// Row of `public.mistakes`: the current user's private tracking of a
/// question they answered wrongly (the "Mistakes" practice set). Never
/// shared.
///
/// Lifecycle: a wrong answer sets `wrongCount++`, `correctStreak = 0`,
/// `resolvedAt = null`; a correct answer while open increments
/// [correctStreak] and resolves the mistake after
/// [Mistake.resolveAfterCorrect] consecutive correct answers.
@freezed
abstract class Mistake with _$Mistake implements Syncable {
  const factory Mistake({
    required String id,
    required String ownerId,
    required String quizId,

    /// `Question.id` within the quiz.
    required String questionId,
    @Default(0) int wrongCount,
    @Default(0) int correctStreak,
    DateTime? lastWrongAt,

    /// Set when mastered; null = still in the Mistakes set.
    DateTime? resolvedAt,
    required DateTime createdAt,
    required DateTime updatedAt,
    DateTime? deletedAt,
  }) = _Mistake;

  const Mistake._();

  factory Mistake.fromJson(Map<String, dynamic> json) =>
      _$MistakeFromJson(json);

  /// Consecutive correct answers that resolve a mistake.
  static const int resolveAfterCorrect = 2;

  /// Still in the Mistakes set (not resolved, not deleted).
  bool get isOpen => resolvedAt == null && deletedAt == null;

  /// Deterministic row id (uuid v5, URL namespace) shared by every device:
  /// `v5(url, 'quizapp:mistake:{ownerId}:{quizId}:{questionId}')`.
  static String idFor({
    required String ownerId,
    required String quizId,
    required String questionId,
  }) => const Uuid().v5(
    Namespace.url.value,
    'quizapp:mistake:$ownerId:$quizId:$questionId',
  );
}
