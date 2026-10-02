import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../ai/llm_provider.dart';
import '../../../core/router/routes.dart';
import '../../../core/widgets/design_system.dart' hide MaxWidth;
import '../../../core/widgets/export_menu.dart';
import '../../../core/widgets/pin_button.dart';
import '../../../core/widgets/tag_widgets.dart';
import '../../../data/data_providers.dart';
import '../../../data/models/question.dart';
import '../../../data/models/quiz.dart';
import '../../../data/models/quiz_attempt.dart';
import '../../../data/models/share.dart';
import '../../../data/models/syncable.dart';
import '../../../data/repositories/organization_repository.dart';
import '../../sharing/widgets/share_actions.dart';
import '../../sharing/widgets/shared_by_chip.dart';
import '../application/quiz_io_actions.dart';
import '../domain/exam_session.dart';
import '../widgets/exam_setup.dart';
import '../widgets/quiz_format.dart';
import '../widgets/score_trend.dart';
import '../widgets/source_summary.dart';

/// Overview of one quiz: info, source, play, attempt history, owner actions.
class QuizDetailScreen extends ConsumerWidget {
  const QuizDetailScreen({super.key, required this.quizId});

  final String quizId;

  Future<void> _delete(BuildContext context, WidgetRef ref, Quiz quiz) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete quiz?'),
        content: Text(
          '"${quiz.title}" and its questions will be deleted. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await ref.read(quizRepositoryProvider).delete(quiz.id);
      if (!context.mounted) return;
      if (context.canPop()) {
        context.pop();
      } else {
        context.go(AppRoutes.subject(quiz.subjectId));
      }
    } on Object catch (e) {
      if (context.mounted) showSnack(context, errorText(e));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quizAsync = ref.watch(quizProvider(quizId));
    final userId = ref.watch(currentUserIdProvider);
    final quiz = quizAsync.value;
    final owner = quiz != null && quiz.isOwnedBy(userId);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          quiz?.title ?? 'Quiz',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (quiz != null && owner) ...[
            PinButton.item(
              kind: TaggableKind.quiz,
              id: quiz.id,
              pinned: quiz.pinned,
            ),
            IconButton(
              tooltip: 'Share',
              icon: const Icon(Icons.ios_share_outlined),
              onPressed: () => showShareSheet(
                context,
                type: ShareResourceType.quiz,
                resourceId: quiz.id,
                title: quiz.title,
              ),
            ),
            IconButton(
              tooltip: 'Edit',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => context.push(AppRoutes.quizEdit(quiz.id)),
            ),
            ExportMenu(items: quizExportItems(quiz)),
            PopupMenuButton<String>(
              key: const Key('quiz-more'),
              tooltip: 'More',
              icon: const Icon(Icons.more_horiz),
              onSelected: (v) => switch (v) {
                'tags' => editItemTags(
                  context,
                  ref,
                  kind: TaggableKind.quiz,
                  id: quiz.id,
                  tags: quiz.tags,
                ),
                'delete' => _delete(context, ref, quiz),
                _ => null,
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  key: Key('quiz-edit-tags'),
                  value: 'tags',
                  child: ListTile(
                    leading: Icon(Icons.sell_outlined),
                    title: Text('Edit tags'),
                  ),
                ),
                PopupMenuDivider(),
                PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    leading: Icon(Icons.delete_outline),
                    title: Text('Delete quiz'),
                  ),
                ),
              ],
            ),
            Gaps.w8,
          ] else if (quiz != null) ...[
            ExportMenu(items: quizExportItems(quiz)),
            Padding(
              padding: const EdgeInsets.only(right: Insets.sm),
              child: CopyToAccountButton(
                type: ShareResourceType.quiz,
                resourceId: quiz.id,
                compact: true,
              ),
            ),
          ],
        ],
      ),
      body: switch (quizAsync) {
        AsyncValue(:final value?) => _DetailBody(quiz: value, owner: owner),
        AsyncValue(hasValue: true) => EmptyState(
          icon: Icons.search_off,
          title: 'Quiz not found',
          message: 'It may have been deleted or is no longer shared with you.',
          action: OutlinedButton(
            onPressed: () => context.go(AppRoutes.subjects),
            child: const Text('Go to subjects'),
          ),
        ),
        AsyncValue(:final error?) => EmptyState(
          icon: Icons.error_outline,
          title: 'Could not load the quiz',
          message: errorText(error),
        ),
        _ => const ContentContainer(
          child: Padding(
            padding: EdgeInsets.only(top: Insets.xl),
            child: LoadingSkeleton(rows: 4),
          ),
        ),
      },
    );
  }
}

class _DetailBody extends ConsumerWidget {
  const _DetailBody({required this.quiz, required this.owner});

  final Quiz quiz;
  final bool owner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attemptsAsync = ref.watch(attemptsByQuizProvider(quiz.id));
    final attempts = completedAttempts(attemptsAsync.value ?? const []);
    final info = _InfoSection(quiz: quiz, owner: owner, attempts: attempts);
    final history = _HistorySection(
      attempts: attempts,
      loading: attemptsAsync.isLoading && !attemptsAsync.hasValue,
    );
    final hasSource = _SourceSection.hasContent(quiz);
    final source = hasSource ? _SourceSection(quiz: quiz) : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= Breakpoints.expanded;
        final padding = Breakpoints.isMedium(context)
            ? Insets.pageWide
            : Insets.page;
        if (wide) {
          return SingleChildScrollView(
            child: ContentContainer(
              maxWidth: ContentWidth.wide,
              padding: padding,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 5,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [info, ?source],
                    ),
                  ),
                  Gaps.w32,
                  Expanded(flex: 4, child: history),
                ],
              ),
            ),
          );
        }
        return SingleChildScrollView(
          child: ContentContainer(
            padding: padding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [info, history, ?source],
            ),
          ),
        );
      },
    );
  }
}

class _InfoSection extends ConsumerWidget {
  const _InfoSection({
    required this.quiz,
    required this.owner,
    required this.attempts,
  });

  final Quiz quiz;
  final bool owner;
  final List<QuizAttempt> attempts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final subject = ref.watch(subjectProvider(quiz.subjectId)).value;
    final note = quiz.noteId == null
        ? null
        : ref.watch(noteProvider(quiz.noteId!)).value;
    final byType = <QuestionType, int>{};
    for (final q in quiz.questions) {
      byType[q.type] = (byType[q.type] ?? 0) + 1;
    }
    final percents = [for (final a in attempts) ?attemptPercent(a)];
    final best = percents.isEmpty
        ? null
        : percents.reduce((a, b) => a > b ? a : b);
    final last = percents.isEmpty ? null : percents.first;
    final count = quiz.questions.length;
    final description = quiz.description?.trim() ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: Insets.xs,
          runSpacing: Insets.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (subject != null)
              _Crumb(
                leading: SubjectColorDot(color: subject.color),
                label: subject.title,
                onTap: () => context.push(AppRoutes.subject(subject.id)),
              ),
            if (subject != null && note != null)
              Icon(Icons.chevron_right, size: 16, color: colors.faintText),
            if (note != null)
              _Crumb(
                leading: Icon(
                  Icons.description_outlined,
                  size: 16,
                  color: colors.mutedText,
                ),
                label: note.title,
                onTap: () => context.push(AppRoutes.note(note.id)),
              ),
            if (!owner) SharedByChip(ownerId: quiz.ownerId),
          ],
        ),
        Gaps.h12,
        Text(quiz.title, style: theme.textTheme.headlineMedium),
        if (quiz.tags.isNotEmpty || owner) ...[
          Gaps.h8,
          Wrap(
            spacing: Insets.xs,
            runSpacing: Insets.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TagChips(tags: quiz.tags),
              if (owner)
                TextButton.icon(
                  key: const Key('quiz-tags-button'),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 28),
                    visualDensity: VisualDensity.compact,
                    foregroundColor: colors.mutedText,
                  ),
                  onPressed: () => editItemTags(
                    context,
                    ref,
                    kind: TaggableKind.quiz,
                    id: quiz.id,
                    tags: quiz.tags,
                  ),
                  icon: Icon(
                    quiz.tags.isEmpty
                        ? Icons.sell_outlined
                        : Icons.edit_outlined,
                    size: 16,
                  ),
                  label: Text(quiz.tags.isEmpty ? 'Add tags' : 'Edit'),
                ),
            ],
          ),
        ],
        if (description.isNotEmpty) ...[
          Gaps.h8,
          Text(
            description,
            style: theme.textTheme.bodyLarge?.copyWith(color: colors.mutedText),
          ),
        ],
        Gaps.h24,
        AppCard(
          padding: const EdgeInsets.symmetric(
            horizontal: Insets.lg,
            vertical: Insets.md,
          ),
          child: Wrap(
            spacing: Insets.xxl,
            runSpacing: Insets.md,
            children: [
              _Stat(label: 'Questions', value: '$count'),
              _Stat(label: 'Attempts', value: '${attempts.length}'),
              _Stat(
                label: 'Best',
                value: formatPercent(best),
                color: best == null ? null : scoreColor(context, best),
              ),
              _Stat(label: 'Last', value: formatPercent(last)),
            ],
          ),
        ),
        if (byType.isNotEmpty) ...[
          Gaps.h12,
          Wrap(
            spacing: Insets.sm,
            runSpacing: Insets.sm,
            children: [
              for (final t in QuestionType.values)
                if (byType[t] != null)
                  Chip(
                    avatar: Icon(questionTypeIcon(t), size: 16),
                    label: Text('${questionTypeLabel(t)} · ${byType[t]}'),
                    visualDensity: VisualDensity.compact,
                  ),
            ],
          ),
        ],
        Gaps.h24,
        _PlayActions(quiz: quiz, owner: owner),
        if (count == 0) ...[
          Gaps.h12,
          Text(
            owner
                ? 'Add questions to play this quiz.'
                : 'This quiz has no questions yet.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.mutedText,
            ),
          ),
        ],
      ],
    );
  }
}

/// Quiet breadcrumb link (subject / note).
class _Crumb extends StatelessWidget {
  const _Crumb({
    required this.leading,
    required this.label,
    required this.onTap,
  });

  final Widget leading;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: Radii.smAll,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Insets.xs,
          vertical: Insets.xxs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            leading,
            Gaps.w8,
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 240),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: AppColors.of(context).mutedText,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: theme.textTheme.titleLarge?.copyWith(
            color: color,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: AppColors.of(context).mutedText,
          ),
        ),
      ],
    );
  }
}

class _HistorySection extends StatelessWidget {
  const _HistorySection({required this.attempts, required this.loading});

  final List<QuizAttempt> attempts;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    // Oldest -> newest for the trend.
    final chronological = attempts.reversed
        .map(attemptPercent)
        .whereType<int>()
        .toList();
    final recent = chronological.length > 20
        ? chronological.sublist(chronological.length - 20)
        : chronological;
    int? delta;
    if (chronological.length >= 2) {
      delta = chronological.last - chronological[chronological.length - 2];
    }

    Widget? trend;
    if (delta != null) {
      final color = delta > 0
          ? colors.success
          : delta < 0
          ? colors.danger
          : colors.mutedText;
      trend = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            delta > 0
                ? Icons.trending_up
                : delta < 0
                ? Icons.trending_down
                : Icons.trending_flat,
            size: 16,
            color: color,
          ),
          Gaps.w4,
          Text(
            delta == 0
                ? 'Same as before'
                : '${delta > 0 ? '+' : ''}$delta% vs previous',
            style: theme.textTheme.labelMedium?.copyWith(color: color),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'Your attempts',
          count: attempts.isEmpty ? null : attempts.length,
          trailing: trend,
          padding: const EdgeInsets.only(top: Insets.xl, bottom: Insets.sm),
        ),
        if (loading)
          const LoadingSkeleton(rows: 3)
        else if (attempts.isEmpty)
          const EmptyState(
            compact: true,
            icon: Icons.insights_outlined,
            title: 'No attempts yet',
            message: 'Play the quiz to track your progress.',
          )
        else ...[
          if (recent.length >= 2) ...[
            SizedBox(height: 64, child: ScoreTrend(percents: recent)),
            Gaps.h12,
          ],
          for (final a in attempts.take(30)) _AttemptRow(attempt: a),
          if (attempts.length > 30)
            Padding(
              padding: const EdgeInsets.all(Insets.md),
              child: Text(
                'Showing the latest 30 of ${attempts.length} attempts.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.mutedText,
                ),
              ),
            ),
        ],
      ],
    );
  }
}

/// Play, Exam (setup dialog) and "Practice mistakes (N)".
class _PlayActions extends ConsumerWidget {
  const _PlayActions({required this.quiz, required this.owner});

  final Quiz quiz;
  final bool owner;

  Future<void> _startExam(BuildContext context, WidgetRef ref) async {
    final config = await showExamSetupDialog(
      context,
      total: quiz.questions.length,
    );
    if (config == null || !context.mounted) return;
    ref.read(pendingExamConfigProvider.notifier).put(quiz.id, config);
    await context.push(AppRoutes.quizPlay(quiz.id, mode: 'exam'));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = quiz.questions.length;
    final groups = ref.watch(openMistakesProvider).value ?? const [];
    final mistakes = groups
        .where((g) => g.quiz.id == quiz.id)
        .fold<int>(0, (n, g) => n + g.entries.length);
    return Wrap(
      spacing: Insets.sm,
      runSpacing: Insets.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        FilledButton.icon(
          key: const Key('play-quiz'),
          style: FilledButton.styleFrom(minimumSize: const Size(140, 44)),
          onPressed: count == 0
              ? null
              : () => context.push(AppRoutes.quizPlay(quiz.id)),
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('Play'),
        ),
        FilledButton.tonalIcon(
          key: const Key('exam-quiz'),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: count == 0 ? null : () => _startExam(context, ref),
          icon: const Icon(Icons.timer_outlined, size: 18),
          label: const Text('Exam'),
        ),
        if (mistakes > 0)
          OutlinedButton.icon(
            key: const Key('practice-mistakes'),
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () =>
                context.push(AppRoutes.quizPlay(quiz.id, mode: 'mistakes')),
            icon: const Icon(Icons.replay_circle_filled_outlined, size: 18),
            label: Text('Practice mistakes ($mistakes)'),
          ),
        if (count == 0 && owner)
          OutlinedButton.icon(
            onPressed: () => context.push(AppRoutes.quizEdit(quiz.id)),
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Edit questions'),
          ),
      ],
    );
  }
}

class _AttemptRow extends StatelessWidget {
  const _AttemptRow({required this.attempt});

  final QuizAttempt attempt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final p = attemptPercent(attempt);
    final color = scoreColor(context, p);
    final mode = attemptModeLabel(attempt.mode);
    final limit = attempt.timeLimitSeconds;
    final details = [
      '${attempt.score.round()} of ${attempt.total} correct',
      limit == null
          ? formatDuration(attemptDuration(attempt))
          : '${formatDuration(attemptDuration(attempt))} of '
                '${formatTimeLimit(limit)}',
    ];
    return ListRowTile(
      dense: true,
      leading: SizedBox.square(
        dimension: 20,
        child: CircularProgressIndicator(
          value: (p ?? 0) / 100,
          strokeWidth: 2.5,
          color: color,
          backgroundColor: colors.skeleton,
        ),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              formatDateTime(attempt.completedAt!),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (mode != null) ...[Gaps.w8, AttemptModeBadge(label: mode)],
        ],
      ),
      subtitle: Text(details.join(' · ')),
      trailing: Text(
        formatPercent(p),
        style: theme.textTheme.titleSmall?.copyWith(
          color: color,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// Small neutral pill ("Exam", "Mistakes") next to an attempt.
class AttemptModeBadge extends StatelessWidget {
  const AttemptModeBadge({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Insets.sm - 2,
        vertical: 1,
      ),
      decoration: BoxDecoration(
        color: colors.hover,
        borderRadius: Radii.xsAll,
        border: Border.all(color: colors.hairline),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: colors.mutedText),
      ),
    );
  }
}

class _SourceSection extends StatefulWidget {
  const _SourceSection({required this.quiz});

  final Quiz quiz;

  static bool hasContent(Quiz quiz) {
    final s = quiz.source;
    return s != null &&
        ((s.contextText?.trim().isNotEmpty ?? false) ||
            (s.youtubeUrl?.trim().isNotEmpty ?? false) ||
            s.provider != null ||
            sourceSummaryOf(s).isNotEmpty);
  }

  @override
  State<_SourceSection> createState() => _SourceSectionState();
}

class _SourceSectionState extends State<_SourceSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final s = widget.quiz.source!;
    final provider = LlmProviderId.fromWireName(s.provider);
    final contextText = s.contextText?.trim() ?? '';
    final youtube = s.youtubeUrl?.trim() ?? '';
    final summary = [
      for (final e in sourceSummaryOf(s))
        if (youtube.isEmpty || e.label.trim() != youtube) e,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'Source',
          padding: const EdgeInsets.only(top: Insets.xl, bottom: Insets.sm),
          subtitle: s.provider == null
              ? null
              : 'Generated with ${provider?.displayName ?? s.provider}'
                    '${s.model != null ? ' · ${s.model}' : ''}',
        ),
        for (final e in summary)
          ListRowTile(
            dense: true,
            leading: Icon(e.icon),
            title: Text(e.label),
            subtitle: e.detail == null ? null : Text(e.detail!),
            trailing: Text(e.kindLabel),
          ),
        if (youtube.isNotEmpty)
          ListRowTile(
            dense: true,
            leading: const Icon(Icons.smart_display_outlined),
            title: Text(youtube),
            trailing: const Text('YouTube'),
            actions: [
              IconButton(
                tooltip: 'Copy link',
                icon: const Icon(Icons.copy_outlined),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: youtube));
                  if (context.mounted) showSnack(context, 'Link copied');
                },
              ),
            ],
          ),
        if (contextText.isNotEmpty) ...[
          Gaps.h8,
          Container(
            width: double.infinity,
            padding: Insets.card,
            decoration: BoxDecoration(
              color: colors.sidebar,
              borderRadius: Radii.mdAll,
              border: Border.all(color: colors.hairline),
            ),
            child: Text(
              contextText,
              maxLines: _expanded ? null : 6,
              overflow: _expanded ? null : TextOverflow.fade,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.mutedText,
              ),
            ),
          ),
          if (contextText.length > 400 ||
              '\n'.allMatches(contextText).length > 5)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() => _expanded = !_expanded),
                child: Text(_expanded ? 'Show less' : 'Show more'),
              ),
            ),
        ],
      ],
    );
  }
}
