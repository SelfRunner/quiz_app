import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/widgets/design_system.dart' hide MaxWidth;
import '../../../data/data_providers.dart';
import '../../../data/models/quiz.dart';
import '../../ai_generate/presentation/ai_generate_screen.dart';
import 'quiz_format.dart';

/// Lists the quizzes of a subject (when [noteId] is null: every quiz of the
/// subject, subject-level ones first, then note quizzes labeled with their
/// note) or of a note (only that note's quizzes), with actions to open, create and AI-generate.
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

  void _generate() => context.push(
    AppRoutes.generate(
      kind: AiGenerateKind.quiz,
      subjectId: widget.subjectId,
      noteId: widget.noteId,
    ),
  );

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
                  for (final q in l)
                    if (q.noteId != null) q,
                ],
              )
        : ref.watch(quizzesByNoteProvider(noteId));

    final actions = widget.readOnly
        ? null
        : <Widget>[
            AiGate(
              key: const Key('quiz-generate-ai'),
              onReady: _generate,
              child: TextButton.icon(
                onPressed: _generate,
                icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                label: const Text('Generate with AI'),
              ),
            ),
            TextButton.icon(
              key: const Key('quiz-new'),
              onPressed: _creating ? null : _create,
              icon: _creating
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add, size: 18),
              label: const Text('New quiz'),
            ),
          ];

    final count = quizzes.value?.length;
    final header = LayoutBuilder(
      builder: (context, constraints) {
        // Phones: actions go on their own line so the title never squeezes.
        final inline = constraints.maxWidth >= 480;
        final title = SectionHeader(
          title: 'Quizzes',
          count: count == null || count == 0 ? null : count,
          trailing: inline && actions != null
              ? Row(mainAxisSize: MainAxisSize.min, children: actions)
              : null,
        );
        if (inline || actions == null) return title;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            title,
            Wrap(spacing: Insets.xs, runSpacing: Insets.xs, children: actions),
            Gaps.h4,
          ],
        );
      },
    );

    final body = switch (quizzes) {
      AsyncValue(:final value?) when value.isEmpty => EmptyState(
        compact: true,
        icon: Icons.quiz_outlined,
        title: 'No quizzes yet',
        message: widget.readOnly
            ? null
            : noteId != null
            ? 'Create one or let AI generate it from the note.'
            : 'Create one by hand or generate it with AI.',
      ),
      AsyncValue(:final value?) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final q in value)
            _QuizTile(quiz: q, showNote: noteId == null && q.noteId != null),
        ],
      ),
      AsyncValue(:final error?) => InfoBanner(
        kind: InfoBannerKind.error,
        message: 'Could not load quizzes: ${errorText(error)}',
      ),
      _ => const LoadingSkeleton(rows: 2, animate: false),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [header, body],
    );
  }
}

class _QuizTile extends ConsumerWidget {
  const _QuizTile({required this.quiz, this.showNote = false});

  final Quiz quiz;

  /// Label the quiz with its note (subject-wide listing).
  final bool showNote;

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
    final aiMade = quiz.source?.provider != null;
    final noteId = quiz.noteId;
    final noteTitle = showNote && noteId != null
        ? ref.watch(noteProvider(noteId)).value?.title
        : null;
    final colors = AppColors.of(context);
    return ListRowTile(
      key: ValueKey('quiz-row-${quiz.id}'),
      leading: Tooltip(
        message: aiMade ? 'Generated with AI' : 'Quiz',
        child: Icon(aiMade ? Icons.auto_awesome_outlined : Icons.quiz_outlined),
      ),
      title: Text(quiz.title),
      subtitle: showNote
          ? Text.rich(
              TextSpan(
                children: [
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Padding(
                      padding: const EdgeInsets.only(right: Insets.xs),
                      child: Icon(
                        Icons.description_outlined,
                        size: 14,
                        color: colors.faintText,
                      ),
                    ),
                  ),
                  TextSpan(
                    text:
                        'From note: '
                        '${noteTitle == null || noteTitle.trim().isEmpty ? 'Untitled note' : noteTitle}',
                  ),
                  TextSpan(text: ' · ${parts.join(' · ')}'),
                ],
              ),
              key: ValueKey('quiz-note-label-${quiz.id}'),
            )
          : Text(parts.join(' · ')),
      onTap: () => context.push(AppRoutes.quiz(quiz.id)),
      actions: [
        if (count > 0)
          IconButton(
            tooltip: 'Play',
            icon: const Icon(Icons.play_arrow_rounded),
            onPressed: () => context.push(AppRoutes.quizPlay(quiz.id)),
          ),
      ],
    );
  }
}
