import '../../core/errors/app_exception.dart';
import '../models/quiz_attempt.dart';
import '../models/syncable.dart';
import 'attempt_repository.dart';
import 'repository_support.dart';

/// Hive-backed [AttemptRepository]. Attempts are always owned by the user
/// who took the quiz (also for quizzes shared with them).
class LocalAttemptRepository implements AttemptRepository {
  LocalAttemptRepository(this._ctx);

  final DataContext _ctx;

  @override
  Stream<List<QuizAttempt>> watchByQuiz(String quizId) {
    final userId = _ctx.currentUserId;
    if (userId == null) return Stream.value(const []);
    return _ctx.db.attempts.watchWhere(
      (a) => a.quizId == quizId && a.ownerId == userId,
      compare: (a, b) {
        final c = b.startedAt.compareTo(a.startedAt);
        return c != 0 ? c : a.id.compareTo(b.id);
      },
    );
  }

  @override
  Stream<QuizAttempt?> watchById(String id) => _ctx.db.attempts.watchById(id);

  @override
  Future<QuizAttempt?> getById(String id) async => _ctx.db.attempts.getLive(id);

  @override
  Future<QuizAttempt> start({
    required String quizId,
    required int total,
  }) async {
    final userId = _ctx.requireUserId();
    final now = _ctx.clock();
    final attempt = QuizAttempt(
      id: _ctx.newId(),
      quizId: quizId,
      ownerId: userId,
      total: total,
      startedAt: now,
      createdAt: now,
      updatedAt: now,
    );
    await _ctx.save(_ctx.db.attempts, attempt);
    return attempt;
  }

  @override
  Future<QuizAttempt> save(QuizAttempt attempt) async {
    final userId = _ctx.requireUserId();
    final existing = _ctx.db.attempts.get(attempt.id);
    if ((existing != null && !existing.isOwnedBy(userId)) ||
        attempt.ownerId != userId) {
      throw const PermissionDeniedException(
        'This attempt belongs to another user.',
      );
    }
    final next = attempt.copyWith(
      createdAt: existing?.createdAt ?? attempt.createdAt,
      updatedAt: _ctx.clock(),
    );
    await _ctx.save(_ctx.db.attempts, next);
    return next;
  }

  @override
  Future<void> delete(String id) async {
    final userId = _ctx.requireUserId();
    final existing = _ctx.db.attempts.getLive(id);
    if (existing == null) return;
    _ctx.ensureOwned(existing, userId, 'attempt');
    final now = _ctx.clock();
    await _ctx.save(
      _ctx.db.attempts,
      existing.copyWith(deletedAt: now, updatedAt: now),
    );
  }
}
