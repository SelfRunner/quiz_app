import 'package:flutter/material.dart';

import '../../../core/widgets/design_system.dart' hide MaxWidth;
import '../../../data/models/question.dart';

/// Review of one answered (or skipped) question after a run: the user's
/// answer, the correct/model answer and the explanation.
class AnswerReviewCard extends StatelessWidget {
  const AnswerReviewCard({
    super.key,
    required this.index,
    required this.question,
    required this.selected,
    required this.text,
    required this.grade,
    this.answered = true,
    this.flagged = false,
    this.footer,
  });

  /// Zero-based position (shown as `index + 1`).
  final int index;
  final Question question;

  /// Selected original option indices.
  final List<int> selected;
  final String text;

  /// Correct / wrong; null = not graded (unanswered or awaiting self-grade).
  final bool? grade;

  /// False when the question was skipped.
  final bool answered;
  final bool flagged;

  /// Extra content (e.g. self-grade buttons).
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final q = question;
    final ok = grade == true;
    final label = TextStyle(color: colors.mutedText);

    final String yours;
    final String correct;
    if (q.type.hasOptions) {
      final sorted = [...selected]..sort();
      yours = sorted.isEmpty
          ? 'No answer'
          : sorted
                .where((i) => i >= 0 && i < q.options.length)
                .map((i) => q.options[i])
                .join(', ');
      correct = q.correctIndices
          .where((i) => i >= 0 && i < q.options.length)
          .map((i) => q.options[i])
          .join(', ');
    } else {
      final t = text.trim();
      yours = t.isEmpty ? (answered ? '(not written)' : 'No answer') : t;
      correct = q.answerText ?? '—';
    }

    final (IconData icon, Color iconColor, String status) = switch (grade) {
      true => (Icons.check_circle_outline, colors.success, 'Correct'),
      false => (Icons.highlight_off, colors.danger, 'Incorrect'),
      null when !answered => (
        Icons.remove_circle_outline,
        colors.danger,
        'Unanswered',
      ),
      null => (Icons.help_outline, colors.warning, 'Not graded'),
    };

    final explanation = q.explanation?.trim() ?? '';
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              icon,
              size: 20,
              color: iconColor,
              semanticLabel: status,
            ),
          ),
          Gaps.w12,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        '${index + 1}. ${q.prompt}',
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    if (flagged)
                      Padding(
                        padding: const EdgeInsets.only(left: Insets.sm),
                        child: Icon(
                          Icons.flag,
                          size: 16,
                          color: colors.warning,
                          semanticLabel: 'Flagged',
                        ),
                      ),
                  ],
                ),
                Gaps.h8,
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: 'Your answer: ', style: label),
                      TextSpan(
                        text: yours,
                        style: ok || grade == null
                            ? (answered ? null : label)
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
                if (explanation.isNotEmpty) ...[
                  Gaps.h8,
                  Text(
                    explanation,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.mutedText,
                    ),
                  ),
                ],
                if (footer != null) ...[Gaps.h12, footer!],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
