import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../data/data_providers.dart';
import 'stats.dart';

/// Progress dashboard (home): streak, quizzes taken, accuracy per subject,
/// weakest questions/quizzes, due cards, open mistakes, recent activity.
/// Recomputed whenever subjects, quizzes, decks, attempts, reviews or
/// mistakes change (and when the study settings change).
final dashboardStatsProvider = StreamProvider.autoDispose<DashboardStats>((
  ref,
) {
  final clock = ref.watch(clockProvider);
  final newCardsPerDay = ref.watch(
    studySettingsProvider.select((s) => s.newCardsPerDay),
  );
  return ref
      .watch(studyActivityRepositoryProvider)
      .watchSnapshot()
      .map(
        (snapshot) => computeDashboard(
          snapshot,
          now: clock(),
          newCardsPerDay: newCardsPerDay,
        ),
      );
});
