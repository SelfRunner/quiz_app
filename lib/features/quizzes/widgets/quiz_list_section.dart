import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../data/data_providers.dart';
import '../../../data/models/quiz.dart';
import '../../ai_generate/presentation/ai_generate_screen.dart';
import 'quiz_format.dart';

/// Lists the quizzes of a subject (when [noteId] is null: subject-level
/// quizzes) or of a note, with actions to open, create and AI-generate.
///
/// Cross-feature entry point: subject and note screens embed this; the
/// quizzes feature owns the implementation. Renders as a non-scrolling
/// column, so it can sit inside the parent's scroll view.
class QuizListSection extends ConsumerStatefulWidget {
  const QuizListSection({
    super.key,
    required this.subjectId,
    this.noteId,
    this.readOnly = false,
  });

  final String subjectId;
  final String? noteId;

  /// True when the parent is shared with (not owned by) the current user.
  final bool readOnly;

  @override
  ConsumerState<QuizListSection> createState() => _QuizListSectionState();
}

class _QuizListSectionState extends ConsumerState<QuizListSection> {
  bool _creating = false;

  Future<void> _create() async {
    setState(() => _creating = true);
    try {
      final quiz = await ref
          .read(quizRepositoryProvider)
          .create(
            subjectId: widget.subjectId,
            noteId: widget.noteId,
            title: 'Untitled quiz',
          );
      if (!mounted) return;
      await context.push(AppRoutes.quizEdit(quiz.id));
    } on Object catch (e) {
      if (mounted) showSnack(context, errorText(e));
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final noteId = widget.noteId;
    final quizzes = noteId == null
        ? ref
              .watch(quizzesBySubjectProvider(widget.subjectId))
              .whenData(
                (l) => [
                  for (final q in l)
                    if (q.noteId == null) q,
                ],
              )
        : ref.watch(quizzesByNoteProvider(noteId));
    final theme = Theme.of(context);

    final header = Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 4,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.quiz_outlined, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text('Quizzes', style: theme.textTheme.titleMedium),
              if (quizzes.value case final list? when list.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  '${list.length}',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (!widget.readOnly)
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              TextButton.icon(
                onPressed: () => context.push(
                  AppRoutes.generate(
                    kind: AiGenerateKind.quiz,
                    subjectId: widget.subjectId,
                    noteId: noteId,
                  ),
                ),
                icon: const Icon(Icons.auto_awesome),
                label: const Text('Generate with AI'),
              ),
              FilledButton.tonalIcon(
                onPressed: _creating ? null : _create,
                icon: _creating
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add),
                label: const Text('New quiz'),
              ),
            ],
          ),
      ],
    );

    final body = switch (quizzes) {
      AsyncValue(:final value?) when value.isEmpty => _EmptyQuizzes(
        readOnly: widget.readOnly,
        forNote: noteId != null,
      ),
      AsyncValue(:final value?) => Column(
        children: [for (final q in value) _QuizTile(quiz: q)],
      ),
      AsyncValue(:final error?) => Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          'Could not load quizzes: ${errorText(error)}',
          style: TextStyle(color: theme.colorScheme.error),
        ),
      ),
      _ => const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [header, const SizedBox(height: 4), body],
    );
  }
}

class _EmptyQuizzes extends StatelessWidget {
  const _EmptyQuizzes({required this.readOnly, required this.forNote});

  final bool readOnly;
  final bool forNote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Text(
        readOnly
            ? 'No quizzes here yet.'
            : forNote
            ? 'No quizzes for this note yet. Create one or let AI generate it '
                  'from the note.'
            : 'No quizzes yet. Create one by hand or generate it with AI.',
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _QuizTile extends ConsumerWidget {
  const _QuizTile({required this.quiz});

  final Quiz quiz;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attempts = completedAttempts(
      ref.watch(attemptsByQuizProvider(quiz.id)).value ?? const [],
    );
    final count = quiz.questions.length;
    final parts = <String>[plural(count, 'question')];
    if (attempts.isNotEmpty) {
      final percents = [for (final a in attempts) ?attemptPercent(a)];
      if (percents.isNotEmpty) {
        final best = percents.reduce((a, b) => a > b ? a : b);
        parts
          ..add('Best ${formatPercent(best)}')
          ..add('Last ${formatPercent(percents.first)}');
      }
    } else if (count > 0) {
      parts.add('Not played yet');
    }
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.secondaryContainer,
          foregroundColor: theme.colorScheme.onSecondaryContainer,
          child: Icon(
            quiz.source?.provider != null ? Icons.auto_awesome : Icons.quiz,
            size: 20,
          ),
        ),
        title: Text(quiz.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(parts.join(' · ')),
        onTap: () => context.push(AppRoutes.quiz(quiz.id)),
        trailing: count == 0
            ? null
            : IconButton(
                tooltip: 'Play',
                icon: const Icon(Icons.play_arrow_rounded),
                onPressed: () => context.push(AppRoutes.quizPlay(quiz.id)),
              ),
      ),
    );
  }
}
