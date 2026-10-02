import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/providers.dart';
import '../../../core/widgets/design_system.dart';
import '../../../data/data_providers.dart';
import '../../../data/models/models.dart';
import '../../../study/stats.dart';
import '../../../study/study_providers.dart';
import '../application/dashboard_providers.dart';
import '../widgets/dashboard_cards.dart';

/// Progress dashboard (home): greeting, streak, today's cards, mistakes,
/// quiz accuracy (overall and per subject), weakest topics, recent activity
/// and quick actions. New users get a short getting-started guide.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  /// Content width from which cards sit side by side.
  static const double _twoColumns = 560;
  static const double _threeColumns = 840;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(dashboardStatsProvider);
    return ResponsiveScaffold(
      appBar: AppBar(title: const Text('Home')),
      maxWidth: ContentWidth.wide,
      scrollable: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Greeting(),
          Gaps.h24,
          AsyncValueView<DashboardStats>(
            value: stats,
            onRetry: () => ref.invalidate(dashboardStatsProvider),
            loading: const LoadingSkeleton(rows: 4),
            data: (s) => isFreshStart(s)
                ? const _FreshStart()
                : _DashboardBody(stats: s),
          ),
        ],
      ),
    );
  }
}

class _Greeting extends ConsumerWidget {
  const _Greeting();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(clockProvider)().toLocal();
    final user =
        ref.watch(authStateProvider).value ??
        ref.watch(authRepositoryProvider).currentUser;
    final display = user?.displayName?.trim();
    final name = (display != null && display.isNotEmpty)
        ? display.split(RegExp(r'\s+')).first
        : null;
    final hello = switch (now.hour) {
      < 5 => 'Good evening',
      < 12 => 'Good morning',
      < 18 => 'Good afternoon',
      _ => 'Good evening',
    };
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name == null ? hello : '$hello, $name',
          key: const Key('dashboard-greeting'),
          style: theme.textTheme.headlineSmall,
        ),
        Gaps.h4,
        Text(
          DateFormat.MMMMEEEEd().format(now),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppColors.of(context).mutedText,
          ),
        ),
      ],
    );
  }
}

/// First-run guide plus quick actions.
class _FreshStart extends ConsumerWidget {
  const _FreshStart();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subjects = ref.watch(subjectsProvider).value ?? const <Subject>[];
    final notes = ref.watch(recentNotesProvider);
    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: ContentWidth.form),
        child: GettingStartedCard(
          hasSubjects: subjects.isNotEmpty,
          hasNotes: notes.isNotEmpty,
        ),
      ),
    );
  }
}

class _DashboardBody extends ConsumerWidget {
  const _DashboardBody({required this.stats});

  final DashboardStats stats;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(dashboardTodayProvider);
    final days = ref.watch(activityDaysProvider).value ?? const <DateTime>{};
    final notes = ref.watch(recentNotesProvider);
    final now = ref.watch(clockProvider)();
    final feed = buildActivityFeed(stats.recentActivity, notes);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final cols = width >= DashboardScreen._threeColumns
            ? 3
            : width >= DashboardScreen._twoColumns
            ? 2
            : 1;
        StreakCard streak({bool expand = false}) => StreakCard(
          streak: stats.streak,
          days: days,
          today: today,
          expand: expand,
        );
        TodayCard todayCard({bool expand = false}) => TodayCard(
          due: stats.due,
          openMistakes: stats.openMistakes,
          expand: expand,
        );
        QuizzesCard quizzes({bool expand = false}) => QuizzesCard(
          quizzesTaken: stats.quizzesTaken,
          accuracy: stats.overallAccuracy,
          expand: expand,
        );

        final Widget tiles = switch (cols) {
          3 => _EqualRow(
            children: [
              todayCard(expand: true),
              streak(expand: true),
              quizzes(expand: true),
            ],
          ),
          2 => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              todayCard(),
              Gaps.h16,
              _EqualRow(
                children: [streak(expand: true), quizzes(expand: true)],
              ),
            ],
          ),
          _ => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [todayCard(), Gaps.h12, streak(), Gaps.h12, quizzes()],
          ),
        };

        final left = [
          DashboardSection(
            key: const Key('dashboard-accuracy-section'),
            title: 'Accuracy by subject',
            child: SubjectAccuracyList(items: stats.accuracyBySubject),
          ),
          DashboardSection(
            key: const Key('dashboard-weakest-section'),
            title: 'Weakest topics',
            subtitle: 'Questions you miss most often',
            padding: const EdgeInsets.symmetric(vertical: Insets.xs),
            child: WeakestTopicsList(
              questions: stats.weakestQuestions,
              quizzes: stats.weakestQuizzes,
            ),
          ),
        ];
        final right = [
          const DashboardSection(title: 'Quick actions', child: QuickActions()),
          DashboardSection(
            key: const Key('dashboard-activity-section'),
            title: 'Recent activity',
            padding: const EdgeInsets.symmetric(vertical: Insets.xs),
            child: ActivityFeed(entries: feed, now: now),
          ),
        ];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            tiles,
            Gaps.h24,
            if (cols >= 2)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: cols == 3 ? 3 : 1,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: left,
                    ),
                  ),
                  Gaps.w16,
                  Expanded(
                    flex: cols == 3 ? 2 : 1,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: right,
                    ),
                  ),
                ],
              )
            else ...[
              right.first,
              ...left,
              right.last,
            ],
          ],
        );
      },
    );
  }
}

/// Cards side by side with equal heights.
class _EqualRow extends StatelessWidget {
  const _EqualRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, c) in children.indexed) ...[
            if (i > 0) Gaps.w16,
            Expanded(child: c),
          ],
        ],
      ),
    );
  }
}
