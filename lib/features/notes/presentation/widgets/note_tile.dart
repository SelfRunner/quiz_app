import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/routes.dart';
import '../../../../core/widgets/design_system.dart';
import '../../../../core/widgets/sync_status_indicator.dart';
import '../../../../data/models/models.dart';
import '../../application/markdown_editing.dart';
import '../../application/note_actions.dart';

/// List row for a note: title, plain-text preview, last update.
class NoteTile extends ConsumerWidget {
  const NoteTile({super.key, required this.note, required this.canEdit});

  final Note note;
  final bool canEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preview = markdownPreviewText(note.contentMd);
    final edited = 'Edited ${formatRelativeTime(note.updatedAt)}';
    final wide = Breakpoints.isMedium(context);
    return ListRowTile(
      leading: const Icon(Icons.description_outlined),
      title: Text(note.title.isEmpty ? 'Untitled note' : note.title),
      subtitle: Text(
        [if (preview.isNotEmpty) preview, if (!wide) edited].join(' · '),
        maxLines: 1,
      ),
      trailing: wide ? Text(edited) : null,
      onTap: () => context.push(AppRoutes.note(note.id)),
      actions: [
        if (canEdit)
          PopupMenuButton<String>(
            tooltip: 'More',
            icon: Icon(
              Icons.more_horiz,
              color: AppColors.of(context).mutedText,
            ),
            onSelected: (v) {
              if (v == 'edit') {
                context.push(AppRoutes.noteEdit(note.id));
              } else if (v == 'delete') {
                NoteActions.delete(context, ref, note).ignore();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'edit',
                child: ListTile(
                  leading: Icon(Icons.edit_outlined),
                  title: Text('Edit'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
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
