import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/data_providers.dart';
import '../../data/sync/default_sync_engine.dart';
import '../../data/sync/sync_engine.dart';
import '../../features/auth/application/sign_out.dart';
import '../widgets/error_message.dart';
import '../widgets/responsive.dart';
import '../widgets/sync_status_indicator.dart';
import 'routes.dart';

/// Top-level navigation (Subjects / Shared / Settings). Bottom bar on narrow
/// screens, rail (with sync indicator and sign-out) on wide screens. Also
/// surfaces sync problems: an offline/error strip on narrow screens and a
/// snackbar when the server rejects a change.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.child, required this.location});

  final Widget child;
  final String location;

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
      final scheme = Theme.of(context).colorScheme;
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: _go,
              labelType: NavigationRailLabelType.all,
              leading: Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 16),
                child: CircleAvatar(
                  backgroundColor: scheme.primaryContainer,
                  child: Icon(Icons.school, color: scheme.onPrimaryContainer),
                ),
              ),
              trailing: Expanded(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SyncStatusButton(),
                        const SizedBox(height: 8),
                        IconButton(
                          tooltip: 'Sign out',
                          icon: const Icon(Icons.logout),
                          onPressed: () => confirmAndSignOut(context, ref),
                        ),
                      ],
                    ),
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
      bottomNavigationBar: NavigationBar(
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
    );
  }
}
