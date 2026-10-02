import 'package:meta/meta.dart';

/// Kinds of items in the search index.
enum SearchItemType { subject, note, quiz, deck, attachment, chat }

/// A searchable item. [title], [body] and [tags] are indexed; the other
/// fields drive filters and result display.
@immutable
class SearchDocument {
  const SearchDocument({
    required this.type,
    required this.id,
    required this.title,
    this.body = '',
    this.tags = const [],
    this.subjectId,
    this.noteId,
    this.ownerId,
    required this.updatedAt,
    this.pinned = false,
  });

  final SearchItemType type;
  final String id;
  final String title;

  /// Plain searchable text (note body without Markdown syntax, quiz
  /// prompts / options, deck cards, attachment text, ...).
  final String body;
  final List<String> tags;

  /// Subject the item belongs to (for subjects: their own id; chats: the
  /// scope's subject when known).
  final String? subjectId;

  /// Parent note of a quiz / deck (or a chat's note scope).
  final String? noteId;
  final String? ownerId;
  final DateTime updatedAt;
  final bool pinned;

  String get key => '${type.name}:$id';

  @override
  bool operator ==(Object other) =>
      other is SearchDocument &&
      other.type == type &&
      other.id == id &&
      other.title == title &&
      other.body == body &&
      _listEq(other.tags, tags) &&
      other.subjectId == subjectId &&
      other.noteId == noteId &&
      other.ownerId == ownerId &&
      other.updatedAt == updatedAt &&
      other.pinned == pinned;

  @override
  int get hashCode => Object.hash(type, id, title, updatedAt);

  @override
  String toString() => 'SearchDocument($key, $title)';
}

/// Filters applied to search results (all optional; empty = no filter).
@immutable
class SearchFilters {
  const SearchFilters({
    this.types = const {},
    this.subjectId,
    this.tags = const {},
    this.includeArchived = true,
    this.pinnedOnly = false,
  });

  /// Only these kinds (empty = all).
  final Set<SearchItemType> types;

  /// Only items of this subject (the subject itself included).
  final String? subjectId;

  /// Items carrying every one of these tags (normalized like tags).
  final Set<String> tags;

  /// Whether items of archived subjects (and archived subjects) match.
  final bool includeArchived;
  final bool pinnedOnly;

  bool get isEmpty =>
      types.isEmpty &&
      subjectId == null &&
      tags.isEmpty &&
      includeArchived &&
      !pinnedOnly;

  SearchFilters copyWith({
    Set<SearchItemType>? types,
    String? Function()? subjectId,
    Set<String>? tags,
    bool? includeArchived,
    bool? pinnedOnly,
  }) => SearchFilters(
    types: types ?? this.types,
    subjectId: subjectId != null ? subjectId() : this.subjectId,
    tags: tags ?? this.tags,
    includeArchived: includeArchived ?? this.includeArchived,
    pinnedOnly: pinnedOnly ?? this.pinnedOnly,
  );

  @override
  bool operator ==(Object other) =>
      other is SearchFilters &&
      _setEq(other.types, types) &&
      other.subjectId == subjectId &&
      _setEq(other.tags, tags) &&
      other.includeArchived == includeArchived &&
      other.pinnedOnly == pinnedOnly;

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(types),
    subjectId,
    Object.hashAllUnordered(tags),
    includeArchived,
    pinnedOnly,
  );

  @override
  String toString() =>
      'SearchFilters(types: $types, subject: $subjectId, tags: $tags, '
      'includeArchived: $includeArchived, pinnedOnly: $pinnedOnly)';
}

/// A highlighted range `[start, end)` in a result's title or snippet.
@immutable
class HighlightRange {
  const HighlightRange(this.start, this.end);

  final int start;
  final int end;

  @override
  bool operator ==(Object other) =>
      other is HighlightRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => '[$start, $end)';
}

/// Which part of the document matched best.
enum SearchField { title, tags, body }

/// One ranked hit.
@immutable
class SearchResult {
  const SearchResult({
    required this.document,
    required this.score,
    this.titleHighlights = const [],
    this.snippet = '',
    this.snippetHighlights = const [],
    this.matchedFields = const {},
    this.subjectTitle,
    this.archived = false,
  });

  final SearchDocument document;
  final double score;

  /// Ranges of [SearchDocument.title] that matched.
  final List<HighlightRange> titleHighlights;

  /// Short excerpt of the body around the first match ('…' marks cuts),
  /// or its beginning when only the title / tags matched.
  final String snippet;
  final List<HighlightRange> snippetHighlights;
  final Set<SearchField> matchedFields;

  /// Title of the item's subject, when cached.
  final String? subjectTitle;

  /// The item (or its subject) is archived.
  final bool archived;

  SearchItemType get type => document.type;
  String get id => document.id;
  String get title => document.title;

  @override
  String toString() =>
      'SearchResult(${document.key}, ${score.toStringAsFixed(2)})';
}

bool _listEq<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _setEq<T>(Set<T> a, Set<T> b) => a.length == b.length && a.containsAll(b);
