/// Tag rules shared by notes, quizzes and decks (`tags text[]`, Wave 3).
///
/// The server only bounds the data (<= [maxTags] tags, each non-blank and
/// <= [maxTagLength] chars); normalization is the client's job: trim,
/// collapse inner whitespace, lowercase, strip leading `#`, de-duplicate
/// (first occurrence wins, order kept).
abstract final class TagRules {
  static const int maxTags = 50;
  static const int maxTagLength = 64;
}

final RegExp _spaces = RegExp(r'\s+');

/// Normalized form of one tag, or null when it is blank.
/// Longer tags are cut to [TagRules.maxTagLength] characters.
String? normalizeTag(String tag) {
  var t = tag.trim().replaceAll(_spaces, ' ').toLowerCase();
  while (t.startsWith('#')) {
    t = t.substring(1).trimLeft();
  }
  if (t.isEmpty) return null;
  if (t.length > TagRules.maxTagLength) {
    t = t.substring(0, TagRules.maxTagLength).trimRight();
  }
  return t;
}

/// Normalized, de-duplicated tags in input order (blank ones dropped).
/// Does not enforce [TagRules.maxTags]; repositories reject longer lists.
List<String> normalizeTags(Iterable<String> tags) {
  final seen = <String>{};
  final result = <String>[];
  for (final tag in tags) {
    final n = normalizeTag(tag);
    if (n != null && seen.add(n)) result.add(n);
  }
  return result;
}
