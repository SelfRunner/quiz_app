import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../ai/llm_provider.dart';
import '../../../core/router/routes.dart';
import '../../../data/data_providers.dart';
import '../../../data/models/question.dart';
import '../../../data/models/quiz.dart';
import '../../../data/models/quiz_attempt.dart';
import '../../../data/models/share.dart';
import '../../../data/models/syncable.dart';
import '../../sharing/widgets/share_actions.dart';
import '../../sharing/widgets/shared_by_chip.dart';
import '../widgets/quiz_format.dart';
import '../widgets/score_trend.dart';

/// Overview of one quiz: info, source, play, attempt history, owner actions.
class QuizDetailScreen extends ConsumerWidget {
  const QuizDetailScreen({super.key, required this.quizId});

  final String quizId;

  Future<void> _delete(BuildContext context, WidgetRef ref, Quiz quiz) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.delete_outline),
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
        title: Text(quiz?.title ?? 'Quiz'),
        actions: [
          if (quiz != null && owner) ...[
            IconButton(
              tooltip: 'Share',
              icon: const Icon(Icons.share_outlined),
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
            PopupMenuButton<String>(
              tooltip: 'More',
              onSelected: (v) {
                if (v == 'delete') _delete(context, ref, quiz);
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    leading: Icon(Icons.delete_outline),
                    title: Text('Delete quiz'),
                  ),
                ),
              ],
            ),
          ] else if (quiz != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: CopyToAccountButton(
                type: ShareResourceType.quiz,
                resourceId: quiz.id,
                compact: true,
              ),
            ),
        ],
      ),
      body: switch (quizAsync) {
        AsyncValue(:final value?) => _DetailBody(quiz: value, owner: owner),
        AsyncValue(hasValue: true) => MessageView(
          icon: Icons.search_off,
          title: 'Quiz not found',
          message: 'It may have been deleted or is no longer shared with you.',
          action: FilledButton.tonal(
            onPressed: () => context.go(AppRoutes.subjects),
            child: const Text('Go to subjects'),
          ),
        ),
        AsyncValue(:final error?) => MessageView(
          icon: Icons.error_outline,
          title: 'Could not load the quiz',
          message: errorText(error),
        ),
        _ => const Center(child: CircularProgressIndicator()),
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
    final info = _InfoCard(quiz: quiz, owner: owner, attempts: attempts);
    final history = _HistoryCard(
      attempts: attempts,
      loading: attemptsAsync.isLoading && !attemptsAsync.hasValue,
    );
    final source = _SourceCard(quiz: quiz);
    final hasSource = _SourceCard.hasContent(quiz);

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= wideBreakpoint) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: MaxWidth(
              maxWidth: 1200,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 5,
                    child: Column(
                      children: [
                        info,
                        if (hasSource) ...[const SizedBox(height: 16), source],
                      ],
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(flex: 4, child: history),
                ],
              ),
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            info,
            const SizedBox(height: 16),
            history,
            if (hasSource) ...[const SizedBox(height: 16), source],
          ],
        );
      },
    );
  }
}

class _InfoCard extends ConsumerWidget {
  const _InfoCard({
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
    final count = quiz.questions.length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (subject != null)
                  ActionChip(
                    avatar: const Icon(Icons.folder_outlined, size: 18),
                    label: Text(subject.title),
                    onPressed: () =>
                        context.push(AppRoutes.subject(subject.id)),
                  ),
                if (note != null)
                  ActionChip(
                    avatar: const Icon(Icons.description_outlined, size: 18),
                    label: Text(note.title),
                    onPressed: () => context.push(AppRoutes.note(note.id)),
                  ),
                if (!owner) SharedByChip(ownerId: quiz.ownerId),
              ],
            ),
            const SizedBox(height: 12),
            Text(quiz.title, style: theme.textTheme.headlineSmall),
            if (quiz.description != null &&
                quiz.description!.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(quiz.description!, style: theme.textTheme.bodyLarge),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 24,
              runSpacing: 12,
              children: [
                _Stat(label: 'Questions', value: '$count'),
                _Stat(label: 'Attempts', value: '${attempts.length}'),
                _Stat(label: 'Best', value: formatPercent(best)),
                _Stat(
                  label: 'Last',
                  value: formatPercent(
                    percents.isEmpty ? null : percents.first,
                  ),
                ),
              ],
            ),
            if (byType.isNotEmpty) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
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
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.icon(
                  key: const Key('play-quiz'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(160, 52),
                    textStyle: theme.textTheme.titleMedium,
                  ),
                  onPressed: count == 0
                      ? null
                      : () => context.push(AppRoutes.quizPlay(quiz.id)),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Play'),
                ),
                if (count == 0)
                  Text(
                    owner
                        ? 'Add questions to play this quiz.'
                        : 'This quiz has no questions yet.',
                    style: theme.textTheme.bodyMedium,
                  ),
                if (count == 0 && owner)
                  OutlinedButton.icon(
                    onPressed: () => context.push(AppRoutes.quizEdit(quiz.id)),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit questions'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: theme.textTheme.titleLarge),
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.attempts, required this.loading});

  final List<QuizAttempt> attempts;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Your attempts',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (delta != null)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    avatar: Icon(
                      delta > 0
                          ? Icons.trending_up
                          : delta < 0
                          ? Icons.trending_down
                          : Icons.trending_flat,
                      size: 18,
                    ),
                    label: Text(
                      delta == 0
                          ? 'Same as before'
                          : '${delta > 0 ? '+' : ''}$delta% vs previous',
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (loading)
              const LinearProgressIndicator()
            else if (attempts.isEmpty)
              Text(
                'No attempts yet. Play the quiz to track your progress.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else ...[
              if (recent.length >= 2) ...[
                SizedBox(height: 72, child: ScoreTrend(percents: recent)),
                const SizedBox(height: 12),
              ],
              for (final a in attempts.take(30)) _AttemptRow(attempt: a),
              if (attempts.length > 30)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Showing the latest 30 of ${attempts.length} attempts.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AttemptRow extends StatelessWidget {
  const _AttemptRow({required this.attempt});

  final QuizAttempt attempt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = attemptPercent(attempt);
    final duration = attempt.completedAt!.difference(attempt.startedAt);
    final color = p == null
        ? theme.colorScheme.outline
        : p >= 80
        ? Colors.green.shade600
        : p >= 50
        ? Colors.orange.shade700
        : theme.colorScheme.error;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: SizedBox.square(
        dimension: 40,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CircularProgressIndicator(
              value: (p ?? 0) / 100,
              strokeWidth: 3,
              color: color,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
            Text('${p ?? 0}', style: theme.textTheme.labelSmall),
          ],
        ),
      ),
      title: Text(formatDateTime(attempt.completedAt!)),
      subtitle: Text(
        '${attempt.score.round()} of ${attempt.total} correct · '
        '${formatDuration(duration)}',
      ),
      trailing: Text(
        formatPercent(p),
        style: theme.textTheme.titleMedium?.copyWith(color: color),
      ),
    );
  }
}

class _SourceCard extends StatefulWidget {
  const _SourceCard({required this.quiz});

  final Quiz quiz;

  static bool hasContent(Quiz quiz) {
    final s = quiz.source;
    return s != null &&
        ((s.contextText?.trim().isNotEmpty ?? false) ||
            (s.youtubeUrl?.trim().isNotEmpty ?? false) ||
            s.provider != null);
  }

  @override
  State<_SourceCard> createState() => _SourceCardState();
}

class _SourceCardState extends State<_SourceCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = widget.quiz.source!;
    final provider = LlmProviderId.fromWireName(s.provider);
    final context_ = s.contextText?.trim() ?? '';
    final youtube = s.youtubeUrl?.trim() ?? '';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Source', style: theme.textTheme.titleMedium),
            if (s.provider != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.auto_awesome, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Generated with ${provider?.displayName ?? s.provider}'
                      '${s.model != null ? ' · ${s.model}' : ''}',
                    ),
                  ),
                ],
              ),
            ],
            if (youtube.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.smart_display_outlined, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: SelectableText(youtube)),
                  IconButton(
                    tooltip: 'Copy link',
                    icon: const Icon(Icons.copy, size: 18),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: youtube));
                      if (context.mounted) showSnack(context, 'Link copied');
                    },
                  ),
                ],
              ),
            ],
            if (context_.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Context', style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  context_,
                  maxLines: _expanded ? null : 6,
                  overflow: _expanded ? null : TextOverflow.fade,
                  style: theme.textTheme.bodySmall,
                ),
              ),
              if (context_.length > 400 || '\n'.allMatches(context_).length > 5)
                TextButton(
                  onPressed: () => setState(() => _expanded = !_expanded),
                  child: Text(_expanded ? 'Show less' : 'Show more'),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
