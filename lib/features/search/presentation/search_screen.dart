import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/design_system.dart';
import '../../../core/widgets/tag_widgets.dart';
import '../../../data/data_providers.dart';
import '../../../data/models/models.dart';
import '../../../data/repositories/organization_repository.dart';
import '../../../search/search_models.dart';
import '../../../search/search_providers.dart';
import '../application/recent_searches.dart';
import '../application/search_logic.dart';
import '../widgets/quick_search.dart';
import '../widgets/search_keys.dart';
import '../widgets/search_result_tile.dart';

/// Subjects offered by the subject filter (all, incl. archived / shared).
const SubjectListQuery searchSubjectsQuery = SubjectListQuery(
  archive: ArchiveFilter.all,
  includeShared: true,
);

/// Global search: instant results grouped by type with highlighted
/// matches, filters (type chips, subject, tag), ↑ / ↓ / Enter, recent
/// searches and empty / no-result states. [initialQuery] may contain
/// `tag:x` / `tag:"x y"` tokens, which become tag filters.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, this.initialQuery});

  final String? initialQuery;

  static const Key fieldKey = Key('search-field');

  /// Set while a search screen is mounted: focuses its field when it is the
  /// current route and returns true (the Ctrl/Cmd+K handler uses it instead
  /// of opening the palette on top of the screen).
  static bool Function()? focusIfCurrent;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  final _selectedKey = GlobalKey();
  Set<SearchItemType> _types = {};
  Set<String> _tags = {};
  String? _subjectId;
  int _selected = 0;
  List<SearchResult> _flat = const [];
  late final bool Function() _focusHook = _focusIfCurrent;

  @override
  void initState() {
    super.initState();
    final parsed = parseSearchInput(widget.initialQuery ?? '');
    _controller.text = parsed.text;
    _tags = parsed.tags;
    SearchScreen.focusIfCurrent = _focusHook;
  }

  @override
  void dispose() {
    if (identical(SearchScreen.focusIfCurrent, _focusHook)) {
      SearchScreen.focusIfCurrent = null;
    }
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool _focusIfCurrent() {
    if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? true)) return false;
    _focus.requestFocus();
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
    return true;
  }

  SearchFilters get _filters {
    final typed = parseSearchInput(_controller.text).tags;
    return SearchFilters(
      types: _types,
      subjectId: _subjectId,
      tags: {..._tags, ...typed},
    );
  }

  bool get _hasFilters =>
      _types.isNotEmpty || _subjectId != null || _tags.isNotEmpty;

  void _update(VoidCallback change) => setState(() {
    change();
    _selected = 0;
  });

  void _clearFilters() => _update(() {
    _types = {};
    _tags = {};
    _subjectId = null;
  });

  void _select(int i) {
    setState(() => _selected = i);
    SchedulerBinding.instance.addPostFrameCallback((_) {
      final ctx = _selectedKey.currentContext;
      if (ctx != null && ctx.mounted) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.5,
          duration: Motion.fast,
          alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
        );
      }
    });
  }

  void _open(SearchResult r) {
    final query = [
      for (final t in _tags) tagSearchQuery(t),
      _controller.text.trim(),
    ].where((s) => s.isNotEmpty).join(' ');
    ref.read(recentSearchesProvider.notifier).add(query);
    context.push(searchResultRoute(r));
  }

  void _useRecent(String q) {
    final parsed = parseSearchInput(q);
    _update(() {
      _controller.text = parsed.text;
      _tags = {..._tags, ...parsed.tags};
    });
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final input = parseSearchInput(_controller.text);
    final filters = _filters;
    final active = input.text.isNotEmpty || !filters.isEmpty;
    final results = active
        ? ref.watch(searchProvider((query: input.text, filters: filters)))
        : null;

    final groups = groupSearchResults(results?.value ?? const []);
    _flat = flattenGroups(groups);
    if (_selected >= _flat.length) _selected = 0;

    final field = Focus(
      onKeyEvent: (node, event) => handleSearchNavKey(
        event,
        count: _flat.length,
        selected: _selected,
        onSelect: _select,
      ),
      child: TextField(
        key: SearchScreen.fieldKey,
        controller: _controller,
        focusNode: _focus,
        autofocus: true,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Search notes, quizzes, decks…',
          prefixIcon: const Icon(Icons.search, size: 20),
          isDense: true,
          suffixIcon: _controller.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () {
                    _update(_controller.clear);
                    _focus.requestFocus();
                  },
                ),
        ),
        onChanged: (_) => _update(() {}),
        onEditingComplete: () {},
        onSubmitted: (_) {
          if (_selected < _flat.length) _open(_flat[_selected]);
        },
      ),
    );

    return Scaffold(
      appBar: AppBar(titleSpacing: 0, title: field, actions: const [Gaps.w16]),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ContentContainer(
            maxWidth: ContentWidth.readable,
            child: _FilterBar(
              types: _types,
              tags: _tags,
              subjectId: _subjectId,
              onTypes: (t) => _update(() => _types = t),
              onTags: (t) => _update(() => _tags = t),
              onSubject: (id) => _update(() => _subjectId = id),
              onClear: _hasFilters ? _clearFilters : null,
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _body(context, results, groups, input.text)),
        ],
      ),
    );
  }

  Widget _body(
    BuildContext context,
    AsyncValue<List<SearchResult>>? results,
    List<SearchGroup> groups,
    String text,
  ) {
    if (results == null) return _Idle(onRecent: _useRecent);
    if (results case AsyncValue(:final error?) when !results.hasValue) {
      return ErrorView(error: error);
    }
    if (!results.hasValue) {
      return const ContentContainer(
        child: Padding(
          padding: EdgeInsets.only(top: Insets.lg),
          child: LoadingSkeleton(rows: 4, animate: false),
        ),
      );
    }
    if (groups.isEmpty) {
      return EmptyState(
        icon: Icons.search_off,
        title: 'No results',
        message: text.isEmpty
            ? 'Nothing matches these filters.'
            : 'Nothing matches "$text"${_hasFilters ? ' with these filters' : ''}.',
        action: _hasFilters
            ? TextButton(
                onPressed: _clearFilters,
                child: const Text('Clear filters'),
              )
            : null,
      );
    }
    final children = <Widget>[];
    var index = 0;
    for (final g in groups) {
      children.add(
        SectionHeader(
          key: ValueKey('search-group-${g.type.name}'),
          title: searchTypeLabel(g.type),
          count: g.results.length,
          padding: const EdgeInsets.only(top: Insets.lg, bottom: Insets.xs),
        ),
      );
      for (final r in g.results) {
        final i = index++;
        final selected = i == _selected;
        children.add(
          KeyedSubtree(
            key: selected ? _selectedKey : null,
            child: SearchResultTile(
              result: r,
              selected: selected,
              onTap: () => _open(r),
            ),
          ),
        );
      }
    }
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        ContentContainer(
          padding: EdgeInsets.fromLTRB(
            Breakpoints.gutter(context),
            0,
            Breakpoints.gutter(context),
            Insets.xxxl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ],
    );
  }
}

/// No query and no filters: recent searches and a hint.
class _Idle extends ConsumerWidget {
  const _Idle({required this.onRecent});

  final ValueChanged<String> onRecent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recents = ref.watch(recentSearchesProvider);
    final hint = EmptyState(
      icon: Icons.search,
      title: 'Search everything',
      message:
          'Find subjects, notes, quizzes, decks, files and chats. Use '
          'tag:name to filter by tag.',
      action: Breakpoints.isMedium(context)
          ? KeyboardShortcutHint.activator(
              quickSearchActivatorFor(Theme.of(context).platform),
              label: 'Quick search anywhere',
            )
          : null,
    );
    if (recents.isEmpty) return hint;
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        ContentContainer(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionHeader(
                title: 'Recent searches',
                trailing: TextButton(
                  key: const Key('clear-recent-searches'),
                  onPressed: () =>
                      ref.read(recentSearchesProvider.notifier).clear(),
                  child: const Text('Clear'),
                ),
              ),
              for (final q in recents)
                ListRowTile(
                  key: ValueKey('recent-search-$q'),
                  dense: true,
                  leading: const Icon(Icons.history),
                  title: Text(q),
                  onTap: () => onRecent(q),
                  actions: [
                    IconButton(
                      tooltip: 'Remove',
                      icon: const Icon(Icons.close),
                      onPressed: () =>
                          ref.read(recentSearchesProvider.notifier).remove(q),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Type chips, subject and tag pickers.
class _FilterBar extends ConsumerWidget {
  const _FilterBar({
    required this.types,
    required this.tags,
    required this.subjectId,
    required this.onTypes,
    required this.onTags,
    required this.onSubject,
    required this.onClear,
  });

  final Set<SearchItemType> types;
  final Set<String> tags;
  final String? subjectId;
  final ValueChanged<Set<SearchItemType>> onTypes;
  final ValueChanged<Set<String>> onTags;
  final ValueChanged<String?> onSubject;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppColors.of(context);
    final subjects =
        ref.watch(subjectListProvider(searchSubjectsQuery)).value ??
        const <Subject>[];
    final allTags = [
      for (final t in ref.watch(allTagsProvider).value ?? const <TagCount>[])
        t.tag,
    ];
    final subject = subjects.where((s) => s.id == subjectId).firstOrNull;

    final items = <Widget>[
      for (final t in searchTypeOrder)
        FilterChip(
          key: ValueKey('search-type-${t.name}'),
          label: Text(searchTypeLabel(t)),
          selected: types.contains(t),
          showCheckmark: false,
          visualDensity: VisualDensity.compact,
          onSelected: (on) =>
              onTypes(on ? {...types, t} : ({...types}..remove(t))),
        ),
      Container(width: 1, height: 20, color: colors.hairline),
      PopupMenuButton<String?>(
        key: const Key('search-subject-filter'),
        tooltip: 'Filter by subject',
        onSelected: (id) => onSubject(id == '' ? null : id),
        itemBuilder: (context) => [
          const PopupMenuItem(value: '', child: Text('Any subject')),
          for (final s in subjects)
            PopupMenuItem(
              value: s.id,
              child: Row(
                children: [
                  SubjectColorDot(color: s.color),
                  Gaps.w8,
                  Flexible(
                    child: Text(s.title, overflow: TextOverflow.ellipsis),
                  ),
                  if (s.archivedAt != null) ...[
                    Gaps.w8,
                    Text('Archived', style: TextStyle(color: colors.mutedText)),
                  ],
                ],
              ),
            ),
        ],
        child: _PickerChip(
          icon: Icons.library_books_outlined,
          label: subject?.title ?? 'Subject',
          active: subjectId != null,
        ),
      ),
      PopupMenuButton<String>(
        key: const Key('search-tag-filter'),
        tooltip: 'Filter by tag',
        enabled: allTags.isNotEmpty || tags.isNotEmpty,
        onSelected: (t) =>
            onTags(tags.contains(t) ? ({...tags}..remove(t)) : {...tags, t}),
        itemBuilder: (context) => [
          for (final t in {...tags, ...allTags})
            CheckedPopupMenuItem(
              value: t,
              checked: tags.contains(t),
              child: Text('#$t'),
            ),
        ],
        child: _PickerChip(
          icon: Icons.sell_outlined,
          label: tags.isEmpty ? 'Tag' : tags.map((t) => '#$t').join(' '),
          active: tags.isNotEmpty,
        ),
      ),
      if (onClear != null)
        TextButton(
          key: const Key('search-clear-filters'),
          onPressed: onClear,
          child: const Text('Clear'),
        ),
    ];
    // Wide: wrap; phones: one horizontally scrolling row.
    if (Breakpoints.isMedium(context)) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: Insets.sm),
        child: Wrap(
          spacing: Insets.sm,
          runSpacing: Insets.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: items,
        ),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(vertical: Insets.sm),
      child: Row(
        children: [
          for (final (i, item) in items.indexed) ...[if (i > 0) Gaps.w8, item],
        ],
      ),
    );
  }
}

class _PickerChip extends StatelessWidget {
  const _PickerChip({
    required this.icon,
    required this.label,
    required this.active,
  });

  final IconData icon;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final fg = active ? scheme.onSurface : colors.mutedText;
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: Insets.md),
      decoration: BoxDecoration(
        color: active ? colors.pressed : null,
        borderRadius: Radii.mdAll,
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: fg),
          Gaps.w8,
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 200),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelLarge
                  ?.copyWith(color: fg),
            ),
          ),
          Icon(Icons.arrow_drop_down, size: 18, color: fg),
        ],
      ),
    );
  }
}
