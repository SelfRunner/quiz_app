import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/data_providers.dart';
import '../../data/sync/default_sync_engine.dart';
import '../../data/sync/sync_engine.dart';
import '../../features/auth/application/sign_out.dart';
import '../theme/app_colors.dart';
import '../theme/tokens.dart';
import '../widgets/error_message.dart';
import '../widgets/responsive.dart';
import '../widgets/sync_status_indicator.dart';
import 'routes.dart';

/// Top-level navigation (Subjects / Shared / Settings). Bottom bar on narrow
/// screens; on wide screens a sidebar-style rail (app mark, destinations,
/// sync status and sign-out at the bottom) that extends with labels from the
/// expanded breakpoint. Also
/// surfaces sync problems: an offline/error strip on narrow screens and a
/// snackbar when the server rejects a change.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.child, required this.location});

  final Widget child;
  final String location;

  static const String appName = 'Quiz & Notes';

  static const _tabs = [
    (
      AppRoutes.subjects,
      Icons.library_books_outlined,
      Icons.library_books,
      'Subjects',
    ),
    (AppRoutes.shared, Icons.people_outline, Icons.people, 'Shared'),
    (AppRoutes.settings, Icons.settings_outlined, Icons.settings, 'Settings'),
  ];

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  StreamSubscription<SyncRejection>? _rejections;

  int get _index {
    for (var i = AppShell._tabs.length - 1; i > 0; i--) {
      if (widget.location.startsWith(AppShell._tabs[i].$1)) return i;
    }
    return 0;
  }

  @override
  void initState() {
    super.initState();
    _listenToRejections();
  }

  void _listenToRejections() {
    SyncEngine? engine;
    try {
      engine = ref.read(syncEngineProvider);
    } catch (_) {
      return; // Sync unavailable (e.g. tests without a backend).
    }
    if (engine is DefaultSyncEngine) {
      _rejections = engine.rejections.listen((rejection) {
        if (!mounted) return;
        showAppSnackBar(
          context,
          'A change was not saved by the server: ${rejection.message}',
          isError: true,
        );
      });
    }
  }

  @override
  void dispose() {
    unawaited(_rejections?.cancel());
    super.dispose();
  }

  void _go(int i) => context.go(AppShell._tabs[i].$1);

  @override
  Widget build(BuildContext context) {
    final wide = Breakpoints.isMedium(context);
    if (wide) {
      final extended = Breakpoints.isExpanded(context);
      final railTheme = NavigationRailTheme.of(context);
      final railWidth = extended
          ? (railTheme.minExtendedWidth ?? 232)
          : (railTheme.minWidth ?? 72);
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: _go,
              extended: extended,
              labelType: extended
                  ? NavigationRailLabelType.none
                  : NavigationRailLabelType.all,
              trailingAtBottom: true,
              leading: SizedBox(
                width: railWidth,
                child: _Brand(extended: extended),
              ),
              trailing: SizedBox(
                width: railWidth,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Insets.sm,
                    Insets.sm,
                    Insets.sm,
                    Insets.md,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (extended)
                        const SyncStatusTile()
                      else
                        const SyncStatusButton(),
                      Gaps.h4,
                      _SidebarAction(
                        icon: Icons.logout,
                        label: 'Sign out',
                        extended: extended,
                        onPressed: () => confirmAndSignOut(context, ref),
                      ),
                    ],
                  ),
                ),
              ),
              destinations: [
                for (final t in AppShell._tabs)
                  NavigationRailDestination(
                    icon: Icon(t.$2),
                    selectedIcon: Icon(t.$3),
                    label: Text(t.$4),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: widget.child),
          ],
        ),
      );
    }

    final status = ref.watch(syncStatusProvider).value;
    final showBanner =
        status != null &&
        (status.state == SyncState.offline || status.state == SyncState.error);
    return Scaffold(
      body: Column(
        children: [
          if (showBanner) const SyncStatusBanner(),
          Expanded(
            child: showBanner
                ? MediaQuery.removePadding(
                    context: context,
                    removeTop: true,
                    child: widget.child,
                  )
                : widget.child,
          ),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: AppColors.of(context).hairline),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: _go,
          destinations: [
            for (final t in AppShell._tabs)
              NavigationDestination(
                icon: Icon(t.$2),
                selectedIcon: Icon(t.$3),
                label: t.$4,
              ),
          ],
        ),
      ),
    );
  }
}

/// App mark (+ name when the sidebar is extended).
class _Brand extends StatelessWidget {
  const _Brand({required this.extended});

  final bool extended;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mark = Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurface,
        borderRadius: Radii.smAll,
      ),
      child: Icon(
        Icons.school_outlined,
        size: 17,
        color: theme.colorScheme.surface,
      ),
    );
    if (!extended) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: Insets.sm),
        child: Tooltip(message: AppShell.appName, child: mark),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Insets.lg,
        Insets.sm,
        Insets.lg,
        Insets.sm,
      ),
      child: Row(
        children: [
          mark,
          Gaps.w12,
          Expanded(
            child: Text(
              AppShell.appName,
              style: theme.textTheme.titleSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Sidebar footer action: icon button (collapsed) or icon + label row.
class _SidebarAction extends StatelessWidget {
  const _SidebarAction({
    required this.icon,
    required this.label,
    required this.extended,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool extended;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    if (!extended) {
      return IconButton(
        tooltip: label,
        icon: Icon(icon, size: 20),
        color: colors.mutedText,
        onPressed: onPressed,
      );
    }
    return InkWell(
      borderRadius: Radii.mdAll,
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Insets.md,
          vertical: Insets.sm,
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: colors.mutedText),
            Gaps.w12,
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelMedium
                    ?.copyWith(color: colors.mutedText),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
