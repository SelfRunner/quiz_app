import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/design_system.dart';
import '../../../data/data_providers.dart';
import '../../../data/models/mistake.dart';
import '../../../data/models/question.dart';
import '../../../data/models/quiz.dart';
import '../../quizzes/widgets/quiz_format.dart' show formatDate;

/// A mastered mistake with its quiz and question.
@immutable
class ResolvedMistake {
  const ResolvedMistake({
    required this.mistake,
    required this.quiz,
    required this.question,
  });

  final Mistake mistake;
  final Quiz quiz;
  final Question question;
}

/// Most recently resolved mistakes (max 50) of quizzes still cached; built
/// from the study snapshot (which holds every own mistake row).
final resolvedMistakesProvider =
    StreamProvider.autoDispose<List<ResolvedMistake>>(
      (ref) => ref.watch(studyActivityRepositoryProvider).watchSnapshot().map((
        snapshot,
      ) {
        final quizzes = {for (final q in snapshot.quizzes) q.id: q};
        final out = <ResolvedMistake>[];
        for (final m in snapshot.mistakes) {
          if (m.resolvedAt == null || m.deletedAt != null) continue;
          final quiz = quizzes[m.quizId];
          if (quiz == null || quiz.deletedAt != null) continue;
          final question = quiz.questions
              .where((q) => q.id == m.questionId)
              .firstOrNull;
          if (question == null) continue;
          out.add(ResolvedMistake(mistake: m, quiz: quiz, question: question));
        }
        out.sort(
          (a, b) => b.mistake.resolvedAt!.compareTo(a.mistake.resolvedAt!),
        );
        return out.length > 50 ? out.sublist(0, 50) : out;
      }),
    );

/// Collapsed "Resolved" history under the open mistakes.
class ResolvedMistakesSection extends ConsumerWidget {
  const ResolvedMistakesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resolved = ref.watch(resolvedMistakesProvider).value ?? const [];
    if (resolved.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: Insets.xl),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: const Key('resolved-mistakes'),
          tilePadding: EdgeInsets.zero,
          childrenPadding: EdgeInsets.zero,
          initiallyExpanded: false,
          shape: const Border(),
          collapsedShape: const Border(),
          leading: Icon(Icons.task_alt, size: 20, color: colors.success),
          title: Text.rich(
            TextSpan(
              text: 'Resolved',
              children: [
                TextSpan(
                  text: '  ${resolved.length}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colors.faintText,
                  ),
                ),
              ],
            ),
            style: theme.textTheme.titleSmall,
          ),
          subtitle: Text(
            'Answered correctly twice in a row, or marked as known.',
            style: theme.textTheme.bodySmall?.copyWith(color: colors.mutedText),
          ),
          children: [
            for (final r in resolved)
              ListRowTile(
                dense: true,
                leading: Icon(
                  Icons.check_circle_outline,
                  size: 18,
                  color: colors.faintText,
                ),
                title: Text(
                  r.question.prompt,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${r.quiz.title} · resolved '
                  '${formatDate(r.mistake.resolvedAt!)}',
                ),
              ),
          ],
        ),
      ),
    );
  }
}
