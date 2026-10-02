import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/widgets/design_system.dart';
import '../../../core/widgets/sync_status_indicator.dart'
    show formatRelativeTime;
import '../../../data/models/models.dart';
import '../../../study/due_queue.dart';
import '../../../study/stats.dart';
import '../application/dashboard_actions.dart';
import '../application/dashboard_providers.dart';
import 'charts.dart';

/// Small muted label at the top of a stat card.
class _CardLabel extends StatelessWidget {
  const _CardLabel(this.text, {this.icon, this.trailing});

  final String text;
  final IconData? icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 16, color: colors.mutedText),
          Gaps.w8,
        ],
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: colors.mutedText),
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// Big number with a small unit after it ("12 day streak").
class _BigNumber extends StatelessWidget {
  const _BigNumber(this.value, this.unit, {this.valueKey});

  final String value;
  final String unit;
  final Key? valueKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text.rich(
      key: valueKey,
      TextSpan(
        children: [
          TextSpan(
            text: value,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w600,
              height: 1.1,
            ),
          ),
          TextSpan(
            text: '  $unit',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.of(context).mutedText,
            ),
          ),
        ],
      ),
    );
  }
}

TextStyle? _muted(BuildContext context) =>
    Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: AppColors.of(context).mutedText);

// -----------------------------------------------------------------------------
// Stat cards
// -----------------------------------------------------------------------------

/// Current/best streak and a 7- or 30-day activity strip.
class StreakCard extends StatefulWidget {
  const StreakCard({
    super.key,
    required this.streak,
    required this.days,
    required this.today,
    this.expand = false,
  });

  /// Pin the bottom content to the card's bottom (inside an equal-height
  /// row). Requires a bounded height.
  final bool expand;
  final StreakInfo streak;
  final Set<DateTime> days;
  final DateTime today;

  @override
  State<StreakCard> createState() => _StreakCardState();
}

class _StreakCardState extends State<StreakCard> {
  int _length = 7;

  @override
  Widget build(BuildContext context) {
    final s = widget.streak;
    final hint = s.activeToday
        ? 'You studied today. Nice!'
        : s.current > 0
        ? 'Study today to keep it going'
        : 'Study today to start a streak';
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardLabel(
            'Streak',
            icon: Icons.local_fire_department_outlined,
            trailing: Text(
              'Best ${s.longest}',
              key: const Key('dashboard-streak-best'),
              style: _muted(context),
            ),
          ),
          Gaps.h8,
          _BigNumber(
            '${s.current}',
            s.current == 1 ? 'day' : 'days',
            valueKey: const Key('dashboard-streak-current'),
          ),
          Gaps.h4,
          Text(hint, style: _muted(context)),
          if (widget.expand) const Spacer(),
          Gaps.h12,
          Row(
            children: [
              Expanded(
                child: Text(
                  'Last $_length days',
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: AppColors.of(context).mutedText),
                ),
              ),
              _RangeToggle(
                value: _length,
                onChanged: (v) => setState(() => _length = v),
              ),
            ],
          ),
          Gaps.h8,
          ActivityStrip(
            key: ValueKey('dashboard-strip-$_length'),
            days: widget.days,
            today: widget.today,
            length: _length,
          ),
        ],
      ),
    );
  }
}

class _RangeToggle extends StatelessWidget {
  const _RangeToggle({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    Widget option(int v, String label) {
      final selected = v == value;
      return InkWell(
        key: Key('dashboard-range-$v'),
        borderRadius: Radii.smAll,
        onTap: () => onChanged(v),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Insets.sm,
            vertical: Insets.xxs,
          ),
          decoration: BoxDecoration(
            color: selected ? colors.pressed : null,
            borderRadius: Radii.smAll,
          ),
          child: Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: selected ? theme.colorScheme.onSurface : colors.mutedText,
              fontWeight: selected ? FontWeight.w600 : null,
            ),
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [option(7, '7d'), Gaps.w4, option(30, '30d')],
    );
  }
}

/// Today's flashcards ("Study now") and open mistakes.
class TodayCard extends StatelessWidget {
  const TodayCard({
    super.key,
    required this.due,
    required this.openMistakes,
    this.expand = false,
  });

  final bool expand;
  final DueQueue due;
  final int openMistakes;

  @override
  Widget build(BuildContext context) {
    final reviews = due.dueNow.length + due.laterToday.length;
    final summary = due.isEmpty
        ? (due.unseenTotal > 0
              ? 'All caught up. New cards come back tomorrow.'
              : 'All caught up.')
        : '$reviews to review · ${due.newCards.length} new';
    final colors = AppColors.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _CardLabel('Due today', icon: Icons.style_outlined),
          Gaps.h8,
          _BigNumber(
            '${due.count}',
            due.count == 1 ? 'card' : 'cards',
            valueKey: const Key('dashboard-due-count'),
          ),
          Gaps.h4,
          Text(summary, style: _muted(context)),
          Gaps.h12,
          Align(
            alignment: Alignment.centerLeft,
            child: due.isEmpty
                ? FilledButton.tonalIcon(
                    key: const Key('dashboard-study-now'),
                    onPressed: () => context.go(AppRoutes.study),
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: const Text('Open study'),
                  )
                : FilledButton.icon(
                    key: const Key('dashboard-study-now'),
                    onPressed: () => context.go(AppRoutes.study),
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: const Text('Study now'),
                  ),
          ),
          if (expand) const Spacer(),
          Gaps.h12,
          Divider(height: 1, color: colors.hairline),
          Gaps.h8,
          Row(
            children: [
              Icon(Icons.replay_outlined, size: 16, color: colors.mutedText),
              Gaps.w8,
              Expanded(
                child: Text(
                  openMistakes == 0
                      ? 'No open mistakes'
                      : '$openMistakes open mistake${openMistakes == 1 ? '' : 's'}',
                  key: const Key('dashboard-mistakes-count'),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              if (openMistakes > 0)
                TextButton(
                  key: const Key('dashboard-mistakes'),
                  onPressed: () => context.push(AppRoutes.mistakes),
                  child: const Text('Review'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Quizzes taken and overall accuracy.
class QuizzesCard extends StatelessWidget {
  const QuizzesCard({
    super.key,
    required this.quizzesTaken,
    required this.accuracy,
    this.expand = false,
  });

  final bool expand;
  final int quizzesTaken;
  final Accuracy accuracy;

  @override
  Widget build(BuildContext context) {
    final ratio = accuracy.ratio;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _CardLabel('Quizzes', icon: Icons.quiz_outlined),
          Gaps.h8,
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: _BigNumber(
                  '$quizzesTaken',
                  'taken',
                  valueKey: const Key('dashboard-quizzes-taken'),
                ),
              ),
              Expanded(
                child: _BigNumber(
                  formatPercent(ratio),
                  'accuracy',
                  valueKey: const Key('dashboard-accuracy'),
                ),
              ),
            ],
          ),
          Gaps.h4,
          Text(
            accuracy.answered == 0
                ? 'Take a quiz to see your accuracy.'
                : '${accuracy.correct} of ${accuracy.answered} answers correct',
            style: _muted(context),
          ),
          if (expand) const Spacer(),
          Gaps.h12,
          AccuracyBar(ratio: ratio ?? 0),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Sections
// -----------------------------------------------------------------------------

/// Titled section with a card body.
class DashboardSection extends StatelessWidget {
  const DashboardSection({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
    this.padding = Insets.card,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: title,
            subtitle: subtitle,
            trailing: trailing,
            padding: const EdgeInsets.only(bottom: Insets.sm),
          ),
          AppCard(padding: padding, child: child),
        ],
      ),
    );
  }
}

/// Accuracy per subject: color dot, title, percent and a thin bar.
class SubjectAccuracyList extends StatelessWidget {
  const SubjectAccuracyList({super.key, required this.items});

  final List<SubjectAccuracy> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const EmptyState(
        compact: true,
        icon: Icons.bar_chart_outlined,
        title: 'No results yet',
        message: 'Take a quiz to see your accuracy per subject.',
      );
    }
    final theme = Theme.of(context);
    return Column(
      children: [
        for (final (i, s) in items.indexed) ...[
          if (i > 0) Gaps.h16,
          Semantics(
            label:
                '${s.title.isEmpty ? 'Subject' : s.title}: '
                '${formatPercent(s.accuracy.ratio)} correct',
            excludeSemantics: true,
            child: Column(
              key: Key('dashboard-subject-${s.subjectId}'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    SubjectColorDot(color: s.color),
                    Gaps.w8,
                    Expanded(
                      child: Text(
                        s.title.isEmpty ? 'Untitled subject' : s.title,
                        style: theme.textTheme.bodyMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Gaps.w8,
                    Text(
                      '${s.attempts} quiz${s.attempts == 1 ? '' : 'zes'}',
                      style: _muted(context),
                    ),
                    Gaps.w12,
                    SizedBox(
                      width: 40,
                      child: Text(
                        formatPercent(s.accuracy.ratio),
                        textAlign: TextAlign.end,
                        style: theme.textTheme.labelLarge,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                AccuracyBar(ratio: s.accuracy.ratio ?? 0),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Lowest-accuracy questions (or quizzes); tap opens the quiz.
class WeakestTopicsList extends StatelessWidget {
  const WeakestTopicsList({
    super.key,
    required this.questions,
    required this.quizzes,
  });

  final List<WeakQuestion> questions;
  final List<WeakQuiz> quizzes;

  @override
  Widget build(BuildContext context) {
    if (questions.isEmpty && quizzes.isEmpty) {
      return const Padding(
        padding: Insets.card,
        child: EmptyState(
          compact: true,
          icon: Icons.trending_up,
          title: 'Nothing to work on yet',
          message: 'Questions you miss more than once will show up here.',
        ),
      );
    }
    return Column(
      children: [
        if (questions.isNotEmpty)
          for (final q in questions)
            ListRowTile(
              key: Key('dashboard-weak-${q.quizId}-${q.questionId}'),
              leading: _PercentBadge(ratio: q.accuracy.ratio),
              title: Text(
                q.prompt,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${q.quizTitle} · ${q.accuracy.correct}/${q.accuracy.answered} correct',
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.chevron_right, size: 18),
              onTap: () => context.push(AppRoutes.quiz(q.quizId)),
            )
        else
          for (final q in quizzes)
            ListRowTile(
              key: Key('dashboard-weak-quiz-${q.quizId}'),
              leading: _PercentBadge(ratio: q.accuracy.ratio),
              title: Text(q.title, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                '${q.attempts} attempts · ${q.accuracy.correct}/${q.accuracy.answered} correct',
              ),
              trailing: const Icon(Icons.chevron_right, size: 18),
              onTap: () => context.push(AppRoutes.quiz(q.quizId)),
            ),
      ],
    );
  }
}

class _PercentBadge extends StatelessWidget {
  const _PercentBadge({required this.ratio});

  final double? ratio;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      width: 44,
      padding: const EdgeInsets.symmetric(vertical: Insets.xxs),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: Radii.smAll,
        border: Border.all(color: colors.hairline),
      ),
      child: Text(
        formatPercent(ratio),
        style: Theme.of(context).textTheme.labelMedium,
      ),
    );
  }
}

/// Recent attempts, review sessions and new notes.
class ActivityFeed extends StatelessWidget {
  const ActivityFeed({super.key, required this.entries, required this.now});

  final List<FeedEntry> entries;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const Padding(
        padding: Insets.card,
        child: EmptyState(
          compact: true,
          icon: Icons.history,
          title: 'No activity yet',
        ),
      );
    }
    return Column(children: [for (final e in entries) _row(context, e)]);
  }

  Widget _row(BuildContext context, FeedEntry entry) {
    final colors = AppColors.of(context);
    final when = formatRelativeTime(entry.at, now: now);
    Widget icon(IconData data) => Icon(data, size: 18, color: colors.mutedText);
    switch (entry) {
      case NoteFeedEntry(:final note):
        return ListRowTile(
          dense: true,
          leading: icon(Icons.description_outlined),
          title: Text(
            note.title.isEmpty ? 'Untitled note' : note.title,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text('New note · $when'),
          onTap: () => context.push(AppRoutes.note(note.id)),
        );
      case StudyFeedEntry(item: final QuizActivity a):
        final attempt = a.attempt;
        final mode = switch (a.mode) {
          AttemptMode.exam => 'Exam',
          AttemptMode.mistakes => 'Mistakes practice',
          AttemptMode.practice => 'Quiz',
        };
        final score = attempt.total > 0
            ? ' · ${attempt.score.round()}/${attempt.total}'
            : '';
        return ListRowTile(
          dense: true,
          leading: icon(
            a.mode == AttemptMode.exam
                ? Icons.timer_outlined
                : Icons.quiz_outlined,
          ),
          title: Text(a.quizTitle, overflow: TextOverflow.ellipsis),
          subtitle: Text('$mode$score · $when'),
          onTap: () => context.push(AppRoutes.quiz(attempt.quizId)),
        );
      case StudyFeedEntry(item: final ReviewActivity r):
        return ListRowTile(
          dense: true,
          leading: icon(Icons.style_outlined),
          title: Text(r.deckTitle, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            'Reviewed ${r.cards} card${r.cards == 1 ? '' : 's'} · $when',
          ),
          onTap: () => context.push(AppRoutes.deck(r.deckId)),
        );
    }
  }
}

/// New subject, new note and (behind [AiGate]) generate with AI.
class QuickActions extends ConsumerWidget {
  const QuickActions({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void generate() => DashboardActions.generate(context);
    return Wrap(
      spacing: Insets.sm,
      runSpacing: Insets.sm,
      children: [
        OutlinedButton.icon(
          key: const Key('dashboard-new-subject'),
          onPressed: () => DashboardActions.newSubject(context, ref),
          icon: const Icon(Icons.create_new_folder_outlined, size: 18),
          label: const Text('New subject'),
        ),
        OutlinedButton.icon(
          key: const Key('dashboard-new-note'),
          onPressed: () => DashboardActions.newNote(context, ref),
          icon: const Icon(Icons.note_add_outlined, size: 18),
          label: const Text('New note'),
        ),
        AiGate(
          key: const Key('dashboard-generate'),
          onReady: generate,
          child: OutlinedButton.icon(
            onPressed: generate,
            icon: const Icon(Icons.auto_awesome_outlined, size: 18),
            label: const Text('Generate with AI'),
          ),
        ),
      ],
    );
  }
}

/// First-run guide: create a subject → add notes → generate a quiz.
class GettingStartedCard extends ConsumerWidget {
  const GettingStartedCard({
    super.key,
    required this.hasSubjects,
    required this.hasNotes,
  });

  final bool hasSubjects;
  final bool hasNotes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    void generate() => DashboardActions.generate(context);
    return AppCard(
      key: const Key('dashboard-getting-started'),
      padding: const EdgeInsets.all(Insets.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Get started', style: theme.textTheme.titleMedium),
          Gaps.h4,
          Text(
            'Three steps to your first quiz. Your progress, streak and due '
            'cards will show up here.',
            style: _muted(context),
          ),
          Gaps.h16,
          _GuideStep(
            number: 1,
            done: hasSubjects,
            title: 'Create a subject',
            message: 'A home for everything about one topic.',
            action: OutlinedButton(
              key: const Key('guide-new-subject'),
              onPressed: () => DashboardActions.newSubject(context, ref),
              child: const Text('New subject'),
            ),
          ),
          _GuideStep(
            number: 2,
            done: hasNotes,
            title: 'Add notes',
            message: 'Write or paste what you are learning.',
            action: OutlinedButton(
              key: const Key('guide-new-note'),
              onPressed: () => DashboardActions.newNote(context, ref),
              child: const Text('New note'),
            ),
          ),
          _GuideStep(
            number: 3,
            done: false,
            last: true,
            title: 'Generate a quiz',
            message:
                'Let AI turn your notes into questions, then test '
                'yourself.',
            action: AiGate(
              key: const Key('guide-generate'),
              onReady: generate,
              child: FilledButton.tonal(
                onPressed: generate,
                child: const Text('Generate'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GuideStep extends StatelessWidget {
  const _GuideStep({
    required this.number,
    required this.done,
    required this.title,
    required this.message,
    required this.action,
    this.last = false,
  });

  final int number;
  final bool done;
  final bool last;
  final String title;
  final String message;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final marker = Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done ? theme.colorScheme.primary : null,
        border: done ? null : Border.all(color: colors.border),
      ),
      child: done
          ? Icon(Icons.check, size: 14, color: theme.colorScheme.onPrimary)
          : Text('$number', style: theme.textTheme.labelSmall),
    );
    return Semantics(
      label: done ? 'Step $number, done' : 'Step $number',
      child: Padding(
        padding: EdgeInsets.only(bottom: last ? 0 : Insets.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            marker,
            Gaps.w12,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      decoration: done ? TextDecoration.lineThrough : null,
                      color: done ? colors.mutedText : null,
                    ),
                  ),
                  Gaps.h2,
                  Text(message, style: _muted(context)),
                ],
              ),
            ),
            Gaps.w12,
            if (!done) action,
          ],
        ),
      ),
    );
  }
}
