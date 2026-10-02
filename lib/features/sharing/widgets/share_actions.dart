import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../data/data_providers.dart';
import '../../../data/models/models.dart';
import '../sharing_ui.dart';
import 'copy_target_picker.dart';
import 'share_sheet.dart';

/// Opens the share sheet for a subject, note or quiz the current user owns.
///
/// Bottom sheet on phones, dialog on wide screens (>= 720 px). Lets the owner
/// invite people by exact email and revoke access. Online-only; offline
/// states are shown inside the sheet.
///
/// Cross-feature entry point: subject/note/quiz screens call this; the
/// sharing feature owns the implementation.
Future<void> showShareSheet(
  BuildContext context, {
  required ShareResourceType type,
  required String resourceId,
  required String title,
}) {
  if (isWideLayout(context)) {
    return showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
          child: ShareSheet(
            type: type,
            resourceId: resourceId,
            title: title,
            inDialog: true,
          ),
        ),
      ),
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: ShareSheet(type: type, resourceId: resourceId, title: title),
      ),
    ),
  );
}

/// Action shown on read-only (shared-with-me) subject/note/quiz screens that
/// copies the resource into the current user's account.
///
/// Notes and quizzes ask for a target subject first (an existing own subject
/// or a new one). Shows progress while copying and a snackbar with "Open"
/// that navigates to the copy. Set [compact] for an app-bar icon button.
/// For a popup-menu item, call [copySharedToMyAccount] directly.
class CopyToAccountButton extends StatelessWidget {
  const CopyToAccountButton({
    super.key,
    required this.type,
    required this.resourceId,
    this.compact = false,
  });

  final ShareResourceType type;
  final String resourceId;

  /// Render as an [IconButton] (e.g. in an AppBar) instead of a tonal button.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    void onPressed() => unawaited(
      copySharedToMyAccount(context, type: type, resourceId: resourceId),
    );
    if (compact) {
      return IconButton(
        tooltip: 'Copy to my account',
        icon: const Icon(Icons.copy_all_outlined),
        onPressed: onPressed,
      );
    }
    return FilledButton.tonalIcon(
      onPressed: onPressed,
      icon: const Icon(Icons.copy_all_outlined),
      label: const Text('Copy to my account'),
    );
  }
}

/// Runs the full "copy to my account" flow for a shared resource: target
/// picker (notes/quizzes) or confirmation (subjects), blocking progress
/// dialog, then a snackbar with an "Open" action. Returns the new id, or
/// null when cancelled or failed (errors are shown in a snackbar).
Future<String?> copySharedToMyAccount(
  BuildContext context, {
  required ShareResourceType type,
  required String resourceId,
}) async {
  // The container outlives the calling widget (which may be rebuilt away
  // while the copy runs), unlike a WidgetRef.
  final ref = ProviderScope.containerOf(context, listen: false);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final router = GoRouter.maybeOf(context);
  final title = await _resourceTitle(ref, type, resourceId);
  if (!context.mounted) return null;

  CopyTarget? target;
  if (type == ShareResourceType.subject) {
    final ok = await _confirmSubjectCopy(context, title);
    if (ok != true) return null;
  } else {
    final suggested = await _parentSubjectTitle(ref, type, resourceId);
    if (!context.mounted) return null;
    target = await showCopyTargetPicker(
      context,
      type: type,
      suggestedTitle: suggested,
    );
    if (target == null) return null;
  }
  if (!context.mounted) return null;

  final navigator = Navigator.of(context, rootNavigator: true);
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => const _CopyProgressDialog(),
    ),
  );

  String? newId;
  Object? failure;
  try {
    var subjectId = target?.subjectId;
    final newTitle = target?.newSubjectTitle;
    if (newTitle != null) {
      final created = await ref
          .read(subjectRepositoryProvider)
          .create(title: newTitle);
      subjectId = created.id;
    }
    newId = await ref
        .read(shareRepositoryProvider)
        .copyToMyAccount(
          resourceType: type,
          resourceId: resourceId,
          targetSubjectId: subjectId,
        );
  } catch (e) {
    failure = e;
  } finally {
    if (navigator.mounted) navigator.pop();
  }

  if (newId == null) {
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          "Couldn't copy this ${type.noun}. ${friendlyError(failure!)}",
        ),
      ),
    );
    return null;
  }
  final copiedId = newId;
  final location = switch (type) {
    ShareResourceType.subject => AppRoutes.subject(copiedId),
    ShareResourceType.note => AppRoutes.note(copiedId),
    ShareResourceType.quiz => AppRoutes.quiz(copiedId),
    // No deck route yet (Wave 2 UI).
    ShareResourceType.deck => AppRoutes.subjects,
  };
  messenger?.showSnackBar(
    SnackBar(
      content: Text(
        title == null
            ? 'Copied to your account.'
            : 'Copied “$title” to your account.',
      ),
      action: router == null
          ? null
          : SnackBarAction(
              label: 'Open',
              onPressed: () => unawaited(router.push(location)),
            ),
    ),
  );
  return copiedId;
}

Future<bool?> _confirmSubjectCopy(BuildContext context, String? title) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.copy_all_outlined),
      title: const Text('Copy to my account?'),
      content: Text(
        '${title == null ? 'This subject' : '“$title”'} and all of its notes, '
        'images and quizzes will be copied into your account as a new '
        'subject you can edit. Later changes by the owner won\'t appear in '
        'your copy.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('copy-subject-confirm'),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Copy'),
        ),
      ],
    ),
  );
}

class _CopyProgressDialog extends StatelessWidget {
  const _CopyProgressDialog();

  @override
  Widget build(BuildContext context) {
    return const PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            SizedBox.square(
              dimension: 28,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            SizedBox(width: 20),
            Expanded(
              child: Text('Copying to your account…\nThis may take a moment.'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Best-effort title of the shared resource from the local cache.
Future<String?> _resourceTitle(
  ProviderContainer ref,
  ShareResourceType type,
  String id,
) async {
  try {
    return switch (type) {
      ShareResourceType.subject =>
        (await ref.read(subjectRepositoryProvider).getById(id))?.title,
      ShareResourceType.note =>
        (await ref.read(noteRepositoryProvider).getById(id))?.title,
      ShareResourceType.quiz =>
        (await ref.read(quizRepositoryProvider).getById(id))?.title,
      ShareResourceType.deck =>
        (await ref.read(deckRepositoryProvider).getById(id))?.title,
    };
  } catch (_) {
    return null;
  }
}

/// Title of the shared note's/quiz's subject, suggested as the name of a new
/// subject in the picker.
Future<String?> _parentSubjectTitle(
  ProviderContainer ref,
  ShareResourceType type,
  String id,
) async {
  try {
    final subjectId = switch (type) {
      ShareResourceType.subject => null,
      ShareResourceType.note =>
        (await ref.read(noteRepositoryProvider).getById(id))?.subjectId,
      ShareResourceType.quiz =>
        (await ref.read(quizRepositoryProvider).getById(id))?.subjectId,
      ShareResourceType.deck =>
        (await ref.read(deckRepositoryProvider).getById(id))?.subjectId,
    };
    if (subjectId == null) return null;
    return (await ref.read(subjectRepositoryProvider).getById(subjectId))
        ?.title;
  } catch (_) {
    return null;
  }
}
