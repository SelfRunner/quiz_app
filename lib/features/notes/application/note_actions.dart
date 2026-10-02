import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/error_message.dart';
import '../../../data/data_providers.dart';
import '../../../data/models/models.dart';

abstract final class NoteActions {
  /// Confirms and deletes a note (and its quizzes). Returns true if deleted.
  static Future<bool> delete(
    BuildContext context,
    WidgetRef ref,
    Note note,
  ) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Delete "${note.title.isEmpty ? 'Untitled note' : note.title}"?',
      message: 'Quizzes attached to this note will be deleted too.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok) return false;
    try {
      await ref.read(noteRepositoryProvider).delete(note.id);
      if (context.mounted) showAppSnackBar(context, 'Note deleted');
      return true;
    } catch (e) {
      if (context.mounted) showErrorSnackBar(context, e);
      return false;
    }
  }
}
