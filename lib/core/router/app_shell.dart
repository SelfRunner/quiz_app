import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/data_providers.dart';
import '../../data/sync/default_sync_engine.dart';
import '../../data/sync/sync_engine.dart';
import '../../features/auth/application/sign_out.dart';
import '../../features/search/presentation/search_screen.dart';
import '../../features/search/widgets/quick_search.dart';
import '../../features/search/widgets/search_entry.dart';
import '../theme/app_colors.dart';
import '../theme/tokens.dart';
import '../widgets/error_message.dart';
import '../widgets/responsive.dart';
import '../widgets/sync_status_indicator.dart';
import 'routes.dart';

/// Top-level navigation (Home / Subjects / Study / Shared / Settings; Study
/// shows a badge with today's due cards). Bottom bar on narrow
/// screens; on wide screens a sidebar-style rail (app mark, destinations,
/// sync status and sign-out at the bottom) that extends with labels from the
/// expanded breakpoint. Search: a sidebar entry and Ctrl/Cmd+K (anywhere
/// while the shell is mounted, also over pushed routes) open the
/// quick-search palette; phone app bars use `SearchIconButton`. Also
/// surfaces sync problems: an offline/error strip on narrow screens and a
/// snackbar when the server rejects a change.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.child, required this.location});

  final Widget child;
  final String location;

  static const String appName = 'Quiz & Notes';

  static const _tabs = [
    (AppRoutes.home, Icons.home_outlined, Icons.home, 'Home'),
    (
      AppRoutes.subjects,
      Icons.library_books_outlined,
      Icons.library_books,
      'Subjects',
    ),
    (AppRoutes.study, Icons.style_outlined, Icons.style, 'Study'),
    (AppRoutes.shared, Icons.people_outline, Icons.people, 'Shared'),
    (AppRoutes.settings, Icons.settings_outlined, Icons.settings, 'Settings'),
  ];

  /// Index of the Study destination (carries the due-count badge).
  static const int _studyIndex = 2;

  /// Key of the due-count badge on the Study destination.
  static const Key studyBadgeKey = Key('nav-study-badge');

  /// Index of the destination for [location] (Subjects for `/` and any
  /// unknown shell location).
  static int indexFor(String location) {
    for (final (i, t) in _tabs.indexed) {
      final path = t.$1;
      if (path == AppRoutes.subjects) continue;
      if (location == path || location.startsWith('$path/')) return i;
    }
    return 1;
  }

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  StreamSubscription<SyncRejection>? _rejections;

  int get _index => AppShell.indexFor(widget.location);

  /// Destination icon, with the due-card badge on Study.
  Widget _icon(int i, IconData icon, int due) {
    final child = Icon(icon);
    if (i != AppShell._studyIndex || due <= 0) return child;
    return Badge(
      key: AppShell.studyBadgeKey,
      label: Text(due > 99 ? '99+' : '$due'),
      child: child,
    );
  }

  @override
  void initState() {
    super.initState();
    _listenToRejections();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  /// Ctrl/Cmd+K: focuses an open search screen, else opens the palette.
  bool _onKey(KeyEvent event) {
    if (!mounted || !isQuickSearchShortcut(event)) return false;
    if (SearchScreen.focusIfCurrent?.call() ?? false) return true;
    if (QuickSearchDialog.isOpen) return true;
    showQuickSearch(context);
    return true;
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
    HardwareKeyboard.instance.removeHandler(_onKey);
    unawaited(_rejections?.cancel());
    super.dispose();
  }

  void _go(int i) => context.go(AppShell._tabs[i].$1);

  @override
  Widget build(BuildContext context) {
    final wide = Breakpoints.isMedium(context);
    final due = ref.watch(dueCountProvider).value ?? 0;
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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _Brand(extended: extended),
                    Gaps.h4,
                    SidebarSearchButton(extended: extended),
                    Gaps.h8,
                  ],
                ),
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
                for (final (i, t) in AppShell._tabs.indexed)
                  NavigationRailDestination(
                    icon: _icon(i, t.$2, due),
                    selectedIcon: _icon(i, t.$3, due),
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
            for (final (i, t) in AppShell._tabs.indexed)
              NavigationDestination(
                icon: _icon(i, t.$2, due),
                selectedIcon: _icon(i, t.$3, due),
                label: t.$4,
                tooltip: i == AppShell._studyIndex && due > 0
                    ? 'Study, $due due'
                    : null,
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
