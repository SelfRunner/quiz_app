import 'package:flutter/material.dart';

import '../../../data/models/question.dart';
import '../domain/quiz_session.dart';
import 'quiz_format.dart';

enum SaveStatus { idle, saving, saved, failed, practice }

/// Score summary, save state, retry actions and per-question review.
class QuizResultsView extends StatelessWidget {
  const QuizResultsView({
    super.key,
    required this.session,
    required this.duration,
    required this.saveStatus,
    required this.onRetry,
    required this.onDone,
    required this.onRetrySave,
    this.onRetryMissed,
    this.saveError,
  });

  final QuizSession session;
  final Duration duration;
  final SaveStatus saveStatus;
  final String? saveError;
  final VoidCallback onRetry;
  final VoidCallback? onRetryMissed;
  final VoidCallback onDone;
  final VoidCallback onRetrySave;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = session;
    final percent = (s.fraction * 100).round();
    final missed = s.missedQuestions.length;
    final message = switch (percent) {
      100 => 'Perfect score!',
      >= 80 => 'Great job!',
      >= 50 => 'Good effort. Keep practising!',
      _ => 'Keep going, review the answers below.',
    };
    final color = percent >= 80
        ? Colors.green.shade600
        : percent >= 50
        ? Colors.orange.shade700
        : theme.colorScheme.error;

    final summary = Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            SizedBox.square(
              dimension: 132,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CircularProgressIndicator(
                    value: s.fraction,
                    strokeWidth: 10,
                    color: color,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  ),
                  Center(
                    child: Text(
                      '$percent%',
                      key: const Key('result-percent'),
                      style: theme.textTheme.headlineMedium,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(message, style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              '${s.correctCount} of ${s.length} correct · '
              '${formatDuration(duration)}',
              key: const Key('result-summary'),
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 12),
            _SaveLine(
              status: saveStatus,
              error: saveError,
              onRetry: onRetrySave,
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.replay),
                  label: const Text('Retry'),
                ),
                if (onRetryMissed != null)
                  FilledButton.tonalIcon(
                    onPressed: onRetryMissed,
                    icon: const Icon(Icons.flag_outlined),
                    label: Text('Retry missed ($missed)'),
                  ),
                OutlinedButton(onPressed: onDone, child: const Text('Done')),
              ],
            ),
          ],
        ),
      ),
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        MaxWidth(maxWidth: 720, child: summary),
        const SizedBox(height: 16),
        MaxWidth(
          maxWidth: 720,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text('Review', style: theme.textTheme.titleMedium),
          ),
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < s.items.length; i++)
          MaxWidth(
            maxWidth: 720,
            child: _ReviewCard(index: i, item: s.items[i], session: s),
          ),
      ],
    );
  }
}

class _SaveLine extends StatelessWidget {
  const _SaveLine({required this.status, required this.onRetry, this.error});

  final SaveStatus status;
  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return switch (status) {
      SaveStatus.idle => const SizedBox.shrink(),
      SaveStatus.saving => Text('Saving your attempt…', style: style),
      SaveStatus.saved => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_done_outlined, size: 16, color: style?.color),
          const SizedBox(width: 6),
          Flexible(child: Text('Saved to your history', style: style)),
        ],
      ),
      SaveStatus.practice => Text(
        'Practice round: not added to your history.',
        style: style,
      ),
      SaveStatus.failed => Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.center,
        children: [
          Text(
            'Could not save this attempt: ${error ?? 'unknown error'}',
            style: style?.copyWith(color: theme.colorScheme.error),
          ),
          TextButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    };
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({
    required this.index,
    required this.item,
    required this.session,
  });

  final int index;
  final PlayItem item;
  final QuizSession session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = item.question;
    final grade = session.gradeFor(item.id);
    final green = Colors.green.shade600;
    final label = TextStyle(color: theme.colorScheme.onSurfaceVariant);

    String yours;
    String correct;
    if (q.type.hasOptions) {
      final selected = session.selectedFor(item.id).toList()..sort();
      yours = selected.isEmpty
          ? 'No answer'
          : selected.map((i) => q.options[i]).join(', ');
      correct = q.correctIndices.map((i) => q.options[i]).join(', ');
    } else {
      final text = session.textFor(item.id).trim();
      yours = text.isEmpty ? '(not written)' : text;
      correct = q.answerText ?? '—';
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              grade == true ? Icons.check_circle : Icons.cancel,
              color: grade == true ? green : theme.colorScheme.error,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${index + 1}. ${q.prompt}',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: 'Your answer: ', style: label),
                        TextSpan(text: yours),
                      ],
                    ),
                  ),
                  if (grade != true || q.type == QuestionType.shortAnswer)
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: q.type == QuestionType.shortAnswer
                                ? 'Model answer: '
                                : 'Correct answer: ',
                            style: label,
                          ),
                          TextSpan(
                            text: correct,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  if (q.explanation != null &&
                      q.explanation!.trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      q.explanation!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
