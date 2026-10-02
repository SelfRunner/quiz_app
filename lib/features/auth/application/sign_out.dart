import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/error_message.dart';
import '../../../data/data_providers.dart';

/// Confirms and signs out. Warns when local changes have not been pushed yet
/// (local data is wiped on sign-out after a best-effort final sync). The
/// router redirects to the login screen once the auth state changes.
Future<void> confirmAndSignOut(BuildContext context, WidgetRef ref) async {
  final pending = ref.read(syncStatusProvider).value?.pendingOps ?? 0;
  final confirmed = await showConfirmDialog(
    context,
    title: 'Sign out?',
    message: pending > 0
        ? 'You have $pending change${pending == 1 ? '' : 's'} not yet synced. '
              'We will try to sync them first; anything that cannot be synced '
              'will be lost from this device.'
        : 'Your data stays in your account and syncs back when you sign in '
              'again.',
    confirmLabel: 'Sign out',
    destructive: pending > 0,
  );
  if (!confirmed) return;
  try {
    await ref.read(authRepositoryProvider).signOut();
  } catch (e) {
    if (context.mounted) showErrorSnackBar(context, e);
  }
}
