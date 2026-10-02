import 'package:flutter/material.dart';

import '../../../core/widgets/design_system.dart' hide MaxWidth;
import '../../../data/models/question.dart';
import '../../../data/models/quiz.dart';
import '../application/ai_grading.dart';
import '../domain/quiz_session.dart';
import 'ai_grading_widgets.dart';
import 'explain_answer.dart';
import 'quiz_format.dart';

/// Hint above a question prompt.
String questionHint(QuestionType t, {bool exam = false}) => switch (t) {
  QuestionType.mcqSingle => 'Choose one answer',
  QuestionType.mcqMulti => 'Select all that apply',
  QuestionType.trueFalse => 'True or false?',
  QuestionType.shortAnswer =>
    exam
        ? 'Write your answer; compare it with the model answer after submitting'
        : 'Answer, then compare with the model answer',
};

// ---------------------------------------------------------------------------
// Question page
// ---------------------------------------------------------------------------

/// One question page of a practice run (feedback after each answer).
class PracticeQuestionView extends StatelessWidget {
  const PracticeQuestionView({
    super.key,
    required this.session,
    required this.answer,
    required this.onToggle,
    required this.onTextChanged,
    required this.onPrimary,
    required this.onSelfGrade,
    this.aiGrade,
    this.onAcceptAiGrade,
    this.onSkipAiGrade,
    this.quiz,
  });

  final QuizSession session;
  final TextEditingController answer;
  final ValueChanged<int> onToggle;
  final ValueChanged<String> onTextChanged;
  final VoidCallback onPrimary;

  /// Self-grade, or an override of the AI grade ("Mark right/wrong").
  final ValueChanged<bool> onSelfGrade;

  /// AI grading of the current short answer (null = self-graded).
  final AiGradeState? aiGrade;
  final VoidCallback? onAcceptAiGrade;

  /// "Grade myself" while the AI is still grading.
  final VoidCallback? onSkipAiGrade;

  /// Quiz of the current question (its notes ground "Explain").
  final Quiz? quiz;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final wide = Breakpoints.isMedium(context);
    final s = session;
    final item = s.current;
    final q = item.question;
    final checked = s.isChecked(item.id);
    final revealed = s.isRevealed(item.id);
    final grade = s.gradeFor(item.id);
    final mono = theme.textTheme.labelMedium?.copyWith(
      color: colors.mutedText,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    final content = <Widget>[
      Row(
        children: [
          Text('Question ${s.index + 1} of ${s.length}', style: mono),
          const Spacer(),
          Tooltip(
            message: 'Correct so far',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check, size: 14, color: colors.success),
                Gaps.w4,
                Text(
                  '${formatPoints(s.credit)} / ${s.answeredCount}',
                  style: mono,
                ),
              ],
            ),
          ),
        ],
      ),
      SizedBox(height: wide ? Insets.xxl : Insets.xl),
      Text(
        questionHint(q.type),
        style: theme.textTheme.labelMedium?.copyWith(color: colors.faintText),
      ),
      Gaps.h8,
      Text(
        q.prompt,
        style:
            (wide
                    ? theme.textTheme.headlineMedium
                    : theme.textTheme.headlineSmall)
                ?.copyWith(height: 1.4),
      ),
      Gaps.h24,
    ];

    if (q.type.hasOptions) {
      final selected = s.selectedFor(item.id);
      for (var d = 0; d < item.optionOrder.length; d++) {
        final original = item.optionOrder[d];
        content.add(
          Padding(
            padding: const EdgeInsets.only(bottom: Insets.sm),
            child: AnswerOptionTile(
              key: Key('option-$d'),
              number: d + 1,
              text: q.options[original],
              multi: q.type == QuestionType.mcqMulti,
              selected: selected.contains(original),
              checked: checked,
              correct: q.correctIndices.contains(original),
              showKey: wide,
              onTap: checked ? null : () => onToggle(d),
            ),
          ),
        );
      }
    } else {
      content.add(
        TextField(
          key: const Key('short-answer-input'),
          controller: answer,
          enabled: !revealed,
          minLines: 2,
          maxLines: 6,
          style: theme.textTheme.bodyLarge,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: 'Your answer (optional)',
          ),
          onChanged: onTextChanged,
          onSubmitted: (_) => onPrimary(),
        ),
      );
      if (revealed) {
        content.addAll([
          Gaps.h16,
          InfoBanner(
            icon: Icons.lightbulb_outline,
            title: 'Model answer',
            message: q.answerText ?? '—',
          ),
        ]);
      }
      final ai = aiGrade;
      if (revealed && ai != null) {
        content.add(Gaps.h12);
        if (ai.loading) {
          content.add(const AiGradingIndicator());
        } else if (ai.grade case final grade?) {
          content.add(
            AiVerdictBanner(grade: grade, note: decisionNote(ai.decision)),
          );
        } else if (ai.error != null) {
          content.add(
            InfoBanner(
              key: const Key('ai-grade-error'),
              kind: InfoBannerKind.warning,
              message:
                  'AI grading failed: ${ai.error} Grade your answer yourself.',
            ),
          );
        }
      }
    }

    final explanation = q.explanation?.trim();
    if (checked) {
      final ok = grade ?? false;
      final partial = s.isPartial(item.id);
      final hasExplanation = explanation != null && explanation.isNotEmpty;
      final status = ok
          ? 'Correct!'
          : (partial ? 'Partly correct' : 'Not quite');
      content.addAll([
        Gaps.h16,
        InfoBanner(
          key: const Key('answer-feedback'),
          kind: ok
              ? InfoBannerKind.success
              : (partial ? InfoBannerKind.warning : InfoBannerKind.error),
          icon: ok
              ? Icons.check_circle_outline
              : (partial ? Icons.adjust : Icons.highlight_off),
          title: hasExplanation ? status : null,
          message: hasExplanation ? explanation : status,
        ),
        Gaps.h8,
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: ExplainButton(
            question: q,
            answer: s.answerFor(item.id),
            quiz: quiz,
          ),
        ),
      ]);
    } else if (revealed && explanation != null && explanation.isNotEmpty) {
      content.addAll([
        Gaps.h12,
        Text(
          explanation,
          style: theme.textTheme.bodyMedium?.copyWith(color: colors.mutedText),
        ),
      ]);
    }

    final selfGrading = !q.type.hasOptions && revealed && !checked;
    final buttonSize = wide ? const Size(160, 44) : const Size.fromHeight(48);
    final ai = selfGrading ? aiGrade : null;
    final aiLoading = ai != null && ai.loading;
    final aiVerdict = ai != null && ai.hasVerdict;
    final Widget actions;
    if (aiLoading) {
      final skip = TextButton(
        key: const Key('ai-grade-skip'),
        onPressed: onSkipAiGrade,
        child: const Text('Grade myself'),
      );
      final busy = FilledButton(
        style: FilledButton.styleFrom(minimumSize: buttonSize),
        onPressed: null,
        child: const Text('Grading…'),
      );
      actions = wide
          ? Row(mainAxisSize: MainAxisSize.min, children: [skip, Gaps.w8, busy])
          : Row(
              children: [
                Expanded(child: skip),
                Gaps.w12,
                Expanded(child: busy),
              ],
            );
    } else if (aiVerdict) {
      final small = wide ? const Size(0, 44) : const Size.fromHeight(48);
      final wrong = OutlinedButton(
        key: const Key('ai-grade-wrong'),
        style: OutlinedButton.styleFrom(
          minimumSize: small,
          foregroundColor: colors.danger,
        ),
        onPressed: () => onSelfGrade(false),
        child: const Text('Mark wrong'),
      );
      final right = OutlinedButton(
        key: const Key('ai-grade-right'),
        style: OutlinedButton.styleFrom(
          minimumSize: small,
          foregroundColor: colors.success,
        ),
        onPressed: () => onSelfGrade(true),
        child: const Text('Mark right'),
      );
      final accept = FilledButton(
        key: const Key('ai-grade-accept'),
        style: FilledButton.styleFrom(minimumSize: small),
        onPressed: onAcceptAiGrade,
        child: const Text('Accept'),
      );
      actions = wide
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [wrong, Gaps.w8, right, Gaps.w8, accept],
            )
          : Row(
              children: [
                Expanded(child: wrong),
                Gaps.w8,
                Expanded(child: right),
                Gaps.w8,
                Expanded(child: accept),
              ],
            );
    } else if (selfGrading) {
      final missed = OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          minimumSize: buttonSize,
          foregroundColor: colors.danger,
        ),
        onPressed: () => onSelfGrade(false),
        icon: const Icon(Icons.close, size: 18),
        label: const Text('I missed it'),
      );
      final got = FilledButton.icon(
        style: FilledButton.styleFrom(
          minimumSize: buttonSize,
          backgroundColor: colors.success,
          foregroundColor: theme.colorScheme.surface,
        ),
        onPressed: () => onSelfGrade(true),
        icon: const Icon(Icons.check, size: 18),
        label: const Text('I got it'),
      );
      actions = wide
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [missed, Gaps.w8, got],
            )
          : Row(
              children: [
                Expanded(child: missed),
                Gaps.w12,
                Expanded(child: got),
              ],
            );
    } else {
      final label = checked
          ? (s.isLast ? 'See results' : 'Next')
          : (q.type.hasOptions ? 'Check' : 'Show answer');
      actions = FilledButton(
        key: const Key('primary-action'),
        style: FilledButton.styleFrom(minimumSize: buttonSize),
        onPressed: checked || s.canCheck ? onPrimary : null,
        child: Text(label),
      );
    }

    final Widget bar;
    if (wide) {
      final hints = <Widget>[
        if (q.type.hasOptions && !checked)
          KeyboardShortcutHint(
            keys: [
              item.optionOrder.length > 1
                  ? '1–${item.optionOrder.length.clamp(1, 9)}'
                  : '1',
            ],
            label: 'Pick',
          ),
        if (aiVerdict)
          const KeyboardShortcutHint(keys: ['Enter'], label: 'Accept')
        else if (aiLoading)
          const SizedBox.shrink()
        else if (selfGrading)
          const KeyboardShortcutHint(keys: ['Y', 'N'], label: 'Got it / missed')
        else
          KeyboardShortcutHint(
            keys: const ['Enter'],
            label: checked
                ? (s.isLast ? 'Results' : 'Next')
                : (q.type.hasOptions ? 'Check' : 'Show answer'),
          ),
      ];
      bar = Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: Insets.lg,
              runSpacing: Insets.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: hints,
            ),
          ),
          Gaps.w16,
          actions,
        ],
      );
    } else {
      bar = SizedBox(width: double.infinity, child: actions);
    }

    return Column(
      children: [
        LinearProgressIndicator(
          key: const Key('quiz-progress'),
          value: s.length == 0 ? 0 : s.answeredCount / s.length,
          minHeight: 2,
          color: theme.colorScheme.primary,
          backgroundColor: colors.hairline,
        ),
        Expanded(
          child: SingleChildScrollView(
            child: ContentContainer(
              padding: EdgeInsets.fromLTRB(
                Breakpoints.gutter(context),
                wide ? Insets.xl : Insets.lg,
                Breakpoints.gutter(context),
                Insets.xl,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: content,
              ),
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(top: BorderSide(color: colors.hairline)),
          ),
          child: ContentContainer(
            padding: EdgeInsets.symmetric(
              horizontal: Breakpoints.gutter(context),
              vertical: Insets.md,
            ),
            child: bar,
          ),
        ),
      ],
    );
  }
}

/// One answer option. Idle rows are hairline-bordered; hover darkens the
/// border, selection uses the text color, and after checking the correct
/// option turns success-green and a wrong pick danger-red.
class AnswerOptionTile extends StatefulWidget {
  const AnswerOptionTile({
    super.key,
    required this.number,
    required this.text,
    required this.multi,
    required this.selected,
    required this.checked,
    required this.correct,
    required this.showKey,
    required this.onTap,
  });

  final int number;
  final String text;
  final bool multi;
  final bool selected;
  final bool checked;
  final bool correct;
  final bool showKey;
  final VoidCallback? onTap;

  @override
  State<AnswerOptionTile> createState() => _AnswerOptionTileState();
}

class _AnswerOptionTileState extends State<AnswerOptionTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final w = widget;
    var border = colors.hairline;
    var borderWidth = 1.0;
    var fill = colors.card;
    var textColor = theme.colorScheme.onSurface;
    var icon = w.multi
        ? (w.selected ? Icons.check_box : Icons.check_box_outline_blank)
        : (w.selected ? Icons.radio_button_checked : Icons.radio_button_off);
    var iconColor = w.selected ? theme.colorScheme.onSurface : colors.faintText;
    String? status;

    if (!w.checked) {
      if (w.selected) {
        border = theme.colorScheme.onSurface;
        borderWidth = 1.5;
        fill = Color.alphaBlend(colors.hover, colors.card);
      } else if (_hovered) {
        border = colors.border;
        fill = Color.alphaBlend(colors.hover, colors.card);
      }
    } else if (w.correct) {
      border = colors.success;
      borderWidth = 1.5;
      fill = colors.successContainer;
      textColor = colors.onSuccessContainer;
      icon = Icons.check_circle;
      iconColor = colors.success;
      status = 'correct answer';
    } else if (w.selected) {
      border = colors.danger;
      borderWidth = 1.5;
      fill = colors.dangerContainer;
      textColor = colors.onDangerContainer;
      icon = Icons.cancel;
      iconColor = colors.danger;
      status = 'incorrect';
    } else {
      textColor = colors.mutedText;
    }

    return Semantics(
      selected: w.selected,
      button: true,
      value: status,
      child: AnimatedContainer(
        duration: Motion.fast,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: Radii.lgAll,
          border: Border.all(color: border, width: borderWidth),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: w.onTap,
            onHover: (v) => setState(() => _hovered = v),
            borderRadius: Radii.lgAll,
            hoverColor: Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Insets.lg,
                vertical: Insets.md + 2,
              ),
              child: Row(
                children: [
                  Icon(icon, size: 20, color: iconColor),
                  Gaps.w12,
                  Expanded(
                    child: Text(
                      w.text,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: textColor,
                      ),
                    ),
                  ),
                  if (w.showKey) ...[
                    Gaps.w8,
                    KeyboardShortcutHint(keys: ['${w.number}']),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
