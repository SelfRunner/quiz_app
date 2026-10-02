import 'dart:math' as math;

import '../data/models/tags.dart';
import 'search_models.dart';
import 'text_normalizer.dart';

/// In-memory inverted index over [SearchDocument]s (pure Dart).
///
/// - **Indexing**: title, tags and body are tokenized ([tokenize]:
///   lowercase, diacritics folded, light plural stemming). Each term stores
///   one weight per document (title 4, tag 3, body BM25-like tf with length
///   normalization), packed into one int list per term.
/// - **Query**: every query word must match (AND), exactly (stemmed) or as a
///   prefix of an indexed term (words of >= 2 chars, lower weight), so
///   results update while typing. `"quoted phrases"` must occur as written
///   (in order) in the title or body.
/// - **Ranking**: sum of term weight x idf, plus bonuses for an exact /
///   leading title match, the query as a phrase (title > body), recency
///   (half-life ~ 6 weeks) and pinned items; archived items rank lower.
/// - **Results**: title highlight ranges and a body snippet around the
///   first match with highlight ranges (offsets into the returned strings).
/// - **Updates**: [upsert] / [remove] are incremental (no rebuild).
class SearchIndex {
  final Map<String, _Entry> _byKey = {};
  final List<_Entry?> _entries = [];
  final List<int> _freeOrds = [];
  final Map<String, _Posting> _postings = {};
  List<String>? _vocabulary;

  /// Subjects whose items are archived (maintained by the owner of the
  /// index, e.g. `LiveSearchIndex`).
  Set<String> archivedSubjectIds = {};

  /// Titles of subjects for [SearchResult.subjectTitle] (subject documents
  /// in the index are used when missing here).
  Map<String, String> subjectTitles = {};

  static const double _titleWeight = 4;
  static const double _tagWeight = 3;
  static const int _weightScale = 1000;
  static const int _pack = 65536;
  static const int _maxPrefixExpansions = 128;
  static const int _snippetLength = 180;
  static const int _snippetLead = 50;
  static const int _maxSnippetScan = 100000;
  static const int _maxPhraseScan = 50000;

  int get length => _byKey.length;

  bool contains(SearchItemType type, String id) =>
      _byKey.containsKey('${type.name}:$id');

  SearchDocument? document(SearchItemType type, String id) =>
      _byKey['${type.name}:$id']?.doc;

  Iterable<SearchDocument> get documents => _byKey.values.map((e) => e.doc);

  void clear() {
    _byKey.clear();
    _entries.clear();
    _freeOrds.clear();
    _postings.clear();
    _vocabulary = null;
  }

  /// Adds or replaces a document.
  void upsert(SearchDocument doc) {
    final existing = _byKey[doc.key];
    if (existing != null) {
      if (existing.doc == doc) return;
      _unlink(existing);
    }
    final ord = existing?.ord ?? _allocOrd();
    final entry = _Entry(ord, doc);
    _entries[ord] = entry;
    _byKey[doc.key] = entry;
    _link(entry);
  }

  /// Removes a document; returns whether it was indexed.
  bool remove(SearchItemType type, String id) {
    final entry = _byKey.remove('${type.name}:$id');
    if (entry == null) return false;
    _unlink(entry);
    _entries[entry.ord] = null;
    _freeOrds.add(entry.ord);
    return true;
  }

  int _allocOrd() {
    if (_freeOrds.isNotEmpty) return _freeOrds.removeLast();
    _entries.add(null);
    return _entries.length - 1;
  }

  void _link(_Entry entry) {
    final doc = entry.doc;
    final weights = <String, double>{};
    final titleTerms = terms(doc.title);
    entry.titleTerms = titleTerms;
    for (final t in titleTerms.toSet()) {
      weights[t] = _titleWeight;
    }
    entry.tags = normalizeTags(doc.tags);
    for (final tag in entry.tags) {
      for (final t in terms(tag).toSet()) {
        weights[t] = (weights[t] ?? 0) + _tagWeight;
      }
    }
    if (doc.body.isNotEmpty) {
      final tf = <String, int>{};
      var length = 0;
      for (final t in terms(doc.body)) {
        tf[t] = (tf[t] ?? 0) + 1;
        length++;
      }
      // BM25 saturation with length normalization (k1 1.2, b 0.75, avg 200).
      final norm = 1.2 * (0.25 + 0.75 * length / 200);
      for (final MapEntry(key: t, value: f) in tf.entries) {
        weights[t] = (weights[t] ?? 0) + f * 2.2 / (f + norm);
      }
    }
    final postings = <_Posting>[];
    for (final MapEntry(key: t, value: w) in weights.entries) {
      var posting = _postings[t];
      if (posting == null) {
        posting = _postings[t] = _Posting(t);
        _vocabulary = null;
      }
      final q = math.min((w * _weightScale).round(), _pack - 1);
      posting.packed.add(entry.ord * _pack + q);
      postings.add(posting);
    }
    entry.postings = postings;
  }

  void _unlink(_Entry entry) {
    for (final posting in entry.postings) {
      final list = posting.packed;
      for (var i = 0; i < list.length; i++) {
        if (list[i] ~/ _pack == entry.ord) {
          list[i] = list.last;
          list.removeLast();
          break;
        }
      }
      if (list.isEmpty) {
        _postings.remove(posting.term);
        _vocabulary = null;
      }
    }
    entry.postings = const [];
  }

  List<String> get _sortedVocabulary =>
      _vocabulary ??= (_postings.keys.toList()..sort());

  /// Indexed terms starting with [prefix] (excluding [prefix] itself).
  Iterable<String> _expand(String prefix) sync* {
    final vocab = _sortedVocabulary;
    var lo = 0;
    var hi = vocab.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (vocab[mid].compareTo(prefix) < 0) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    var n = 0;
    for (var i = lo; i < vocab.length && n < _maxPrefixExpansions; i++) {
      final t = vocab[i];
      if (!t.startsWith(prefix)) break;
      if (t == prefix) continue;
      n++;
      yield t;
    }
  }

  /// Smoothed idf (>= 1 + ln 2), so field weights keep their meaning even
  /// for terms present in every document.
  double _idf(int df) => 1 + math.log(1 + _byKey.length / math.max(df, 1));

  // ---------------------------------------------------------------------------
  // Search
  // ---------------------------------------------------------------------------

  /// Ranked results for [query] (at most [limit]). An empty query returns
  /// the most recent items matching [filters] when any filter is set, and
  /// nothing otherwise. [now] drives the recency bonus.
  List<SearchResult> search(
    String query, {
    SearchFilters filters = const SearchFilters(),
    int limit = 50,
    DateTime? now,
  }) {
    final parsed = _ParsedQuery.parse(query);
    final at = now ?? DateTime.now().toUtc();
    final filterTags = normalizeTags(filters.tags);
    bool passes(_Entry e) => _passes(e, filters, filterTags);

    if (parsed.words.isEmpty) {
      if (filters.isEmpty) return const [];
      final entries = _byKey.values.where(passes).toList()
        ..sort((a, b) => b.doc.updatedAt.compareTo(a.doc.updatedAt));
      return [for (final e in entries.take(limit)) _result(e, 0, parsed)];
    }

    // Candidate scores per query word, intersected (AND).
    Map<int, double>? scores;
    for (final word in parsed.words) {
      final matches = _matchWord(word);
      if (matches.isEmpty) return const [];
      if (scores == null) {
        scores = matches;
      } else {
        final next = <int, double>{};
        final (small, large) = matches.length < scores.length
            ? (matches, scores)
            : (scores, matches);
        for (final MapEntry(key: ord, value: s) in small.entries) {
          final other = large[ord];
          if (other != null) next[ord] = s + other;
        }
        scores = next;
        if (scores.isEmpty) return const [];
      }
    }

    final candidates = <(_Entry, double)>[];
    for (final MapEntry(key: ord, value: s) in scores!.entries) {
      final e = _entries[ord];
      if (e != null && passes(e)) candidates.add((e, s));
    }
    candidates.sort((a, b) => b.$2.compareTo(a.$2));
    final pool = candidates.take(math.max(limit * 4, 100));

    final ranked = <(_Entry, double)>[];
    for (final (entry, base) in pool) {
      if (!_phrasesMatch(entry, parsed)) continue;
      ranked.add((entry, base + _bonus(entry, parsed, at)));
    }
    ranked.sort((a, b) {
      final c = b.$2.compareTo(a.$2);
      return c != 0 ? c : b.$1.doc.updatedAt.compareTo(a.$1.doc.updatedAt);
    });
    return [
      for (final (entry, score) in ranked.take(limit))
        _result(entry, score, parsed),
    ];
  }

  /// Ord -> best weight x idf for one query word (exact stem or prefix).
  Map<int, double> _matchWord(_QueryWord word) {
    final result = <int, double>{};
    void add(String term, double factor) {
      final posting = _postings[term];
      if (posting == null) return;
      final idf = _idf(posting.packed.length);
      for (final p in posting.packed) {
        final ord = p ~/ _pack;
        final w = (p % _pack) / _weightScale * idf * factor;
        final current = result[ord];
        if (current == null || w > current) result[ord] = w;
      }
    }

    add(word.stem, 1);
    if (word.folded != word.stem) add(word.folded, 1);
    if (word.folded.length >= 2) {
      for (final term in _expand(word.folded)) {
        if (term == word.stem) continue;
        add(term, 0.6);
      }
    }
    return result;
  }

  bool _passes(_Entry e, SearchFilters f, List<String> tags) {
    final doc = e.doc;
    if (f.types.isNotEmpty && !f.types.contains(doc.type)) return false;
    if (f.subjectId != null && doc.subjectId != f.subjectId) return false;
    if (f.pinnedOnly && !doc.pinned) return false;
    if (!f.includeArchived && _isArchived(doc)) return false;
    if (tags.isNotEmpty && !tags.every(e.tags.contains)) return false;
    return true;
  }

  bool _isArchived(SearchDocument doc) =>
      doc.subjectId != null && archivedSubjectIds.contains(doc.subjectId);

  double _bonus(_Entry entry, _ParsedQuery q, DateTime now) {
    var bonus = 0.0;
    final stems = q.stems;
    final title = entry.titleTerms;
    if (stems.isNotEmpty && _listEquals(title, stems)) {
      bonus += 6;
    } else if (stems.isNotEmpty && _startsWith(title, stems)) {
      bonus += 2;
    }
    if (stems.length >= 2) {
      if (_containsSequence(title, stems)) {
        bonus += 3;
      } else if (_bodyContains(entry.doc.body, stems)) {
        bonus += 1.5;
      }
    }
    final ageDays = now.difference(entry.doc.updatedAt).inHours / 24;
    bonus += 1.0 * math.pow(0.5, math.max(0, ageDays) / 42);
    if (entry.doc.pinned) bonus += 0.3;
    if (_isArchived(entry.doc)) bonus -= 1;
    return bonus;
  }

  bool _phrasesMatch(_Entry entry, _ParsedQuery q) {
    for (final phrase in q.phrases) {
      if (phrase.isEmpty) continue;
      if (_containsSequence(entry.titleTerms, phrase)) continue;
      if (_bodyContains(entry.doc.body, phrase)) continue;
      return false;
    }
    return true;
  }

  static bool _bodyContains(String body, List<String> seq) {
    if (body.isEmpty) return false;
    final text = body.length > _maxPhraseScan
        ? body.substring(0, _maxPhraseScan)
        : body;
    return _containsSequence(terms(text), seq);
  }

  static bool _containsSequence(List<String> haystack, List<String> seq) {
    if (seq.isEmpty || haystack.length < seq.length) return false;
    outer:
    for (var i = 0; i <= haystack.length - seq.length; i++) {
      for (var j = 0; j < seq.length; j++) {
        if (haystack[i + j] != seq[j]) continue outer;
      }
      return true;
    }
    return false;
  }

  static bool _startsWith(List<String> list, List<String> prefix) {
    if (list.length < prefix.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (list[i] != prefix[i]) return false;
    }
    return true;
  }

  static bool _listEquals(List<String> a, List<String> b) =>
      a.length == b.length && _startsWith(a, b);

  // ---------------------------------------------------------------------------
  // Results, highlights, snippets
  // ---------------------------------------------------------------------------

  SearchResult _result(_Entry entry, double score, _ParsedQuery q) {
    final doc = entry.doc;
    final titleHighlights = q.words.isEmpty
        ? const <HighlightRange>[]
        : _highlights(doc.title, q, 0);
    final snippet = _snippet(doc.body, q);
    final matched = <SearchField>{
      if (titleHighlights.isNotEmpty) SearchField.title,
      if (snippet.highlights.isNotEmpty) SearchField.body,
      if (q.words.isNotEmpty &&
          entry.tags.any((t) => terms(t).any(q.matchesTerm)))
        SearchField.tags,
    };
    final subjectId = doc.subjectId;
    return SearchResult(
      document: doc,
      score: score,
      titleHighlights: titleHighlights,
      snippet: snippet.text,
      snippetHighlights: snippet.highlights,
      matchedFields: matched,
      subjectTitle: subjectId == null
          ? null
          : subjectTitles[subjectId] ??
                _byKey['${SearchItemType.subject.name}:$subjectId']?.doc.title,
      archived: _isArchived(doc),
    );
  }

  static List<HighlightRange> _highlights(
    String text,
    _ParsedQuery q,
    int offset,
  ) => [
    for (final token in tokenizeLazy(text))
      if (q.matchesToken(token, text))
        HighlightRange(token.start + offset, token.end + offset),
  ];

  static ({String text, List<HighlightRange> highlights}) _snippet(
    String body,
    _ParsedQuery q,
  ) {
    if (body.isEmpty) return (text: '', highlights: const []);
    int? first;
    if (q.words.isNotEmpty) {
      for (final token in tokenizeLazy(body)) {
        if (token.start > _maxSnippetScan) break;
        if (q.matchesToken(token, body)) {
          first = token.start;
          break;
        }
      }
    }
    var start = 0;
    if (first != null && first > _snippetLead) {
      start = first - _snippetLead;
      // Start after a whitespace so the snippet does not cut a word.
      final space = body.indexOf(RegExp(r'\s'), start);
      if (space >= 0 && space < first) start = space + 1;
    }
    var end = math.min(body.length, start + _snippetLength);
    if (end < body.length) {
      final space = body.lastIndexOf(RegExp(r'\s'), end);
      if (space > (first ?? start) + 1 && space > start) end = space;
    }
    final prefix = start > 0 ? '…' : '';
    final window = body
        .substring(start, end)
        .replaceAll(RegExp(r'[\r\n\t]'), ' ');
    final text = '$prefix${window.trimRight()}${end < body.length ? '…' : ''}';
    if (q.words.isEmpty) return (text: text, highlights: const []);
    return (
      text: text,
      highlights: _highlights(window.trimRight(), q, prefix.length),
    );
  }
}

class _Entry {
  _Entry(this.ord, this.doc);

  final int ord;
  final SearchDocument doc;
  List<String> titleTerms = const [];
  List<String> tags = const [];
  List<_Posting> postings = const [];
}

class _Posting {
  _Posting(this.term);

  final String term;

  /// `ord * 65536 + weight * 1000` per document (int-only arithmetic, safe
  /// on the web).
  final List<int> packed = [];
}

class _QueryWord {
  _QueryWord(this.folded) : stem = _stemWord(folded);

  /// Lowercase, folded, unstemmed (prefix matching).
  final String folded;

  /// Index form.
  final String stem;
}

String _stemWord(String w) => stem(w);

class _ParsedQuery {
  _ParsedQuery(this.words, this.phrases);

  factory _ParsedQuery.parse(String query) {
    final phrases = <List<String>>[];
    for (final m in RegExp('"([^"]+)"').allMatches(query)) {
      final p = terms(m[1]!);
      if (p.length > 1) phrases.add(p);
    }
    final words = <_QueryWord>[];
    final seen = <String>{};
    for (final m in RegExp(r'[\p{L}\p{N}]+', unicode: true).allMatches(query)) {
      final folded = foldWord(m[0]!);
      if (seen.add(folded)) words.add(_QueryWord(folded));
    }
    return _ParsedQuery(words, phrases);
  }

  final List<_QueryWord> words;
  final List<List<String>> phrases;

  List<String> get stems => [for (final w in words) w.stem];

  /// Whether an indexed term matches a query word.
  bool matchesTerm(String term) {
    for (final w in words) {
      if (term == w.stem || term == w.folded) return true;
      if (w.folded.length >= 2 && term.startsWith(w.folded)) return true;
    }
    return false;
  }

  /// Whether a token of [text] matches (stem, or folded word prefix).
  bool matchesToken(Token token, String text) {
    for (final w in words) {
      if (token.term == w.stem || token.term == w.folded) return true;
      if (w.folded.length >= 2) {
        final folded = foldWord(text.substring(token.start, token.end));
        if (folded.startsWith(w.folded)) return true;
      }
    }
    return false;
  }
}
