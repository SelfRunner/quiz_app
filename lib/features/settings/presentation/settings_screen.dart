import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/sync_status_indicator.dart';
import '../../../data/data_providers.dart';
import '../../../data/sync/sync_engine.dart';
import '../../auth/application/sign_out.dart';
import 'widgets/ai_settings_section.dart';

/// Account, appearance, sync and AI provider settings.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: const [
          MaxWidth(
            maxWidth: 760,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Section(
                  icon: Icons.person_outline,
                  title: 'Account',
                  child: _AccountTile(),
                ),
                _Section(
                  icon: Icons.auto_awesome_outlined,
                  title: 'AI provider',
                  child: AiSettingsSection(),
                ),
                _Section(
                  icon: Icons.palette_outlined,
                  title: 'Appearance',
                  child: _ThemePicker(),
                ),
                _Section(icon: Icons.sync, title: 'Sync', child: _SyncTile()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(icon, color: theme.colorScheme.primary),
                  const SizedBox(width: 12),
                  Text(title, style: theme.textTheme.titleMedium),
                ],
              ),
              const SizedBox(height: 16),
              child,
            ],
          ),
        ),
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
    return Wrap(
      spacing: 16,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.spaceBetween,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Text(
                label.isEmpty ? '?' : label.characters.first.toUpperCase(),
                style: TextStyle(
                  color: theme.colorScheme.onPrimaryContainer,
                  fontSize: 20,
                ),
              ),
            ),
            const SizedBox(width: 16),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label.isEmpty ? 'Signed in' : label,
                    style: theme.textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (email.isNotEmpty && email != label)
                    Text(
                      email,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
        OutlinedButton.icon(
          key: const Key('settings-sign-out'),
          onPressed: () => confirmAndSignOut(context, ref),
          icon: const Icon(Icons.logout),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Theme'),
        const SizedBox(height: 8),
        SegmentedButton<ThemeMode>(
          key: const Key('settings-theme'),
          segments: const [
            ButtonSegment(
              value: ThemeMode.light,
              icon: Icon(Icons.light_mode_outlined),
              label: Text('Light'),
            ),
            ButtonSegment(
              value: ThemeMode.dark,
              icon: Icon(Icons.dark_mode_outlined),
              label: Text('Dark'),
            ),
            ButtonSegment(
              value: ThemeMode.system,
              icon: Icon(Icons.brightness_auto_outlined),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Your subjects, notes and quizzes are stored on this device and '
          'synced to your account automatically when online.',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              value == null
                  ? (status.hasError ? 'Sync unavailable' : 'Starting…')
                  : describeSyncStatus(value),
              style: theme.textTheme.titleSmall,
            ),
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
                  : const Icon(Icons.sync),
              label: const Text('Sync now'),
            ),
          ],
        ),
        if (value?.error != null) ...[
          const SizedBox(height: 12),
          Text(value!.error!, style: TextStyle(color: theme.colorScheme.error)),
        ],
      ],
    );
  }
}
