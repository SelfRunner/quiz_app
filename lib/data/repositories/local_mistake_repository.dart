import '../local/local_table.dart';
import '../models/mistake.dart';
import '../models/quiz.dart';
import '../models/quiz_attempt.dart';
import 'mistake_repository.dart';
import 'repository_support.dart';

/// Hive-backed [MistakeRepository]. Rows are private to the user and keyed
/// by a uuid v5 of (owner, quiz, question), so offline devices converge.
class LocalMistakeRepository implements MistakeRepository {
  LocalMistakeRepository(this._ctx);

  final DataContext _ctx;

  @override
  Future<Mistake?> recordAnswer({
    required String quizId,
    required String questionId,
    required bool correct,
  }) async {
    final userId = _ctx.requireUserId();
    _ctx.requireLive(_ctx.db.quizzes, quizId, 'quiz');
    return _record(userId, quizId, questionId, correct);
  }

  @override
  Future<void> recordAttempt(QuizAttempt attempt) async {
    final userId = _ctx.requireUserId();
    if (_ctx.db.quizzes.getLive(attempt.quizId) == null) return;
    for (final answer in attempt.answers) {
      final correct = answer.isCorrect;
      if (correct == null) continue;
      await _record(userId, attempt.quizId, answer.questionId, correct);
    }
  }

  Future<Mistake?> _record(
    String userId,
    String quizId,
    String questionId,
    bool correct,
  ) async {
    final existing = _find(userId, quizId, questionId);
    final open = existing != null && existing.isOpen;
    if (correct && !open) return existing?.deletedAt == null ? existing : null;
    final now = _ctx.clock();
    final Mistake next;
    if (!correct) {
      final base =
          existing ??
          Mistake(
            id: Mistake.idFor(
              ownerId: userId,
              quizId: quizId,
              questionId: questionId,
            ),
            ownerId: userId,
            quizId: quizId,
            questionId: questionId,
            createdAt: now,
            updatedAt: now,
          );
      next = base.copyWith(
        wrongCount: (existing?.deletedAt == null ? base.wrongCount : 0) + 1,
        correctStreak: 0,
        lastWrongAt: now,
        resolvedAt: null,
        updatedAt: now,
        deletedAt: null,
      );
    } else {
      final streak = existing!.correctStreak + 1;
      next = existing.copyWith(
        correctStreak: streak,
        resolvedAt: streak >= Mistake.resolveAfterCorrect ? now : null,
        updatedAt: now,
      );
    }
    await _ctx.save(_ctx.db.mistakes, next);
    return next;
  }

  @override
  Future<void> resolve({
    required String quizId,
    required String questionId,
  }) async {
    final userId = _ctx.requireUserId();
    final existing = _find(userId, quizId, questionId);
    if (existing == null || !existing.isOpen) return;
    final now = _ctx.clock();
    await _ctx.save(
      _ctx.db.mistakes,
      existing.copyWith(resolvedAt: now, updatedAt: now),
    );
  }

  @override
  Stream<List<MistakeGroup>> watchOpen() {
    final userId = _ctx.currentUserId;
    if (userId == null) return Stream.value(const []);
    return watchQuery(
      [_ctx.db.quizzes.box, _ctx.db.mistakes.box],
      () => _groups(userId),
      equals: _listEquals,
    );
  }

  @override
  Stream<int> watchOpenCount() => watchOpen()
      .map((groups) => groups.fold<int>(0, (n, g) => n + g.entries.length))
      .distinct();

  List<MistakeGroup> _groups(String userId) {
    final byQuiz = <String, List<Mistake>>{};
    for (final m in _ctx.db.mistakes.where(
      (m) => m.ownerId == userId && m.isOpen,
    )) {
      (byQuiz[m.quizId] ??= []).add(m);
    }
    final groups = <MistakeGroup>[];
    for (final MapEntry(key: quizId, value: mistakes) in byQuiz.entries) {
      final Quiz? quiz = _ctx.db.quizzes.getLive(quizId);
      if (quiz == null) continue;
      final byQuestion = {for (final m in mistakes) m.questionId: m};
      final entries = [
        for (final q in quiz.questions)
          if (byQuestion[q.id] case final m?)
            MistakeEntry(mistake: m, question: q),
      ];
      if (entries.isNotEmpty) {
        groups.add(MistakeGroup(quiz: quiz, entries: entries));
      }
    }
    groups.sort((a, b) {
      final ta = a.lastWrongAt, tb = b.lastWrongAt;
      final c = (tb ?? DateTime(0)).compareTo(ta ?? DateTime(0));
      return c != 0 ? c : a.quiz.id.compareTo(b.quiz.id);
    });
    return groups;
  }

  /// The user's row for a question (deterministic id, else any row with
  /// that key, e.g. adopted after a `23505`).
  Mistake? _find(String userId, String quizId, String questionId) {
    final byId = _ctx.db.mistakes.get(
      Mistake.idFor(ownerId: userId, quizId: quizId, questionId: questionId),
    );
    if (byId != null && byId.deletedAt == null) return byId;
    final rows = _ctx.db.mistakes.where(
      (m) =>
          m.ownerId == userId &&
          m.quizId == quizId &&
          m.questionId == questionId,
      includeDeleted: true,
    );
    return rows.where((m) => m.deletedAt == null).firstOrNull ??
        byId ??
        rows.firstOrNull;
  }

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
