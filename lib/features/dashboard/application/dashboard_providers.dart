import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../data/data_providers.dart';
import '../../../data/models/models.dart';
import '../../../study/local_day.dart';
import '../../../study/stats.dart';

/// Today's local calendar day ([localDay]) from [clockProvider].
final dashboardTodayProvider = Provider.autoDispose<DateTime>(
  (ref) => localDay(ref.watch(clockProvider)()),
);

/// Local days with study activity (quiz attempts and card reviews), for the
/// streak activity strip.
final activityDaysProvider = StreamProvider.autoDispose<Set<DateTime>>(
  (ref) => ref
      .watch(studyActivityRepositoryProvider)
      .watchSnapshot()
      .map((s) => activityDays(attempts: s.attempts, reviews: s.reviews)),
);

/// The current user's own notes, newest created first (max 10), for the
/// recent activity feed; notes of archived subjects are left out. Empty
/// while loading or on error.
final recentNotesProvider = Provider.autoDispose<List<Note>>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  final notes = ref.watch(accessibleNotesProvider).value ?? const <Note>[];
  final own = [
    for (final n in notes)
      if (n.deletedAt == null && (userId == null || n.ownerId == userId)) n,
  ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  final archived = {
    for (final id in {for (final n in own) n.subjectId})
      if (ref.watch(subjectProvider(id)).value?.archivedAt != null) id,
  };
  return own.where((n) => !archived.contains(n.subjectId)).take(10).toList();
});

/// One row of the dashboard's recent activity feed.
sealed class FeedEntry {
  const FeedEntry();

  DateTime get at;
}

/// A quiz attempt or a flashcard review session.
final class StudyFeedEntry extends FeedEntry {
  const StudyFeedEntry(this.item);

  final ActivityItem item;

  @override
  DateTime get at => item.at;
}

/// A note the user created.
final class NoteFeedEntry extends FeedEntry {
  const NoteFeedEntry(this.note);

  final Note note;

  @override
  DateTime get at => note.createdAt;
}

/// Merges study activity and new notes, newest first.
List<FeedEntry> buildActivityFeed(
  List<ActivityItem> activity,
  List<Note> notes, {
  int limit = 8,
}) {
  final entries = <FeedEntry>[
    for (final a in activity) StudyFeedEntry(a),
    for (final n in notes) NoteFeedEntry(n),
  ]..sort((a, b) => b.at.compareTo(a.at));
  return entries.take(limit).toList();
}

/// Whether [stats] show no study history at all (first-run guide).
bool isFreshStart(DashboardStats stats) =>
    stats.quizzesTaken == 0 &&
    stats.recentActivity.isEmpty &&
    stats.due.isEmpty &&
    stats.due.unseenTotal == 0 &&
    stats.streak.longest == 0 &&
    stats.openMistakes == 0;
