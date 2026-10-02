import 'package:flutter/material.dart';

import '../../../core/router/routes.dart';
import '../../../data/models/tags.dart';
import '../../../search/search_models.dart';

/// Display order of result groups.
const List<SearchItemType> searchTypeOrder = [
  SearchItemType.subject,
  SearchItemType.note,
  SearchItemType.quiz,
  SearchItemType.deck,
  SearchItemType.attachment,
  SearchItemType.chat,
];

String searchTypeLabel(SearchItemType type, {bool plural = true}) =>
    switch (type) {
      SearchItemType.subject => plural ? 'Subjects' : 'Subject',
      SearchItemType.note => plural ? 'Notes' : 'Note',
      SearchItemType.quiz => plural ? 'Quizzes' : 'Quiz',
      SearchItemType.deck => plural ? 'Decks' : 'Deck',
      SearchItemType.attachment => plural ? 'Files' : 'File',
      SearchItemType.chat => plural ? 'Chats' : 'Chat',
    };

IconData searchTypeIcon(SearchItemType type) => switch (type) {
  SearchItemType.subject => Icons.library_books_outlined,
  SearchItemType.note => Icons.description_outlined,
  SearchItemType.quiz => Icons.quiz_outlined,
  SearchItemType.deck => Icons.style_outlined,
  SearchItemType.attachment => Icons.attach_file,
  SearchItemType.chat => Icons.chat_bubble_outline,
};

/// Where a result opens. Files open their subject (the Files library).
String searchResultRoute(SearchResult r) => switch (r.type) {
  SearchItemType.subject => AppRoutes.subject(r.id),
  SearchItemType.note => AppRoutes.note(r.id),
  SearchItemType.quiz => AppRoutes.quiz(r.id),
  SearchItemType.deck => AppRoutes.deck(r.id),
  SearchItemType.attachment =>
    r.document.subjectId == null
        ? AppRoutes.subjects
        : AppRoutes.subject(r.document.subjectId!),
  SearchItemType.chat => AppRoutes.chat(r.id),
};

/// Results of one type, in rank order.
@immutable
class SearchGroup {
  const SearchGroup(this.type, this.results, {this.total});

  final SearchItemType type;
  final List<SearchResult> results;

  /// Results of this type before [groupSearchResults]' `perGroup` cut.
  final int? total;
}

/// Groups ranked [results] by type in [searchTypeOrder] (rank order kept
/// inside a group). [perGroup] caps each group (quick search).
List<SearchGroup> groupSearchResults(
  List<SearchResult> results, {
  int? perGroup,
}) {
  final byType = <SearchItemType, List<SearchResult>>{};
  for (final r in results) {
    (byType[r.type] ??= []).add(r);
  }
  return [
    for (final type in searchTypeOrder)
      if (byType[type] case final list?)
        SearchGroup(
          type,
          perGroup == null || list.length <= perGroup
              ? list
              : list.sublist(0, perGroup),
          total: list.length,
        ),
  ];
}

/// The results in display order (what ↑ / ↓ walk through).
List<SearchResult> flattenGroups(List<SearchGroup> groups) => [
  for (final g in groups) ...g.results,
];

/// Free text plus the `tag:x` / `tag:"x y"` tokens of a typed query.
typedef ParsedSearchInput = ({String text, Set<String> tags});

final RegExp _tagToken = RegExp(r'(?:^|\s)tag:(?:"([^"]*)"|(\S+))');

/// Splits `tag:` tokens (see `tagSearchQuery`) off [raw].
ParsedSearchInput parseSearchInput(String raw) {
  final tags = <String>{};
  final text = raw.replaceAllMapped(_tagToken, (m) {
    final tag = normalizeTag(m[1] ?? m[2] ?? '');
    if (tag != null) tags.add(tag);
    return ' ';
  });
  return (text: text.replaceAll(RegExp(r'\s+'), ' ').trim(), tags: tags);
}

/// [text] as spans with [ranges] (offsets into [text]) styled [highlight].
/// Out-of-range / overlapping ranges are clamped and merged.
TextSpan highlightedSpan(
  String text,
  List<HighlightRange> ranges, {
  TextStyle? style,
  required TextStyle highlight,
}) {
  if (ranges.isEmpty || text.isEmpty) return TextSpan(text: text, style: style);
  final sorted = [
    for (final r in ranges)
      if (r.start < text.length && r.end > r.start)
        (
          start: r.start.clamp(0, text.length),
          end: r.end.clamp(0, text.length),
        ),
  ]..sort((a, b) => a.start.compareTo(b.start));
  // Merge overlapping / touching ranges.
  final merged = <({int start, int end})>[];
  for (final r in sorted) {
    if (merged.isNotEmpty && r.start <= merged.last.end) {
      final last = merged.removeLast();
      merged.add((start: last.start, end: r.end > last.end ? r.end : last.end));
    } else {
      merged.add(r);
    }
  }
  final children = <TextSpan>[];
  var pos = 0;
  for (final r in merged) {
    if (r.start > pos) {
      children.add(TextSpan(text: text.substring(pos, r.start)));
    }
    children.add(
      TextSpan(text: text.substring(r.start, r.end), style: highlight),
    );
    pos = r.end;
  }
  if (pos < text.length) children.add(TextSpan(text: text.substring(pos)));
  return TextSpan(style: style, children: children);
}
