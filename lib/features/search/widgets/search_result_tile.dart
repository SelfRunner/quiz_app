import 'package:flutter/material.dart';

import '../../../core/widgets/design_system.dart';
import '../../../search/search_models.dart';
import '../application/search_logic.dart';

/// Style for matched characters in titles and snippets.
TextStyle searchHighlightStyle(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  return TextStyle(
    fontWeight: FontWeight.w600,
    color: scheme.onSurface,
    backgroundColor: scheme.primary.withValues(alpha: 0.14),
  );
}

/// One search hit: type icon, highlighted title, highlighted snippet and
/// the subject (plus "Archived" / pin markers).
class SearchResultTile extends StatelessWidget {
  const SearchResultTile({
    super.key,
    required this.result,
    required this.onTap,
    this.selected = false,
    this.dense = false,
    this.showSnippet = true,
  });

  final SearchResult result;
  final VoidCallback onTap;

  /// Keyboard selection.
  final bool selected;
  final bool dense;
  final bool showSnippet;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final highlight = searchHighlightStyle(context);
    final r = result;
    final title = r.title.trim().isEmpty ? 'Untitled' : r.title;
    final meta = [
      if (r.type != SearchItemType.subject && r.subjectTitle != null)
        r.subjectTitle!,
      if (r.archived) 'Archived',
    ].join(' · ');
    return ListRowTile(
      key: ValueKey('search-result-${r.type.name}-${r.id}'),
      selected: selected,
      dense: dense,
      revealActionsOnHover: false,
      leading: Icon(searchTypeIcon(r.type)),
      title: Text.rich(
        highlightedSpan(title, r.titleHighlights, highlight: highlight),
      ),
      subtitle: showSnippet && r.snippet.isNotEmpty
          ? Text.rich(
              highlightedSpan(
                r.snippet,
                r.snippetHighlights,
                highlight: highlight,
              ),
              maxLines: dense ? 1 : 2,
            )
          : null,
      trailing: meta.isEmpty && !r.document.pinned
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (r.document.pinned)
                  Padding(
                    padding: const EdgeInsets.only(right: Insets.xs),
                    child: Icon(
                      Icons.push_pin,
                      size: 14,
                      color: colors.faintText,
                      semanticLabel: 'Pinned',
                    ),
                  ),
                if (meta.isNotEmpty)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 180),
                    child: Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
      onTap: onTap,
    );
  }
}
