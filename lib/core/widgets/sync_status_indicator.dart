import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/data_providers.dart';
import '../../data/sync/sync_engine.dart';

/// Human summary of a [SyncStatus].
String describeSyncStatus(SyncStatus status, {DateTime? now}) {
  final pending = status.pendingOps;
  final pendingText = pending == 0
      ? ''
      : ' · $pending change${pending == 1 ? '' : 's'} waiting';
  return switch (status.state) {
    SyncState.syncing => 'Syncing…',
    SyncState.offline => 'Offline$pendingText',
    SyncState.error => 'Sync problem$pendingText',
    SyncState.idle when pending > 0 => 'Changes waiting to sync ($pending)',
    SyncState.idle =>
      status.lastSyncedAt == null
          ? 'Not synced yet'
          : 'Synced ${formatRelativeTime(status.lastSyncedAt!, now: now)}',
  };
}

/// "just now", "5 min ago", "today 14:03", "Mar 3, 14:03".
String formatRelativeTime(DateTime time, {DateTime? now}) {
  final current = (now ?? DateTime.now()).toUtc();
  final diff = current.difference(time.toUtc());
  if (diff.inSeconds < 45) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  final local = time.toLocal();
  final today = current.toLocal();
  if (local.year == today.year &&
      local.month == today.month &&
      local.day == today.day) {
    return 'today ${DateFormat.Hm().format(local)}';
  }
  return DateFormat.MMMd().add_Hm().format(local);
}

/// Opens a dialog with sync details and a "Sync now" button.
Future<void> showSyncDetailsDialog(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) => const _SyncDetailsDialog(),
);

/// Icon button reflecting the sync state. Tap: sync now (or show details
/// when there is a problem). Hidden if the sync engine is unavailable.
class SyncStatusButton extends ConsumerWidget {
  const SyncStatusButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncStatusProvider).value;
    if (status == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final Widget icon = switch (status.state) {
      SyncState.syncing => const SizedBox.square(
        dimension: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      SyncState.offline => const Icon(Icons.cloud_off_outlined),
      SyncState.error => Icon(Icons.sync_problem, color: scheme.error),
      SyncState.idle when status.pendingOps > 0 => const Icon(
        Icons.cloud_upload_outlined,
      ),
      SyncState.idle => const Icon(Icons.cloud_done_outlined),
    };
    return IconButton(
      tooltip: '${describeSyncStatus(status)}\nTap for details',
      icon: Badge(
        isLabelVisible: status.pendingOps > 0,
        label: Text('${status.pendingOps}'),
        child: icon,
      ),
      onPressed: () => showSyncDetailsDialog(context),
    );
  }
}

/// Thin strip shown at the top of the shell on narrow screens when offline
/// or when sync has a problem.
class SyncStatusBanner extends ConsumerWidget {
  const SyncStatusBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncStatusProvider).value;
    if (status == null ||
        (status.state != SyncState.offline &&
            status.state != SyncState.error)) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    final isError = status.state == SyncState.error;
    final bg = isError ? scheme.errorContainer : scheme.secondaryContainer;
    final fg = isError ? scheme.onErrorContainer : scheme.onSecondaryContainer;
    return Material(
      color: bg,
      child: SafeArea(
        bottom: false,
        child: InkWell(
          onTap: () => showSyncDetailsDialog(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                Icon(
                  isError ? Icons.sync_problem : Icons.cloud_off_outlined,
                  size: 18,
                  color: fg,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isError
                        ? describeSyncStatus(status)
                        : '${describeSyncStatus(status)} · changes are saved on '
                              'this device',
                    style: TextStyle(color: fg),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  'Details',
                  style: TextStyle(color: fg, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SyncDetailsDialog extends ConsumerWidget {
  const _SyncDetailsDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncStatusProvider).value ?? const SyncStatus();
    final theme = Theme.of(context);
    final syncing = status.state == SyncState.syncing;
    return AlertDialog(
      icon: const Icon(Icons.sync),
      title: const Text('Sync'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              describeSyncStatus(status),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (status.lastSyncedAt != null)
              Text('Last synced ${formatRelativeTime(status.lastSyncedAt!)}'),
            Text('Changes waiting: ${status.pendingOps}'),
            if (status.state == SyncState.offline) ...[
              const SizedBox(height: 8),
              const Text(
                'You can keep working offline. Changes sync automatically '
                'when you are back online.',
              ),
            ],
            if (status.error != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  status.error!,
                  style: TextStyle(color: theme.colorScheme.onErrorContainer),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        FilledButton.icon(
          onPressed: syncing
              ? null
              : () => ref.read(syncEngineProvider).sync().ignore(),
          icon: const Icon(Icons.sync),
          label: Text(syncing ? 'Syncing…' : 'Sync now'),
        ),
      ],
    );
  }
}
