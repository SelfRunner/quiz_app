import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ai/ai_providers.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/design_system.dart';
import '../../../core/widgets/error_message.dart';
import '../../../core/widgets/sync_status_indicator.dart';
import '../../../data/data_providers.dart';
import '../../../data/sync/sync_engine.dart';
import '../../auth/application/sign_out.dart';
import 'widgets/ai_settings_section.dart';

/// Account, AI provider, appearance, sync and "danger zone" settings.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ResponsiveScaffold(
      appBar: AppBar(title: const Text('Settings')),
      maxWidth: ContentWidth.form + 2 * Insets.gutterWide,
      scrollable: true,
      body: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Section(title: 'Account', child: _AccountTile()),
          _Section(
            title: 'AI provider',
            subtitle:
                'Bring your own API key. It stays on this device and is sent '
                'only to the provider you choose.',
            child: AiSettingsSection(),
          ),
          _Section(title: 'Appearance', child: _ThemePicker()),
          _Section(title: 'Sync', child: _SyncTile()),
          _Section(title: 'Danger zone', danger: true, child: _DangerZone()),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.child,
    this.subtitle,
    this.danger = false,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: title,
            subtitle: subtitle,
            padding: const EdgeInsets.only(bottom: Insets.sm),
          ),
          AppCard(accentColor: danger ? colors.danger : null, child: child),
        ],
      ),
    );
  }
}

class _AccountTile extends ConsumerWidget {
  const _AccountTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user =
        ref.watch(authStateProvider).value ??
        ref.watch(authRepositoryProvider).currentUser;
    final name = user?.displayName?.trim();
    final email = user?.email ?? '';
    final label = (name != null && name.isNotEmpty) ? name : email;
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colors.hover,
            shape: BoxShape.circle,
            border: Border.all(color: colors.hairline),
          ),
          child: Text(
            label.isEmpty ? '?' : label.characters.first.toUpperCase(),
            style: theme.textTheme.titleSmall,
          ),
        ),
        Gaps.w12,
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.isEmpty ? 'Signed in' : label,
                style: theme.textTheme.titleSmall,
                overflow: TextOverflow.ellipsis,
              ),
              if (email.isNotEmpty && email != label)
                Text(
                  email,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.mutedText,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
        Gaps.w12,
        OutlinedButton.icon(
          key: const Key('settings-sign-out'),
          onPressed: () => confirmAndSignOut(context, ref),
          icon: const Icon(Icons.logout, size: 18),
          label: const Text('Sign out'),
        ),
      ],
    );
  }
}

class _ThemePicker extends ConsumerWidget {
  const _ThemePicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return Wrap(
      spacing: Insets.lg,
      runSpacing: Insets.sm,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('Theme', style: Theme.of(context).textTheme.titleSmall),
        SegmentedButton<ThemeMode>(
          key: const Key('settings-theme'),
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(
              value: ThemeMode.light,
              icon: Icon(Icons.light_mode_outlined, size: 18),
              label: Text('Light'),
            ),
            ButtonSegment(
              value: ThemeMode.dark,
              icon: Icon(Icons.dark_mode_outlined, size: 18),
              label: Text('Dark'),
            ),
            ButtonSegment(
              value: ThemeMode.system,
              icon: Icon(Icons.brightness_auto_outlined, size: 18),
              label: Text('System'),
            ),
          ],
          selected: {mode},
          onSelectionChanged: (s) =>
              ref.read(themeModeProvider.notifier).set(s.first),
        ),
      ],
    );
  }
}

class _SyncTile extends ConsumerWidget {
  const _SyncTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncStatusProvider);
    final value = status.value;
    final syncing = value?.state == SyncState.syncing;
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value == null
                        ? (status.hasError ? 'Sync unavailable' : 'Starting…')
                        : describeSyncStatus(value),
                    style: theme.textTheme.titleSmall,
                  ),
                  Gaps.h2,
                  Text(
                    'Subjects, notes, quizzes and files are stored on this '
                    'device and synced to your account when online.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.mutedText,
                    ),
                  ),
                ],
              ),
            ),
            Gaps.w12,
            FilledButton.tonalIcon(
              key: const Key('settings-sync'),
              onPressed: value == null || syncing
                  ? null
                  : () => ref.read(syncEngineProvider).sync().ignore(),
              icon: syncing
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync, size: 18),
              label: const Text('Sync now'),
            ),
          ],
        ),
        if (value?.error != null) ...[
          Gaps.h12,
          InfoBanner(kind: InfoBannerKind.error, message: value!.error!),
        ],
      ],
    );
  }
}

class _DangerZone extends ConsumerWidget {
  const _DangerZone();

  Future<void> _clearAll(BuildContext context, WidgetRef ref) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Remove all saved keys?',
      message:
          'All API keys and AI settings saved for your account on this '
          'device are deleted. Keys of other accounts are not affected.',
      confirmLabel: 'Remove all',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;
    try {
      await ref.read(apiKeyStoreProvider).clearForUser(userId);
      ref.read(aiSettingsResetProvider.notifier).bump();
      ref.invalidate(aiReadinessProvider);
      if (context.mounted) showAppSnackBar(context, 'All saved keys removed');
    } catch (e) {
      if (context.mounted) showErrorSnackBar(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Remove saved AI keys', style: theme.textTheme.titleSmall),
              Gaps.h2,
              Text(
                'Deletes every API key and AI setting of your account from '
                'this device.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.mutedText,
                ),
              ),
            ],
          ),
        ),
        Gaps.w12,
        OutlinedButton.icon(
          key: const Key('ai-clear-all'),
          onPressed: () => _clearAll(context, ref),
          style: OutlinedButton.styleFrom(
            foregroundColor: colors.danger,
            side: BorderSide(color: colors.danger.withValues(alpha: 0.5)),
          ),
          icon: const Icon(Icons.delete_sweep_outlined, size: 18),
          label: const Text('Remove keys'),
        ),
      ],
    );
  }
}
