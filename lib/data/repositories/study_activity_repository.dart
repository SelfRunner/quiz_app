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
      () {
        // Archived subjects (and their quizzes / decks) are hidden from the
        // dashboard; the user's attempts and reviews still count for the
        // streak and totals.
        final archived = archivedSubjectIds(db);
        return StudySnapshot(
          subjects: db.subjects.where((s) => !archived.contains(s.id)),
          quizzes: db.quizzes.where((q) => !archived.contains(q.subjectId)),
          decks: db.decks.where((d) => !archived.contains(d.subjectId)),
          attempts: db.attempts.where((a) => a.ownerId == userId),
          reviews: db.reviews.where((r) => r.ownerId == userId),
          mistakes: db.mistakes.where((m) => m.ownerId == userId),
        );
      },
      // Snapshots are rebuilt only after a change; always emit.
      equals: (a, b) => false,
    );
  }
}
