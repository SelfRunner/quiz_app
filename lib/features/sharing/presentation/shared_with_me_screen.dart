import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/router/routes.dart';
import '../../../data/data_providers.dart';
import '../../../data/models/models.dart';
import '../../../data/sync/sync_engine.dart';
import '../sharing_ui.dart';
import '../widgets/shared_by_chip.dart';

/// Last successfully loaded shared-with-me list (per user, in memory), shown
/// while offline or while a refresh is in flight.
final _lastSharedWithMeProvider =
    NotifierProvider<_LastSharedWithMe, ({String userId, List<Share> shares})?>(
      _LastSharedWithMe.new,
    );

class _LastSharedWithMe
    extends Notifier<({String userId, List<Share> shares})?> {
  @override
  ({String userId, List<Share> shares})? build() => null;

  void remember(String userId, List<Share> shares) =>
      state = (userId: userId, shares: shares);
}

/// "Shared with me": subjects, notes and quizzes other users shared with the
/// current user, grouped by type. Tapping opens the normal detail routes
/// (which render read-only for items the user doesn't own).
class SharedWithMeScreen extends ConsumerStatefulWidget {
  const SharedWithMeScreen({super.key});

  @override
  ConsumerState<SharedWithMeScreen> createState() => _SharedWithMeScreenState();
}

class _SharedWithMeScreenState extends ConsumerState<SharedWithMeScreen> {
  final _refreshKey = GlobalKey<RefreshIndicatorState>();
  bool _refreshing = false;

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      try {
        await ref.read(syncEngineProvider).sync();
      } catch (_) {
        // sync() reports problems through its status; never fatal here.
      }
      if (!mounted) return;
      ref
        ..invalidate(sharedWithMeProvider)
        ..invalidate(sharedOwnerNamesProvider);
      try {
        await ref
            .read(sharedWithMeProvider.future)
            .timeout(const Duration(seconds: 20));
      } catch (_) {
        // Shown by the error state / offline banner.
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userId = ref.watch(currentUserIdProvider);
    final async = ref.watch(sharedWithMeProvider);
    ref.listen(sharedWithMeProvider, (_, next) {
      final value = next.value;
      if (next.hasValue && value != null && userId != null) {
        ref.read(_lastSharedWithMeProvider.notifier).remember(userId, value);
      }
    });
    final cached = ref.watch(_lastSharedWithMeProvider);
    final syncState = ref.watch(syncStatusProvider).value?.state;

    final fresh = async.hasValue && !async.hasError ? async.value : null;
    final shares =
        fresh ??
        async.value ??
        (cached != null && cached.userId == userId ? cached.shares : null);
    final error = async.error;
    final offline = syncState == SyncState.offline || error is NetworkException;
    final stale = shares != null && fresh == null && (offline || error != null);

    final Widget body;
    if (shares == null) {
      if (error != null && !async.isLoading) {
        body = _MessageView(
          icon: offline ? Icons.cloud_off_outlined : Icons.error_outline,
          title: offline ? "You're offline" : "Couldn't load shared items",
          message: offline
              ? 'Connect to the internet to see what others have shared '
                    'with you.'
              : friendlyError(error),
          action: FilledButton.tonalIcon(
            onPressed: () => _refreshKey.currentState?.show(),
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
        );
      } else if (error != null) {
        // Retrying in the background after an error.
        body = _MessageView(
          icon: offline ? Icons.cloud_off_outlined : Icons.hourglass_empty,
          title: offline ? "You're offline" : 'Still trying…',
          message: offline
              ? "We'll load shared items as soon as you're back online."
              : friendlyError(error),
          action: const SizedBox.square(
            dimension: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      } else {
        body = const _LoadingView();
      }
    } else if (shares.isEmpty) {
      body = _EmptyView(offline: offline);
    } else {
      body = _SharedList(shares: shares, showStaleBanner: stale || offline);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Shared with me'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refreshing
                ? null
                : () => _refreshKey.currentState?.show(),
            icon: _refreshing
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        key: _refreshKey,
        onRefresh: _refresh,
        child: body,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// List
// ---------------------------------------------------------------------------

class _SharedList extends StatelessWidget {
  const _SharedList({required this.shares, required this.showStaleBanner});

  final List<Share> shares;
  final bool showStaleBanner;

  @override
  Widget build(BuildContext context) {
    final groups = <ShareResourceType, List<Share>>{
      for (final t in ShareResourceType.values)
        t: [
          for (final s in shares)
            if (s.resourceType == t) s,
        ]..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        const maxWidth = 1040.0;
        final width = constraints.maxWidth.clamp(0.0, maxWidth);
        final hPad = constraints.maxWidth >= kSharingWideBreakpoint
            ? 24.0
            : 16.0;
        final inner = width - hPad * 2;
        final columns = inner >= 760 ? 2 : 1;
        const gap = 12.0;
        final itemWidth = (inner - gap * (columns - 1)) / columns;

        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.symmetric(
            horizontal: hPad + (constraints.maxWidth - width) / 2,
            vertical: 16,
          ),
          children: [
            if (showStaleBanner) ...[
              const _StaleBanner(),
              const SizedBox(height: 16),
            ],
            for (final entry in groups.entries)
              if (entry.value.isNotEmpty) ...[
                _SectionHeader(type: entry.key, count: entry.value.length),
                const SizedBox(height: 8),
                Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final share in entry.value)
                      SizedBox(
                        width: itemWidth,
                        child: SharedItemCard(share: share),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
              ],
          ],
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.type, required this.count});

  final ShareResourceType type;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      header: true,
      child: Row(
        children: [
          Icon(type.icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text(type.pluralTitle, style: theme.textTheme.titleMedium),
          const SizedBox(width: 8),
          Badge.count(
            count: count,
            backgroundColor: theme.colorScheme.secondaryContainer,
            textColor: theme.colorScheme.onSecondaryContainer,
          ),
        ],
      ),
    );
  }
}

/// One shared resource: title, owner, shared date and content counts.
@visibleForTesting
class SharedItemCard extends ConsumerWidget {
  const SharedItemCard({super.key, required this.share});

  final Share share;

  String get _route => switch (share.resourceType) {
    ShareResourceType.subject => AppRoutes.subject(share.resourceId),
    ShareResourceType.note => AppRoutes.note(share.resourceId),
    ShareResourceType.quiz => AppRoutes.quiz(share.resourceId),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final owner = profileLabel(share.owner, fallback: 'Someone');
    final title = share.resourceTitle?.trim().isNotEmpty == true
        ? share.resourceTitle!.trim()
        : 'Untitled ${share.resourceType.noun}';

    Color? accent;
    if (share.resourceType == ShareResourceType.subject) {
      final color = ref.watch(subjectProvider(share.resourceId)).value?.color;
      if (color != null) accent = Color(color);
    }

    return Card.outlined(
      key: ValueKey('shared-${share.id}'),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => unawaited(context.push(_route)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color:
                      accent?.withValues(alpha: 0.18) ??
                      scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  share.resourceType.icon,
                  color: accent ?? scheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        InitialsAvatar(label: owner, radius: 10),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Shared by $owner',
                            style: theme.textTheme.bodyMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    _DetailsLine(share: share),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Oct 2, 2026 · 4 notes · 2 quizzes" using locally synced rows.
class _DetailsLine extends ConsumerWidget {
  const _DetailsLine({required this.share});

  final Share share;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = share.resourceId;
    final parts = <String>[formatShareDate(share.createdAt)];
    switch (share.resourceType) {
      case ShareResourceType.subject:
        final notes = ref.watch(notesBySubjectProvider(id)).value;
        final quizzes = ref.watch(quizzesBySubjectProvider(id)).value;
        if (notes != null) parts.add(_count(notes.length, 'note'));
        if (quizzes != null) parts.add(_count(quizzes.length, 'quiz'));
      case ShareResourceType.note:
        final quizzes = ref.watch(quizzesByNoteProvider(id)).value;
        if (quizzes != null && quizzes.isNotEmpty) {
          parts.add(_count(quizzes.length, 'quiz'));
        }
      case ShareResourceType.quiz:
        final quiz = ref.watch(quizProvider(id)).value;
        if (quiz != null) parts.add(_count(quiz.questions.length, 'question'));
    }
    return Text(
      parts.join(' · '),
      style: Theme.of(context).textTheme.bodySmall
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    );
  }

  static String _count(int n, String noun) {
    final plural = noun == 'quiz' ? 'quizzes' : '${noun}s';
    return '$n ${n == 1 ? noun : plural}';
  }
}

class _StaleBanner extends StatelessWidget {
  const _StaleBanner();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      key: const ValueKey('shared-offline-banner'),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(Icons.cloud_off_outlined, color: scheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                "You're offline. Shared items may be out of date.",
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty / loading / error states (scrollable so pull-to-refresh works)
// ---------------------------------------------------------------------------

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    children: const [
      SizedBox(height: 160),
      Center(child: CircularProgressIndicator()),
    ],
  );
}

class _EmptyView extends ConsumerWidget {
  const _EmptyView({required this.offline});

  final bool offline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final email = ref.watch(authStateProvider).value?.email;
    return _MessageView(
      icon: Icons.people_outline,
      title: 'Nothing shared with you yet',
      message:
          'When someone shares a subject, note or quiz with '
          '${email ?? 'your email address'}, it shows up here.\n\n'
          'Shared items are view-only: you can read notes and take quizzes, '
          'and a shared subject includes everything its owner adds later. '
          'Use “Copy to my account” on any shared item to get your own '
          'editable copy.',
      footer: offline
          ? const Padding(
              padding: EdgeInsets.only(top: 24),
              child: _StaleBanner(),
            )
          : null,
    );
  }
}

class _MessageView extends StatelessWidget {
  const _MessageView({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    this.footer,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 64, color: theme.colorScheme.primary),
                    const SizedBox(height: 16),
                    Text(
                      title,
                      style: theme.textTheme.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      message,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (action != null) ...[
                      const SizedBox(height: 24),
                      action!,
                    ],
                    ?footer,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
