import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/error_message.dart';
import '../../../data/data_providers.dart';
import '../../../data/models/models.dart';
import '../presentation/widgets/subject_form_dialog.dart';

/// UI flows for subjects shared by the list and detail screens.
abstract final class SubjectActions {
  /// Asks for subject details and creates it. Returns the new subject.
  static Future<Subject?> create(BuildContext context, WidgetRef ref) async {
    final result = await showSubjectFormDialog(context);
    if (result == null) return null;
    try {
      return await ref
          .read(subjectRepositoryProvider)
          .create(
            title: result.title,
            description: result.description,
            color: result.color,
          );
    } catch (e) {
      if (context.mounted) showErrorSnackBar(context, e);
      return null;
    }
  }

  static Future<void> edit(
    BuildContext context,
    WidgetRef ref,
    Subject subject,
  ) async {
    final result = await showSubjectFormDialog(context, subject: subject);
    if (result == null) return;
    try {
      await ref
          .read(subjectRepositoryProvider)
          .update(
            subject.copyWith(
              title: result.title,
              description: result.description,
              color: result.color,
            ),
          );
    } catch (e) {
      if (context.mounted) showErrorSnackBar(context, e);
    }
  }

  /// Confirms and deletes. Returns true when deleted.
  static Future<bool> delete(
    BuildContext context,
    WidgetRef ref,
    Subject subject,
  ) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Delete "${subject.title}"?',
      message:
          'All notes and quizzes in this subject will be deleted too. People '
          'you shared it with will lose access.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok) return false;
    try {
      await ref.read(subjectRepositoryProvider).delete(subject.id);
      if (context.mounted) showAppSnackBar(context, 'Subject deleted');
      return true;
    } catch (e) {
      if (context.mounted) showErrorSnackBar(context, e);
      return false;
    }
  }

  /// Creates an empty note in [subjectId] and opens the editor.
  static Future<void> newNote(
    BuildContext context,
    WidgetRef ref,
    String subjectId,
  ) async {
    try {
      final note = await ref
          .read(noteRepositoryProvider)
          .create(subjectId: subjectId, title: 'Untitled note');
      if (context.mounted) {
        await context.push(AppRoutes.noteEdit(note.id));
      }
    } catch (e) {
      if (context.mounted) showErrorSnackBar(context, e);
    }
  }
}
