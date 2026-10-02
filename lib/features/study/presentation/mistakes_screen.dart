import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/widgets/design_system.dart';
import '../../../data/data_providers.dart';
import '../../../data/models/subject.dart';
import '../../../data/repositories/mistake_repository.dart';
import '../../quizzes/presentation/mistakes_practice_screen.dart';
import '../../quizzes/widgets/quiz_format.dart'
    show errorText, formatDate, plural, showSnack;
import '../widgets/mistakes_history.dart';

/// Open mistakes of one subject (groups keep the repository order: most
/// recent wrong answer first).
class MistakeSubjectGroup {
  const MistakeSubjectGroup({
    required this.subjectId,
    required this.subject,
    required this.groups,
  });

  final String subjectId;

  /// Null when the subject isn't cached (e.g. a quiz shared on its own).
  final Subject? subject;
  final List<MistakeGroup> groups;

  int get count => groups.fold(0, (n, g) => n + g.entries.length);
}

/// Groups quiz groups by subject, in order of first appearance.
List<MistakeSubjectGroup> groupMistakesBySubject(
  List<MistakeGroup> groups,
  Map<String, Subject> subjects,
) {
  final bySubject = <String, List<MistakeGroup>>{};
  for (final g in groups) {
    if (g.entries.isEmpty) continue;
    (bySubject[g.quiz.subjectId] ??= []).add(g);
  }
  return [
    for (final MapEntry(key: id, value: list) in bySubject.entries)
      MistakeSubjectGroup(subjectId: id, subject: subjects[id], groups: list),
  ];
}

/// The user's Mistakes set: open mistakes grouped by subject and quiz, with
/// per-quiz and combined practice, plus the resolved history.
class MistakesScreen extends ConsumerWidget {
  const MistakesScreen({super.key});

  void _practiceAll(BuildContext context, List<MistakeGroup> groups) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => MistakesPracticeScreen(groups: groups),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupsAsync = ref.watch(openMistakesProvider);
    final subjects = {
      for (final s in ref.watch(subjectsProvider).value ?? const <Subject>[])
        s.id: s,
    };

    return ResponsiveScaffold(
      appBar: AppBar(title: const Text('Mistakes')),
      scrollable: true,
      body: AsyncValueView(
        value: groupsAsync,
        loading: const LoadingSkeleton(rows: 4),
        onRetry: () => ref.invalidate(openMistakesProvider),
        data: (groups) {
          final bySubject = groupMistakesBySubject(groups, subjects);
          final total = bySubject.fold<int>(0, (n, s) => n + s.count);
          final quizCount = bySubject.fold<int>(
            0,
            (n, s) => n + s.groups.length,
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (total == 0)
                const Padding(
                  padding: EdgeInsets.only(top: Insets.xxl),
                  child: EmptyState(
                    icon: Icons.task_alt,
                    title: 'No mistakes to review',
                    message:
                        'Questions you answer wrongly in quizzes and exams '
                        'show up here. Answer one correctly twice in a row '
                        'to clear it.',
                  ),
                )
              else ...[
                _Summary(
                  total: total,
                  quizCount: quizCount,
                  onPracticeAll: () => _practiceAll(context, [
                    for (final s in bySubject) ...s.groups,
                  ]),
                ),
                for (final s in bySubject) _SubjectSection(group: s),
              ],
              const ResolvedMistakesSection(),
              Gaps.h24,
            ],
          );
        },
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({
    required this.total,
    required this.quizCount,
    required this.onPracticeAll,
  });

  final int total;
  final int quizCount;
  final VoidCallback onPracticeAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${plural(total, 'open mistake')} in '
          '${plural(quizCount, 'quiz', 'quizzes')}',
          key: const Key('mistakes-summary'),
          style: theme.textTheme.titleMedium,
        ),
        Gaps.h4,
        Text(
          'Answer a question correctly twice in a row to clear it.',
          style: theme.textTheme.bodyMedium?.copyWith(color: colors.mutedText),
        ),
      ],
    );
    final button = FilledButton.icon(
      key: const Key('practice-all-mistakes'),
      onPressed: onPracticeAll,
      icon: const Icon(Icons.play_arrow_rounded),
      label: const Text('Practice all'),
    );
    return Padding(
      padding: const EdgeInsets.only(top: Insets.sm, bottom: Insets.sm),
      child: LayoutBuilder(
        builder: (context, c) => c.maxWidth >= 520
            ? Row(
                children: [
                  Expanded(child: text),
                  Gaps.w16,
                  button,
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [text, Gaps.h12, button],
              ),
      ),
    );
  }
}

class _SubjectSection extends StatelessWidget {
  const _SubjectSection({required this.group});

  final MistakeSubjectGroup group;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final subject = group.subject;
    return Column(
      key: Key('mistakes-subject-${group.subjectId}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: Insets.xl, bottom: Insets.sm),
          child: Row(
            children: [
              SubjectColorDot(color: subject?.color),
              Gaps.w8,
              Expanded(
                child: Text.rich(
                  TextSpan(
                    text: subject?.title ?? 'Other quizzes',
                    children: [
                      TextSpan(
                        text: '  ${group.count}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colors.faintText,
                        ),
                      ),
                    ],
                  ),
                  style: theme.textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        for (final g in group.groups)
          Padding(
            padding: const EdgeInsets.only(bottom: Insets.sm),
            child: _QuizCard(group: g),
          ),
      ],
    );
  }
}

class _QuizCard extends ConsumerWidget {
  const _QuizCard({required this.group});

  final MistakeGroup group;

  Future<void> _resolve(
    BuildContext context,
    WidgetRef ref,
    MistakeEntry e,
  ) async {
    try {
      await ref
          .read(mistakeRepositoryProvider)
          .resolve(quizId: group.quiz.id, questionId: e.question.id);
      if (context.mounted) showSnack(context, 'Marked as known');
    } on Object catch (err) {
      if (context.mounted) showSnack(context, errorText(err));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final quiz = group.quiz;
    final last = group.lastWrongAt;
    return AppCard(
      key: Key('mistakes-quiz-${quiz.id}'),
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Insets.lg,
              Insets.md,
              Insets.md,
              Insets.md,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      InkWell(
                        borderRadius: Radii.smAll,
                        onTap: () => context.push(AppRoutes.quiz(quiz.id)),
                        child: Text(
                          quiz.title,
                          style: theme.textTheme.titleSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Gaps.h2,
                      Text(
                        [
                          plural(group.entries.length, 'mistake'),
                          if (last != null) 'last wrong ${formatDate(last)}',
                        ].join(' · '),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.mutedText,
                        ),
                      ),
                    ],
                  ),
                ),
                Gaps.w8,
                FilledButton.tonalIcon(
                  key: Key('practice-quiz-${quiz.id}'),
                  onPressed: () => context.push(
                    AppRoutes.quizPlay(quiz.id, mode: 'mistakes'),
                  ),
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: const Text('Practice'),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: colors.hairline),
          for (final e in group.entries)
            ListRowTile(
              key: Key('mistake-${quiz.id}-${e.question.id}'),
              dense: true,
              leading: Icon(
                Icons.highlight_off,
                size: 18,
                color: colors.danger,
              ),
              title: Text(
                e.question.prompt,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                [
                  'Wrong ${e.mistake.wrongCount}×',
                  if (e.mistake.lastWrongAt != null)
                    formatDate(e.mistake.lastWrongAt!),
                  if (e.mistake.correctStreak > 0)
                    '${e.mistake.correctStreak} correct in a row',
                ].join(' · '),
              ),
              actions: [
                IconButton(
                  tooltip: 'I know this',
                  icon: const Icon(Icons.check),
                  onPressed: () => _resolve(context, ref, e),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
