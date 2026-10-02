import '../../study/stats.dart';
import '../local/local_table.dart';
import 'repository_support.dart';

/// Read-only source of everything the progress dashboard needs.
abstract interface class StudyActivityRepository {
  /// Live cached subjects/quizzes/decks (own + shared) and the user's own
  /// attempts, card reviews and mistakes. Emits on listen and on any change
  /// of those tables.
  Stream<StudySnapshot> watchSnapshot();
}

/// Hive-backed [StudyActivityRepository].
class LocalStudyActivityRepository implements StudyActivityRepository {
  LocalStudyActivityRepository(this._ctx);

  final DataContext _ctx;

  @override
  Stream<StudySnapshot> watchSnapshot() {
    final userId = _ctx.currentUserId;
    if (userId == null) return Stream.value(const StudySnapshot());
    final db = _ctx.db;
    return watchQuery(
      [
        db.subjects.box,
        db.quizzes.box,
        db.decks.box,
        db.attempts.box,
        db.reviews.box,
        db.mistakes.box,
      ],
      () => StudySnapshot(
        subjects: db.subjects.where((_) => true),
        quizzes: db.quizzes.where((_) => true),
        decks: db.decks.where((_) => true),
        attempts: db.attempts.where((a) => a.ownerId == userId),
        reviews: db.reviews.where((r) => r.ownerId == userId),
        mistakes: db.mistakes.where((m) => m.ownerId == userId),
      ),
      // Snapshots are rebuilt only after a change; always emit.
      equals: (a, b) => false,
    );
  }
}
