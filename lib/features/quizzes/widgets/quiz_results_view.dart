import 'package:flutter/material.dart';

import '../../../core/widgets/design_system.dart' hide MaxWidth;
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
    final colors = AppColors.of(context);
    final wide = Breakpoints.isMedium(context);
    final s = session;
    final percent = (s.fraction * 100).round();
    final missed = s.missedQuestions.length;
    final message = switch (percent) {
      100 => 'Perfect score!',
      >= 80 => 'Great job!',
      >= 50 => 'Good effort. Keep practising!',
      _ => 'Keep going, review the answers below.',
    };
    final color = scoreColor(context, percent);

    final summary = AppCard(
      padding: EdgeInsets.all(wide ? Insets.xxl : Insets.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your score',
            style: theme.textTheme.labelMedium?.copyWith(
              color: colors.mutedText,
            ),
          ),
          Gaps.h4,
          Text(
            '$percent%',
            key: const Key('result-percent'),
            style: theme.textTheme.displayMedium?.copyWith(
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Gaps.h4,
          Text(message, style: theme.textTheme.titleLarge),
          Gaps.h16,
          ClipRRect(
            borderRadius: Radii.xsAll,
            child: LinearProgressIndicator(
              value: s.fraction,
              minHeight: 4,
              color: color,
              backgroundColor: colors.hairline,
            ),
          ),
          Gaps.h12,
          Text(
            '${s.correctCount} of ${s.length} correct · '
            '${formatDuration(duration)}',
            key: const Key('result-summary'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.mutedText,
            ),
          ),
          _SaveLine(status: saveStatus, error: saveError, onRetry: onRetrySave),
          Gaps.h24,
          Wrap(
            spacing: Insets.sm,
            runSpacing: Insets.sm,
            children: [
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.replay, size: 18),
                label: const Text('Retry'),
              ),
              if (onRetryMissed != null)
                FilledButton.tonalIcon(
                  onPressed: onRetryMissed,
                  icon: const Icon(Icons.flag_outlined, size: 18),
                  label: Text('Retry missed ($missed)'),
                ),
              OutlinedButton(onPressed: onDone, child: const Text('Done')),
            ],
          ),
        ],
      ),
    );

    return ListView(
      padding: EdgeInsets.symmetric(vertical: wide ? Insets.xl : Insets.lg),
      children: [
        ContentContainer(child: summary),
        ContentContainer(
          child: SectionHeader(
            title: 'Review',
            count: s.items.length,
            subtitle: missed == 0
                ? 'Every answer was right.'
                : '${plural(missed, 'question')} to look at again.',
            padding: const EdgeInsets.only(top: Insets.xl, bottom: Insets.sm),
          ),
        ),
        for (var i = 0; i < s.items.length; i++)
          ContentContainer(
            child: Padding(
              padding: const EdgeInsets.only(bottom: Insets.sm),
              child: _ReviewCard(index: i, item: s.items[i], session: s),
            ),
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
    final colors = AppColors.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(color: colors.faintText);
    Widget line(IconData icon, String text) => Padding(
      padding: const EdgeInsets.only(top: Insets.xs),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colors.faintText),
          Gaps.w4,
          Flexible(child: Text(text, style: style)),
        ],
      ),
    );
    return switch (status) {
      SaveStatus.idle => const SizedBox.shrink(),
      SaveStatus.saving => line(
        Icons.cloud_upload_outlined,
        'Saving your attempt…',
      ),
      SaveStatus.saved => line(
        Icons.cloud_done_outlined,
        'Saved to your history',
      ),
      SaveStatus.practice => line(
        Icons.school_outlined,
        'Practice round: not added to your history.',
      ),
      SaveStatus.failed => Padding(
        padding: const EdgeInsets.only(top: Insets.md),
        child: InfoBanner(
          kind: InfoBannerKind.error,
          message: 'Could not save this attempt: ${error ?? 'unknown error'}',
          action: TextButton(
            onPressed: onRetry,
            child: const Text('Try again'),
          ),
        ),
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
    final colors = AppColors.of(context);
    final q = item.question;
    final grade = session.gradeFor(item.id);
    final ok = grade == true;
    final label = TextStyle(color: colors.mutedText);

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

    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              ok ? Icons.check_circle_outline : Icons.highlight_off,
              size: 20,
              color: ok ? colors.success : colors.danger,
              semanticLabel: ok ? 'Correct' : 'Incorrect',
            ),
          ),
          Gaps.w12,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${index + 1}. ${q.prompt}',
                  style: theme.textTheme.titleSmall,
                ),
                Gaps.h8,
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: 'Your answer: ', style: label),
                      TextSpan(
                        text: yours,
                        style: ok
                            ? null
                            : TextStyle(
                                color: colors.danger,
                                decoration: q.type.hasOptions
                                    ? TextDecoration.lineThrough
                                    : null,
                                decorationColor: colors.danger,
                              ),
                      ),
                    ],
                  ),
                  style: theme.textTheme.bodyMedium,
                ),
                if (!ok || q.type == QuestionType.shortAnswer)
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
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: colors.success,
                          ),
                        ),
                      ],
                    ),
                    style: theme.textTheme.bodyMedium,
                  ),
                if (q.explanation != null &&
                    q.explanation!.trim().isNotEmpty) ...[
                  Gaps.h8,
                  Text(
                    q.explanation!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.mutedText,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
