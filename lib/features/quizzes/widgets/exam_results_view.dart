import 'package:flutter/material.dart';

import '../../../core/widgets/design_system.dart' hide MaxWidth;
import '../../../data/models/question.dart';
import '../../../data/models/quiz.dart';
import '../../../data/models/quiz_attempt.dart';
import '../../../study/exam.dart';
import '../application/ai_grading.dart';
import 'ai_grading_widgets.dart';
import 'answer_review_card.dart';
import 'explain_answer.dart';
import 'quiz_format.dart';
import 'quiz_results_view.dart';

/// Results of a submitted exam: score, time used and a per-question review
/// with explanations. Written short answers can be self-graded here.
class ExamResultsView extends StatelessWidget {
  const ExamResultsView({
    super.key,
    required this.attempt,
    required this.questions,
    required this.flagged,
    required this.autoSubmitted,
    required this.saveStatus,
    required this.onRetrySave,
    required this.onSelfGrade,
    required this.onNewExam,
    required this.onDone,
    this.saveError,
    this.quiz,
    this.aiGrades = const {},
    this.partialIds = const {},
    this.gradingProgress,
  });

  /// The completed attempt (graded answers, duration).
  final QuizAttempt attempt;

  /// Questions served, in exam order.
  final List<Question> questions;
  final Set<String> flagged;
  final bool autoSubmitted;
  final SaveStatus saveStatus;
  final String? saveError;
  final VoidCallback onRetrySave;
  final void Function(String questionId, bool correct) onSelfGrade;
  final VoidCallback onNewExam;
  final VoidCallback onDone;

  /// The quiz (its notes ground "Explain").
  final Quiz? quiz;

  /// AI grades of written answers, by question id.
  final Map<String, AiGradeState> aiGrades;

  /// Answers graded partly correct (half a point when still wrong).
  final Set<String> partialIds;

  /// Batch AI grading progress (null when not grading).
  final ({int done, int total})? gradingProgress;

  bool _isPartial(QuestionAnswer? a) =>
      a != null && a.isCorrect == false && partialIds.contains(a.questionId);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final wide = Breakpoints.isMedium(context);
    final score = scoreExam(questions, attempt.answers).score;
    final byId = {for (final a in attempt.answers) a.questionId: a};
    final partial = attempt.answers.where(_isPartial).length;
    final credit = score.correct + partial * 0.5;
    final fraction = score.total == 0 ? 0.0 : credit / score.total;
    final percent = (fraction * 100).round();
    final color = scoreColor(context, percent);
    final duration = Duration(seconds: attempt.durationSeconds ?? 0);
    final limit = attempt.timeLimitSeconds;
    final muted = theme.textTheme.bodyMedium?.copyWith(color: colors.mutedText);

    final facts = <String>[
      '${formatPoints(credit)} of ${score.total} correct',
      limit == null
          ? 'Time ${formatDuration(duration)}'
          : 'Time ${formatDuration(duration)} of ${formatTimeLimit(limit)}',
    ];

    final summary = AppCard(
      padding: EdgeInsets.all(wide ? Insets.xxl : Insets.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Exam score',
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
          Gaps.h16,
          ClipRRect(
            borderRadius: Radii.xsAll,
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 4,
              color: color,
              backgroundColor: colors.hairline,
            ),
          ),
          Gaps.h12,
          Text(
            facts.join(' · '),
            key: const Key('result-summary'),
            style: muted,
          ),
          if (score.unanswered > 0 || score.ungraded > 0) ...[
            Gaps.h4,
            Text(
              [
                if (score.unanswered > 0) '${score.unanswered} unanswered',
                if (score.ungraded > 0)
                  '${plural(score.ungraded, 'answer')} to self-grade below',
              ].join(' · '),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.faintText,
              ),
            ),
          ],
          if (gradingProgress case final p?) ...[
            Gaps.h12,
            Column(
              key: const Key('ai-grading-progress'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AiGradingIndicator(
                  label:
                      'Grading written answers with AI… '
                      '${p.done} of ${p.total}',
                ),
                Gaps.h8,
                LinearProgressIndicator(
                  value: p.total == 0 ? null : p.done / p.total,
                  minHeight: 3,
                  backgroundColor: colors.hairline,
                ),
              ],
            ),
          ],
          if (autoSubmitted) ...[
            Gaps.h12,
            const InfoBanner(
              kind: InfoBannerKind.warning,
              icon: Icons.timer_off_outlined,
              message: 'Time is up. Your exam was submitted automatically.',
            ),
          ],
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
                onPressed: onNewExam,
                icon: const Icon(Icons.replay, size: 18),
                label: const Text('New exam'),
              ),
              OutlinedButton(onPressed: onDone, child: const Text('Done')),
            ],
          ),
        ],
      ),
    );

    final wrong = score.total - score.correct;

    return ListView(
      key: const Key('exam-results'),
      padding: EdgeInsets.symmetric(vertical: wide ? Insets.xl : Insets.lg),
      children: [
        ContentContainer(child: summary),
        ContentContainer(
          child: SectionHeader(
            title: 'Review',
            count: questions.length,
            subtitle: wrong == 0
                ? 'Every answer was right.'
                : '${plural(wrong, 'question')} to look at again.',
            padding: const EdgeInsets.only(top: Insets.xl, bottom: Insets.sm),
          ),
        ),
        for (var i = 0; i < questions.length; i++)
          ContentContainer(
            child: Padding(
              padding: const EdgeInsets.only(bottom: Insets.sm),
              child: _review(context, i, questions[i], byId[questions[i].id]),
            ),
          ),
      ],
    );
  }

  Widget _review(
    BuildContext context,
    int index,
    Question q,
    QuestionAnswer? answer,
  ) {
    final colors = AppColors.of(context);
    final ai = aiGrades[q.id];
    final needsGrade =
        answer != null &&
        answer.isCorrect == null &&
        q.type == QuestionType.shortAnswer &&
        (answer.textAnswer?.trim().isNotEmpty ?? false) &&
        !(ai?.loading ?? false);
    final Widget? aiPart = switch (ai) {
      null => null,
      AiGradeState(loading: true) => const AiGradingIndicator(),
      AiGradeState(grade: final grade?) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AiVerdictBanner(grade: grade, note: decisionNote(ai.decision)),
          Gaps.h8,
          Wrap(
            spacing: Insets.sm,
            runSpacing: Insets.sm,
            children: [
              OutlinedButton.icon(
                key: Key('ai-grade-wrong-${q.id}'),
                style: OutlinedButton.styleFrom(foregroundColor: colors.danger),
                onPressed: answer?.isCorrect == false && !_isPartial(answer)
                    ? null
                    : () => onSelfGrade(q.id, false),
                icon: const Icon(Icons.close, size: 16),
                label: const Text('Mark wrong'),
              ),
              OutlinedButton.icon(
                key: Key('ai-grade-right-${q.id}'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.success,
                ),
                onPressed: answer?.isCorrect == true
                    ? null
                    : () => onSelfGrade(q.id, true),
                icon: const Icon(Icons.check, size: 16),
                label: const Text('Mark right'),
              ),
            ],
          ),
        ],
      ),
      AiGradeState(error: final error?) when answer?.isCorrect == null =>
        InfoBanner(
          key: Key('ai-grade-error-${q.id}'),
          kind: InfoBannerKind.warning,
          message: 'AI grading failed: $error Grade it yourself.',
        ),
      _ => null,
    };
    final selfGrade = needsGrade
        ? Wrap(
            spacing: Insets.sm,
            runSpacing: Insets.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Did you get it?',
                style: Theme.of(context).textTheme.labelMedium
                    ?.copyWith(color: colors.mutedText),
              ),
              OutlinedButton.icon(
                key: Key('grade-wrong-${q.id}'),
                style: OutlinedButton.styleFrom(foregroundColor: colors.danger),
                onPressed: () => onSelfGrade(q.id, false),
                icon: const Icon(Icons.close, size: 16),
                label: const Text('I missed it'),
              ),
              FilledButton.tonalIcon(
                key: Key('grade-right-${q.id}'),
                onPressed: () => onSelfGrade(q.id, true),
                icon: const Icon(Icons.check, size: 16),
                label: const Text('I got it'),
              ),
            ],
          )
        : null;
    final footer = aiPart != null && selfGrade != null
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [aiPart, Gaps.h8, selfGrade],
          )
        : aiPart ?? selfGrade;
    return AnswerReviewCard(
      key: Key('review-${q.id}'),
      index: index,
      question: q,
      selected: answer?.selectedIndices ?? const [],
      text: answer?.textAnswer ?? '',
      grade: answer?.isCorrect,
      answered: answer != null,
      flagged: flagged.contains(q.id),
      partial: _isPartial(answer),
      footer: footer,
      explain: ExplainButton(question: q, answer: answer, quiz: quiz),
    );
  }
}
