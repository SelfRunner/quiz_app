import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/routes.dart';
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
    final theme = Theme.of(context);
    final preview = markdownPreviewText(note.contentMd);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
        leading: const Icon(Icons.description_outlined),
        title: Text(
          note.title.isEmpty ? 'Untitled note' : note.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          [
            if (preview.isNotEmpty) preview,
            'Updated ${formatRelativeTime(note.updatedAt)}',
          ].join('\n'),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        isThreeLine: preview.isNotEmpty,
        onTap: () => context.push(AppRoutes.note(note.id)),
        trailing: canEdit
            ? PopupMenuButton<String>(
                tooltip: 'More',
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
              )
            : null,
      ),
    );
  }
}
