import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'routes.dart';

/// Top-level navigation (Subjects / Shared / Settings). Bottom bar on narrow
/// screens, rail on wide screens.
class AppShell extends StatelessWidget {
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

  int get _index {
    for (var i = _tabs.length - 1; i > 0; i--) {
      if (location.startsWith(_tabs[i].$1)) return i;
    }
    return 0;
  }

  void _go(BuildContext context, int i) => context.go(_tabs[i].$1);

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 720;
    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: (i) => _go(context, i),
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (final t in _tabs)
                  NavigationRailDestination(
                    icon: Icon(t.$2),
                    selectedIcon: Icon(t.$3),
                    label: Text(t.$4),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: child),
          ],
        ),
      );
    }
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => _go(context, i),
        destinations: [
          for (final t in _tabs)
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
