import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ai/ai_providers.dart';
import '../../../ai/ai_tools_service.dart';
import '../../../core/widgets/design_system.dart' hide MaxWidth;
import '../application/ai_grading.dart';

/// Player setting "Grade short answers with AI". Locked (tap opens the
/// "Set up AI" sheet) while AI is not configured.
class AiGradingSwitch extends ConsumerWidget {
  const AiGradingSwitch({super.key, this.contentPadding});

  final EdgeInsetsGeometry? contentPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final readiness = ref.watch(aiReadinessProvider).value;
    final ready = readiness?.isConfigured ?? false;
    final enabled = ref.watch(aiGradeShortAnswersProvider);
    final tile = SwitchListTile(
      key: const Key('ai-grading-switch'),
      contentPadding: contentPadding,
      secondary: const Icon(Icons.auto_awesome_outlined, size: 20),
      title: const Text('Grade short answers with AI'),
      subtitle: ready ? null : const Text('Set up AI in Settings to use this.'),
      value: ready && enabled,
      onChanged: ready
          ? (v) => ref.read(aiGradeShortAnswersProvider.notifier).set(v)
          : null,
    );
    return LockedFeature(
      locked: !ready,
      showBadge: false,
      dimOpacity: 1,
      tooltip: 'Set up AI in Settings to use this',
      onTap: () => showAiSetupSheet(context, reason: readiness?.reason),
      child: tile,
    );
  }
}

/// Label of an AI verdict.
String verdictLabel(GradeVerdict v) => switch (v) {
  GradeVerdict.correct => 'Correct',
  GradeVerdict.partial => 'Partly correct',
  GradeVerdict.incorrect => 'Incorrect',
};

/// The AI's verdict and feedback for a short answer.
class AiVerdictBanner extends StatelessWidget {
  const AiVerdictBanner({super.key, required this.grade, this.note});

  final ShortAnswerGrade grade;

  /// Extra line, e.g. "You marked it right".
  final String? note;

  @override
  Widget build(BuildContext context) {
    final (kind, icon) = switch (grade.verdict) {
      GradeVerdict.correct => (
        InfoBannerKind.success,
        Icons.check_circle_outline,
      ),
      GradeVerdict.partial => (InfoBannerKind.warning, Icons.adjust),
      GradeVerdict.incorrect => (InfoBannerKind.error, Icons.highlight_off),
    };
    final feedback = grade.feedback.trim();
    return InfoBanner(
      key: const Key('ai-verdict'),
      kind: kind,
      icon: icon,
      title: 'AI grade: ${verdictLabel(grade.verdict)}',
      message: [if (feedback.isNotEmpty) feedback, ?note].join('\n'),
    );
  }
}

/// "Grading with AI…" line with a small spinner.
class AiGradingIndicator extends StatelessWidget {
  const AiGradingIndicator({super.key, this.label = 'Grading with AI…'});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return Row(
      key: const Key('ai-grading'),
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox.square(
          dimension: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        Gaps.w8,
        Flexible(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.mutedText,
            ),
          ),
        ),
      ],
    );
  }
}

/// Note shown under an AI verdict once the user decided.
String? decisionNote(AiGradeDecision d) => switch (d) {
  AiGradeDecision.markedRight => 'You marked it right.',
  AiGradeDecision.markedWrong => 'You marked it wrong.',
  _ => null,
};
