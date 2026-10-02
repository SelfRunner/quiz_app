import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/routes.dart';
import '../../../../core/widgets/design_system.dart';
import '../../../../core/widgets/sync_status_indicator.dart';
import '../../../../core/widgets/tag_widgets.dart';
import '../../../../data/models/models.dart';
import '../../../../data/repositories/organization_repository.dart';
import '../../application/markdown_editing.dart';
import '../../application/note_actions.dart';
import '../../application/note_export_actions.dart';

/// List row for a note: title (pin marker), plain-text preview, tags, last
/// update. Owners get Edit / Pin / Tags / Delete in the row menu.
class NoteTile extends ConsumerWidget {
  const NoteTile({super.key, required this.note, required this.canEdit});

  final Note note;
  final bool canEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preview = markdownPreviewText(note.contentMd);
    final edited = 'Edited ${formatRelativeTime(note.updatedAt)}';
    final wide = Breakpoints.isMedium(context);
    final colors = AppColors.of(context);
    final previewLine = Text(
      [if (preview.isNotEmpty) preview, if (!wide) edited].join(' · '),
      maxLines: 1,
    );
    return ListRowTile(
      key: ValueKey('note-row-${note.id}'),
      leading: const Icon(Icons.description_outlined),
      title: Row(
        children: [
          Flexible(
            child: Text(
              note.title.isEmpty ? 'Untitled note' : note.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (note.pinned)
            Padding(
              padding: const EdgeInsets.only(left: Insets.xs),
              child: Icon(
                Icons.push_pin,
                key: ValueKey('note-pinned-${note.id}'),
                size: 14,
                color: colors.faintText,
                semanticLabel: 'Pinned',
              ),
            ),
        ],
      ),
      subtitle: note.tags.isEmpty
          ? previewLine
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                previewLine,
                Gaps.h4,
                TagChips(tags: note.tags, dense: true, maxVisible: 3),
              ],
            ),
      trailing: wide ? Text(edited) : null,
      onTap: () => context.push(AppRoutes.note(note.id)),
      actions: [
        if (canEdit)
          PopupMenuButton<String>(
            tooltip: 'More',
            icon: Icon(Icons.more_horiz, color: colors.mutedText),
            onSelected: (v) {
              switch (v) {
                case 'edit':
                  context.push(AppRoutes.noteEdit(note.id));
                case 'pin':
                  setNotePinned(context, ref, note, !note.pinned).ignore();
                case 'tags':
                  editItemTags(
                    context,
                    ref,
                    kind: TaggableKind.note,
                    id: note.id,
                    tags: note.tags,
                  ).ignore();
                case 'delete':
                  NoteActions.delete(context, ref, note).ignore();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'edit',
                child: ListTile(
                  leading: Icon(Icons.edit_outlined),
                  title: Text('Edit'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                key: ValueKey('note-row-pin-${note.id}'),
                value: 'pin',
                child: ListTile(
                  leading: Icon(
                    note.pinned ? Icons.push_pin : Icons.push_pin_outlined,
                  ),
                  title: Text(note.pinned ? 'Unpin' : 'Pin'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                key: ValueKey('note-row-tags-${note.id}'),
                value: 'tags',
                child: const ListTile(
                  leading: Icon(Icons.sell_outlined),
                  title: Text('Edit tags'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  leading: Icon(Icons.delete_outline),
                  title: Text('Delete'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
      ],
    );
  }
}
