import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/widgets/design_system.dart';
import '../../../core/widgets/error_message.dart';
import '../../../search/search_models.dart';
import '../../../search/search_providers.dart';
import '../application/recent_searches.dart';
import '../application/search_logic.dart';
import 'search_keys.dart';
import 'search_result_tile.dart';

/// The shortcut that opens [showQuickSearch] on [platform] (Cmd+K on
/// Apple platforms, Ctrl+K elsewhere; both work everywhere).
SingleActivator quickSearchActivatorFor(TargetPlatform platform) =>
    platform == TargetPlatform.macOS || platform == TargetPlatform.iOS
    ? const SingleActivator(LogicalKeyboardKey.keyK, meta: true)
    : const SingleActivator(LogicalKeyboardKey.keyK, control: true);

/// Whether [event] is Ctrl+K (or Cmd+K on Apple keyboards).
bool isQuickSearchShortcut(KeyEvent event) {
  if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.keyK) {
    return false;
  }
  final kb = HardwareKeyboard.instance;
  return (kb.isControlPressed || kb.isMetaPressed) &&
      !kb.isAltPressed &&
      !kb.isShiftPressed;
}

/// Command-palette style search over everything (Ctrl/Cmd+K): instant
/// grouped results, ↑ / ↓ / Enter, Esc closes, "Show all results"
/// (or Ctrl/Cmd+Enter) expands to the full [SearchScreen]. Does nothing
/// when a palette is already open.
Future<void> showQuickSearch(
  BuildContext context, {
  String initialQuery = '',
}) async {
  if (QuickSearchDialog.isOpen) return;
  QuickSearchDialog.isOpen = true;
  try {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.2),
      builder: (_) => QuickSearchDialog(initialQuery: initialQuery),
    );
  } finally {
    QuickSearchDialog.isOpen = false;
  }
}

sealed class _Entry {
  const _Entry();
}

final class _ResultEntry extends _Entry {
  const _ResultEntry(this.result);
  final SearchResult result;
}

final class _RecentEntry extends _Entry {
  const _RecentEntry(this.query);
  final String query;
}

final class _ShowAllEntry extends _Entry {
  const _ShowAllEntry();
}

class QuickSearchDialog extends ConsumerStatefulWidget {
  const QuickSearchDialog({super.key, this.initialQuery = ''});

  final String initialQuery;

  /// A palette is currently shown.
  static bool isOpen = false;

  /// Results shown per type.
  static const int perGroup = 3;

  static const Key fieldKey = Key('quick-search-field');
  static const Key showAllKey = Key('quick-search-show-all');

  @override
  ConsumerState<QuickSearchDialog> createState() => _QuickSearchDialogState();
}

class _QuickSearchDialogState extends ConsumerState<QuickSearchDialog> {
  late final _controller = TextEditingController(text: widget.initialQuery);
  final _focus = FocusNode();
  int _selected = 0;
  bool _closing = false;
  List<_Entry> _entries = const [];

  @override
  void initState() {
    super.initState();
    QuickSearchDialog.isOpen = true;
  }

  @override
  void dispose() {
    // Also when the route is removed without a pop.
    QuickSearchDialog.isOpen = false;
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _close(String? route) {
    if (_closing) return;
    _closing = true;
    final router = GoRouter.maybeOf(context);
    Navigator.of(context).pop();
    if (route != null) router?.push(route);
  }

  void _openResult(SearchResult r) {
    ref.read(recentSearchesProvider.notifier).add(_controller.text);
    _close(searchResultRoute(r));
  }

  void _showAll() {
    final q = _controller.text.trim();
    if (q.isNotEmpty) ref.read(recentSearchesProvider.notifier).add(q);
    _close(AppRoutes.searchFor(q));
  }

  void _useRecent(String q) {
    _controller.value = TextEditingValue(
      text: q,
      selection: TextSelection.collapsed(offset: q.length),
    );
    setState(() => _selected = 0);
    _focus.requestFocus();
  }

  void _activate(int index) {
    if (index < 0 || index >= _entries.length) return;
    switch (_entries[index]) {
      case _ResultEntry(:final result):
        _openResult(result);
      case _RecentEntry(:final query):
        _useRecent(query);
      case _ShowAllEntry():
        _showAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final input = parseSearchInput(_controller.text);
    final hasQuery = input.text.isNotEmpty || input.tags.isNotEmpty;
    final recents = ref.watch(recentSearchesProvider);

    AsyncValue<List<SearchResult>>? results;
    List<SearchGroup> groups = const [];
    if (hasQuery) {
      final found = ref.watch(
        searchProvider((
          query: input.text,
          filters: SearchFilters(tags: input.tags),
        )),
      );
      results = found;
      groups = groupSearchResults(
        found.value ?? const [],
        perGroup: QuickSearchDialog.perGroup,
      );
    }
    _entries = hasQuery
        ? [
            for (final r in flattenGroups(groups)) _ResultEntry(r),
            const _ShowAllEntry(),
          ]
        : [for (final q in recents) _RecentEntry(q)];
    if (_selected >= _entries.length) _selected = 0;

    final children = <Widget>[];
    var index = 0;
    if (!hasQuery) {
      if (recents.isEmpty) {
        children.add(
          Padding(
            padding: const EdgeInsets.all(Insets.xl),
            child: Text(
              'Search subjects, notes, quizzes, decks, files and chats.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.mutedText,
              ),
            ),
          ),
        );
      } else {
        children.add(
          _GroupLabel(
            'Recent',
            trailing: TextButton(
              onPressed: () =>
                  ref.read(recentSearchesProvider.notifier).clear(),
              child: const Text('Clear'),
            ),
          ),
        );
        for (final q in recents) {
          final i = index++;
          children.add(
            ListRowTile(
              key: ValueKey('quick-recent-$q'),
              dense: true,
              selected: i == _selected,
              leading: const Icon(Icons.history),
              title: Text(q),
              onTap: () => _useRecent(q),
            ),
          );
        }
      }
    } else if (results case AsyncValue(isLoading: true, hasValue: false)) {
      children.add(const LinearProgressIndicator(minHeight: 2));
    } else if (results case AsyncValue(:final error?)) {
      children.add(
        Padding(
          padding: const EdgeInsets.all(Insets.lg),
          child: Text('Search is unavailable: ${errorMessage(error)}'),
        ),
      );
    } else if (groups.isEmpty) {
      children.add(
        Padding(
          padding: const EdgeInsets.all(Insets.xl),
          child: Text(
            'No results for "${_controller.text.trim()}"',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.mutedText,
            ),
          ),
        ),
      );
    } else {
      for (final g in groups) {
        children.add(_GroupLabel(searchTypeLabel(g.type), count: g.total));
        for (final r in g.results) {
          final i = index++;
          children.add(
            SearchResultTile(
              result: r,
              dense: true,
              selected: i == _selected,
              onTap: () => _openResult(r),
            ),
          );
        }
      }
    }
    Widget? showAll;
    if (hasQuery) {
      final i = index++;
      showAll = ListRowTile(
        key: QuickSearchDialog.showAllKey,
        dense: true,
        selected: i == _selected,
        leading: const Icon(Icons.open_in_full),
        title: Text(
          input.text.isEmpty
              ? 'Open full search'
              : 'Show all results for "${input.text}"',
        ),
        trailing: const KeyboardShortcutHint.activator(
          SingleActivator(LogicalKeyboardKey.enter, control: true),
        ),
        onTap: _showAll,
      );
    }

    return Dialog(
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.fromLTRB(
        Insets.lg,
        Insets.xxxl + Insets.xl,
        Insets.lg,
        Insets.xl,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Focus(
              onKeyEvent: (node, event) {
                if (isModifiedEnter(event)) {
                  _showAll();
                  return KeyEventResult.handled;
                }
                return handleSearchNavKey(
                  event,
                  count: _entries.length,
                  selected: _selected,
                  onSelect: (i) => setState(() => _selected = i),
                );
              },
              child: TextField(
                key: QuickSearchDialog.fieldKey,
                controller: _controller,
                focusNode: _focus,
                autofocus: true,
                textInputAction: TextInputAction.search,
                style: theme.textTheme.titleMedium,
                decoration: InputDecoration(
                  hintText: 'Search everything…',
                  prefixIcon: const Icon(Icons.search),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: Insets.lg,
                  ),
                  suffixIcon: _controller.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear',
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () {
                            _controller.clear();
                            setState(() => _selected = 0);
                            _focus.requestFocus();
                          },
                        ),
                ),
                onChanged: (_) => setState(() => _selected = 0),
                onEditingComplete: () {},
                onSubmitted: (_) => _activate(_selected),
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.all(Insets.sm),
                children: children,
              ),
            ),
            if (showAll != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Insets.sm,
                  0,
                  Insets.sm,
                  Insets.sm,
                ),
                child: showAll,
              ),
            const Divider(height: 1),
            const Padding(
              padding: EdgeInsets.symmetric(
                horizontal: Insets.md,
                vertical: Insets.sm,
              ),
              child: Wrap(
                spacing: Insets.lg,
                runSpacing: Insets.xs,
                children: [
                  KeyboardShortcutHint(keys: ['↑', '↓'], label: 'Navigate'),
                  KeyboardShortcutHint(keys: ['Enter'], label: 'Open'),
                  KeyboardShortcutHint(keys: ['Esc'], label: 'Close'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.label, {this.count, this.trailing});

  final String label;
  final int? count;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final style = Theme.of(context).textTheme.labelMedium
        ?.copyWith(color: colors.mutedText);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Insets.md,
        Insets.sm,
        Insets.xs,
        Insets.xxs,
      ),
      child: Row(
        children: [
          Text(label, style: style),
          if (count != null) ...[
            Gaps.w8,
            Text('$count', style: style?.copyWith(color: colors.faintText)),
          ],
          const Spacer(),
          ?trailing,
        ],
      ),
    );
  }
}
