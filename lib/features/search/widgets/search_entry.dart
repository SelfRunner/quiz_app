import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/widgets/design_system.dart';
import 'quick_search.dart';

/// Opens search: the full [SearchScreen] on phones, the quick-search
/// palette on wider screens.
void openSearch(BuildContext context) {
  if (Breakpoints.isMedium(context)) {
    showQuickSearch(context);
  } else {
    GoRouter.maybeOf(context)?.push(AppRoutes.search);
  }
}

/// App-bar search action for phone layouts (the sidebar has its own entry
/// from 720px, so this renders nothing there unless [always]).
class SearchIconButton extends StatelessWidget {
  const SearchIconButton({super.key, this.always = false});

  final bool always;

  static const Key buttonKey = Key('app-bar-search');

  @override
  Widget build(BuildContext context) {
    if (!always && Breakpoints.isMedium(context)) {
      return const SizedBox.shrink();
    }
    return IconButton(
      key: buttonKey,
      tooltip: 'Search',
      icon: const Icon(Icons.search),
      onPressed: () => GoRouter.maybeOf(context)?.push(AppRoutes.search),
    );
  }
}

/// Sidebar search entry: a "Search  Ctrl K" row when [extended], else an
/// icon button. Opens the quick-search palette.
class SidebarSearchButton extends StatelessWidget {
  const SidebarSearchButton({super.key, required this.extended});

  final bool extended;

  static const Key buttonKey = Key('sidebar-search');

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    if (!extended) {
      return IconButton(
        key: buttonKey,
        tooltip: 'Search (Ctrl+K)',
        icon: Icon(Icons.search, color: colors.mutedText),
        onPressed: () => showQuickSearch(context),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Insets.md),
      child: Material(
        color: colors.card,
        shape: RoundedRectangleBorder(
          borderRadius: Radii.mdAll,
          side: BorderSide(color: colors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: buttonKey,
          onTap: () => showQuickSearch(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Insets.md,
              vertical: Insets.sm,
            ),
            child: Row(
              children: [
                Icon(Icons.search, size: 18, color: colors.mutedText),
                Gaps.w8,
                Expanded(
                  child: Text(
                    'Search',
                    style: Theme.of(context).textTheme.labelLarge
                        ?.copyWith(color: colors.mutedText),
                  ),
                ),
                KeyboardShortcutHint.activator(
                  quickSearchActivatorFor(Theme.of(context).platform),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
