import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/widgets/design_system.dart';
import '../../../core/widgets/error_message.dart';
import '../../../core/widgets/sync_status_indicator.dart';
import '../../../data/data_providers.dart';
import '../../../data/models/models.dart';
import '../../../data/repositories/note_repository.dart';
import '../../ai_generate/presentation/ai_generate_screen.dart';
import '../../decks/widgets/deck_list_section.dart';
import '../../quizzes/widgets/quiz_list_section.dart';
import '../../sharing/widgets/share_actions.dart';
import '../../subjects/presentation/subject_detail_screen.dart' show MetaChip;
import '../application/note_actions.dart';
import '../application/note_ai_tools.dart';
import '../application/note_document.dart';
import '../application/note_markdown_syntax.dart';
import 'widgets/note_ai_tools.dart';
import 'widgets/note_toc.dart';
import 'widgets/rich_note_markdown.dart';

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
        loading: const ContentContainer(child: LoadingSkeleton()),
        onRetry: () => ref.invalidate(noteProvider(noteId)),
        data: (_) => const NotFoundView(what: 'Note'),
      ),
    );
  }
}

class _NoteView extends ConsumerStatefulWidget {
  const _NoteView({required this.note});

  final Note note;

  @override
  ConsumerState<_NoteView> createState() => _NoteViewState();
}

class _NoteViewState extends ConsumerState<_NoteView> {
  final _anchors = NoteAnchors();
  String? _parsedFor;
  List<NoteHeading> _headings = const [];

  Note get note => widget.note;

  List<NoteHeading> get headings {
    if (_parsedFor != note.contentMd) {
      _parsedFor = note.contentMd;
      _headings = noteHeadings(note.contentMd);
    }
    return _headings;
  }

  NoteRepository get _repo => ref.read(noteRepositoryProvider);

  Future<void> _saveContent(
    String markdown, {
    String? message,
    bool undo = false,
  }) async {
    final before = note;
    try {
      await _repo.update(note.copyWith(contentMd: markdown));
      if (!mounted || message == null) return;
      showAppSnackBar(
        context,
        message,
        action: undo
            ? SnackBarAction(
                label: 'Undo',
                onPressed: () => unawaited(
                  _saveContent(before.contentMd, message: 'Undone'),
                ),
              )
            : null,
      );
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e, prefix: 'Could not save');
    }
  }

  void _toggleTask(int index, bool checked) {
    final updated = NoteDocument.setTask(
      note.contentMd,
      index,
      checked: checked,
    );
    if (updated == null) {
      showAppSnackBar(
        context,
        "This checkbox can't be changed here. Edit the note instead.",
      );
      return;
    }
    unawaited(_saveContent(updated));
  }

  NoteAiHost _aiHost(bool isOwner) => NoteAiHost(
    currentMarkdown: () => note.contentMd,
    title: note.title,
    subjectId: isOwner ? note.subjectId : null,
    onReplace: isOwner
        ? (markdown) =>
              _saveContent(markdown, message: 'Note replaced', undo: true)
        : null,
    onInsertBelow: isOwner
        ? (markdown) => _saveContent(
            appendMarkdown(note.contentMd, markdown),
            message: 'Inserted below',
            undo: true,
          )
        : null,
  );

  Future<void> _showTocSheet() async {
    final heading = await showNoteTocSheet(context, headings);
    if (heading != null && mounted) unawaited(_anchors.reveal(heading.index));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
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

    final showToc = noteNeedsToc(headings);
    final actions = <Widget>[
      if (showToc && !twoPane)
        IconButton(
          key: const Key('note-toc-button'),
          tooltip: 'Contents',
          icon: const Icon(Icons.toc),
          onPressed: _showTocSheet,
        ),
      NoteAiMenuButton(host: _aiHost(isOwner)),
      if (isOwner) ...[
        AiGate(
          onReady: generateQuiz,
          child: IconButton(
            key: const Key('note-generate-quiz'),
            tooltip: 'Generate quiz from this note',
            icon: const Icon(Icons.auto_awesome_outlined),
            onPressed: generateQuiz,
          ),
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
          icon: const Icon(Icons.more_horiz),
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
        Gaps.w4,
      ] else
        Padding(
          padding: const EdgeInsets.only(right: Insets.sm),
          child: CopyToAccountButton(
            type: ShareResourceType.note,
            resourceId: note.id,
          ),
        ),
    ];

    final metaStyle = theme.textTheme.bodySmall?.copyWith(
      color: colors.mutedText,
    );
    final meta = Wrap(
      spacing: Insets.md,
      runSpacing: Insets.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (subject != null)
          InkWell(
            key: const Key('note-subject-link'),
            borderRadius: Radii.smAll,
            onTap: () => context.push(AppRoutes.subject(subject.id)),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Insets.xxs,
                vertical: Insets.xxs,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SubjectColorDot(color: subject.color, size: 8),
                  Gaps.w8,
                  Text(subject.title, style: metaStyle),
                ],
              ),
            ),
          ),
        if (!isOwner)
          const MetaChip(
            icon: Icons.visibility_outlined,
            label: 'Shared · read-only',
          ),
        Text('Updated ${formatRelativeTime(note.updatedAt)}', style: metaStyle),
        if (note.contentMd.trim().isNotEmpty)
          Text(
            '${NoteDocument.readingMinutes(NoteDocument.wordCount(note.contentMd))} min read',
            key: const Key('note-reading-time'),
            style: metaStyle,
          ),
      ],
    );

    final content = note.contentMd.trim().isEmpty
        ? EmptyState(
            compact: true,
            icon: Icons.edit_note,
            title: 'This note is empty',
            action: isOwner
                ? FilledButton.icon(
                    onPressed: () => context.push(AppRoutes.noteEdit(note.id)),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Start writing'),
                  )
                : null,
          )
        : RichNoteMarkdown(
            data: note.contentMd,
            anchors: _anchors,
            onToggleTask: isOwner ? _toggleTask : null,
          );

    // QuizListSection / DeckListSection bring their own headers and actions.
    final studySections = Column(
      key: const Key('note-study-sections'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        QuizListSection(
          subjectId: note.subjectId,
          noteId: note.id,
          readOnly: !isOwner,
        ),
        DeckListSection(
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
        Gaps.h8,
        meta,
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Insets.lg),
          child: Divider(height: 1, color: colors.hairline),
        ),
        content,
      ],
    );

    final hairline = BorderSide(color: colors.hairline);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          subject?.title ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleSmall?.copyWith(color: colors.mutedText),
        ),
        actions: actions,
      ),
      body: twoPane
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(
                      top: Insets.lg,
                      bottom: Insets.xxxl,
                    ),
                    child: ContentContainer(child: article),
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.sidebar,
                    border: Border(left: hairline),
                  ),
                  child: SizedBox(
                    width: 360,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(Insets.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (showToc) ...[
                            NoteTableOfContents(
                              headings: headings,
                              onSelect: (h) =>
                                  unawaited(_anchors.reveal(h.index)),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: Insets.lg,
                              ),
                              child: Divider(height: 1, color: colors.hairline),
                            ),
                          ],
                          studySections,
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.only(
                top: Insets.sm,
                bottom: Insets.xxxl,
              ),
              child: ContentContainer(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    article,
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: Insets.xl),
                      child: Divider(height: 1, color: colors.hairline),
                    ),
                    studySections,
                  ],
                ),
              ),
            ),
    );
  }
}
