import 'package:meta/meta.dart';

import '../models/mistake.dart';
import '../models/question.dart';
import '../models/quiz.dart';
import '../models/quiz_attempt.dart';

/// An open mistake with its question (resolved from the cached quiz).
@immutable
class MistakeEntry {
  const MistakeEntry({required this.mistake, required this.question});

  final Mistake mistake;
  final Question question;

  @override
  bool operator ==(Object other) =>
      other is MistakeEntry &&
      other.mistake == mistake &&
      other.question == question;

  @override
  int get hashCode => Object.hash(mistake, question);
}

/// Open mistakes of one quiz, in the quiz's question order.
@immutable
class MistakeGroup {
  const MistakeGroup({required this.quiz, required this.entries});

  final Quiz quiz;
  final List<MistakeEntry> entries;

  /// The questions to practise (for a `mistakes`-mode session).
  List<Question> get questions => [for (final e in entries) e.question];

  /// Most recent wrong answer in the group.
  DateTime? get lastWrongAt {
    DateTime? latest;
    for (final e in entries) {
      final t = e.mistake.lastWrongAt;
      if (t != null && (latest == null || t.isAfter(latest))) latest = t;
    }
    return latest;
  }

  @override
  bool operator ==(Object other) {
    if (other is! MistakeGroup || other.quiz != quiz) return false;
    if (other.entries.length != entries.length) return false;
    for (var i = 0; i < entries.length; i++) {
      if (other.entries[i] != entries[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(quiz, Object.hashAll(entries));
}

/// The current user's private "Mistakes" set (wrongly answered questions),
/// local-first; rows sync via `mistakes`.
abstract interface class MistakeRepository {
  /// Records one graded answer:
  /// - wrong: creates/updates the row (`wrongCount++`, `correctStreak = 0`,
  ///   `resolvedAt = null`, `lastWrongAt = now`);
  /// - correct while open: `correctStreak++`, resolved after
  ///   `Mistake.resolveAfterCorrect` (2) consecutive correct answers;
  /// - correct with no open mistake: nothing is written.
  /// Returns the row (null when none exists). Throws `NotFoundException`
  /// when the quiz isn't available.
  Future<Mistake?> recordAnswer({
    required String quizId,
    required String questionId,
    required bool correct,
  });

  /// [recordAnswer] for every graded answer (`isCorrect != null`) of a
  /// completed attempt. Ignores attempts of quizzes no longer available.
  Future<void> recordAttempt(QuizAttempt attempt);

  /// Open mistakes grouped by quiz (most recent wrong answer first).
  /// Mistakes whose quiz isn't cached (revoked/deleted) or whose question
  /// was removed are hidden.
  Stream<List<MistakeGroup>> watchOpen();

  /// Number of visible open mistakes (badge).
  Stream<int> watchOpenCount();

  /// Marks a mistake as mastered ("I know this now").
  Future<void> resolve({required String quizId, required String questionId});
}
