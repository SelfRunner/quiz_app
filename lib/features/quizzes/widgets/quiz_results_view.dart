import 'package:flutter/material.dart';

import '../../../core/widgets/design_system.dart' hide MaxWidth;
import '../../../data/models/question.dart';
import '../../../data/models/quiz.dart';
import '../domain/quiz_session.dart';
import 'answer_review_card.dart';
import 'explain_answer.dart';
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
    this.quizFor,
    this.onEditQuestions,
  });

  final QuizSession session;
  final Duration duration;
  final SaveStatus saveStatus;
  final String? saveError;
  final VoidCallback onRetry;
  final VoidCallback? onRetryMissed;
  final VoidCallback onDone;
  final VoidCallback onRetrySave;

  /// The quiz a question belongs to (context for "Explain").
  final Quiz? Function(Question question)? quizFor;

  /// Opens the quiz editor (owners only; null hides the link).
  final VoidCallback? onEditQuestions;

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
            '${formatPoints(s.credit)} of ${s.length} correct · '
            '${formatDuration(duration)}',
            key: const Key('result-summary'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.mutedText,
            ),
          ),
          SaveStatusLine(
            status: saveStatus,
            error: saveError,
            onRetry: onRetrySave,
          ),
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
              if (onEditQuestions != null)
                TextButton.icon(
                  key: const Key('results-edit-questions'),
                  onPressed: onEditQuestions,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Edit questions'),
                ),
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
              child: AnswerReviewCard(
                index: i,
                question: s.items[i].question,
                selected: s.selectedFor(s.items[i].id).toList(),
                text: s.textFor(s.items[i].id),
                grade: s.gradeFor(s.items[i].id),
                partial: s.isPartial(s.items[i].id),
                explain: ExplainButton(
                  question: s.items[i].question,
                  answer: s.answerFor(s.items[i].id),
                  quiz: quizFor?.call(s.items[i].question),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// "Saved to your history" / saving / failed (with retry) line.
class SaveStatusLine extends StatelessWidget {
  const SaveStatusLine({
    super.key,
    required this.status,
    required this.onRetry,
    this.error,
  });

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
