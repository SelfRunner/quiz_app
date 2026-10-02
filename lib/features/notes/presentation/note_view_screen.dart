import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/widgets/note_markdown.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/sync_status_indicator.dart';
import '../../../data/data_providers.dart';
import '../../../data/models/models.dart';
import '../../ai_generate/presentation/ai_generate_screen.dart';
import '../../quizzes/widgets/quiz_list_section.dart';
import '../../sharing/widgets/share_actions.dart';
import '../application/note_actions.dart';

/// Rendered note with its quizzes. Owners can edit, share, delete and
/// generate quizzes from the note; shared notes are read-only.
class NoteViewScreen extends ConsumerWidget {
  const NoteViewScreen({super.key, required this.noteId});

  final String noteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final note = ref.watch(noteProvider(noteId));
    final value = note.value;
    if (value != null) return _NoteView(note: value);
    return Scaffold(
      appBar: AppBar(),
      body: AsyncValueView<Note?>(
        value: note,
        onRetry: () => ref.invalidate(noteProvider(noteId)),
        data: (_) => const NotFoundView(what: 'Note'),
      ),
    );
  }
}

class _NoteView extends ConsumerWidget {
  const _NoteView({required this.note});

  final Note note;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isOwner = note.isOwnedBy(ref.watch(currentUserIdProvider));
    final subject = ref.watch(subjectProvider(note.subjectId)).value;
    final twoPane = Breakpoints.isExpanded(context);
    final title = note.title.isEmpty ? 'Untitled note' : note.title;

    void generateQuiz() => context.push(
      AppRoutes.generate(
        kind: AiGenerateKind.quiz,
        subjectId: note.subjectId,
        noteId: note.id,
      ),
    );

    final actions = <Widget>[
      if (isOwner) ...[
        IconButton(
          tooltip: 'Generate quiz from this note',
          icon: const Icon(Icons.auto_awesome_outlined),
          onPressed: generateQuiz,
        ),
        IconButton(
          tooltip: 'Share',
          icon: const Icon(Icons.share_outlined),
          onPressed: () => showShareSheet(
            context,
            type: ShareResourceType.note,
            resourceId: note.id,
            title: title,
          ),
        ),
        IconButton(
          key: const Key('note-edit'),
          tooltip: 'Edit',
          icon: const Icon(Icons.edit_outlined),
          onPressed: () => context.push(AppRoutes.noteEdit(note.id)),
        ),
        PopupMenuButton<String>(
          tooltip: 'More',
          onSelected: (v) async {
            if (v != 'delete') return;
            final deleted = await NoteActions.delete(context, ref, note);
            if (deleted && context.mounted) {
              context.canPop()
                  ? context.pop()
                  : context.go(AppRoutes.subject(note.subjectId));
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: 'delete',
              child: ListTile(
                leading: Icon(Icons.delete_outline),
                title: Text('Delete note'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ] else
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: CopyToAccountButton(
            type: ShareResourceType.note,
            resourceId: note.id,
          ),
        ),
    ];

    final meta = Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (subject != null)
          ActionChip(
            avatar: const Icon(Icons.folder_outlined, size: 18),
            label: Text(subject.title),
            onPressed: () => context.push(AppRoutes.subject(subject.id)),
          ),
        if (!isOwner)
          const Chip(
            avatar: Icon(Icons.visibility_outlined, size: 18),
            label: Text('Shared · read-only'),
          ),
        Text(
          'Updated ${formatRelativeTime(note.updatedAt)}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );

    final content = note.contentMd.trim().isEmpty
        ? Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: EmptyState(
              icon: Icons.edit_note,
              title: 'This note is empty',
              action: isOwner
                  ? FilledButton.icon(
                      onPressed: () =>
                          context.push(AppRoutes.noteEdit(note.id)),
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Start writing'),
                    )
                  : null,
            ),
          )
        : NoteMarkdown(data: note.contentMd);

    final quizzes = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.quiz_outlined, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Quizzes from this note',
                style: theme.textTheme.titleMedium,
              ),
            ),
            if (isOwner)
              TextButton.icon(
                onPressed: generateQuiz,
                icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                label: const Text('Generate'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        QuizListSection(
          subjectId: note.subjectId,
          noteId: note.id,
          readOnly: !isOwner,
        ),
      ],
    );

    final article = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: theme.textTheme.headlineMedium),
        const SizedBox(height: 8),
        meta,
        const Divider(height: 32),
        content,
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: actions,
      ),
      body: twoPane
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(32, 16, 32, 48),
                    child: MaxWidth(maxWidth: 820, child: article),
                  ),
                ),
                const VerticalDivider(width: 1),
                SizedBox(
                  width: 380,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: quizzes,
                  ),
                ),
              ],
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
              child: MaxWidth(
                maxWidth: 820,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [article, const Divider(height: 48), quizzes],
                ),
              ),
            ),
    );
  }
}
