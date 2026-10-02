/// Text normalization for the local search index (pure Dart).
///
/// - [foldDiacritics]: lowercase-insensitive folding of Latin diacritics
///   (`é` -> `e`, `ß` -> `ss`, `Æ` -> `ae`, combining marks dropped).
/// - [tokenize]: runs of Unicode letters / digits with their offsets in the
///   original text (so highlights map back to it).
/// - [normalizeTerm]: lowercase + fold + [stem].
/// - [stem]: light English plural stemming (`notes` -> `note`, `classes` ->
///   `class`, `studies` -> `study`); conservative so it rarely conflates
///   unrelated words.
library;

/// One token of a text: `text.substring(start, end)` normalizes to [term].
class Token {
  const Token(this.start, this.end, this.term);

  final int start;
  final int end;

  /// Normalized (lowercase, folded, stemmed) form.
  final String term;

  @override
  String toString() => 'Token($start..$end $term)';
}

final RegExp _wordPattern = RegExp(r'[\p{L}\p{N}]+', unicode: true);

/// Letters / digits runs of [text] (with offsets), normalized.
List<Token> tokenize(String text) => [
  for (final m in _wordPattern.allMatches(text))
    Token(m.start, m.end, normalizeTerm(m[0]!)),
];

/// Lazily tokenizes [text] (for scanning long bodies until a match).
Iterable<Token> tokenizeLazy(String text) => _wordPattern
    .allMatches(text)
    .map((m) => Token(m.start, m.end, normalizeTerm(m[0]!)));

/// Lowercase + diacritic fold of one word (no stemming).
String foldWord(String word) => foldDiacritics(word.toLowerCase());

/// Index / query form of one word.
String normalizeTerm(String word) => stem(foldWord(word));

/// Normalized terms of [text] in order.
List<String> terms(String text) => [
  for (final m in _wordPattern.allMatches(text)) normalizeTerm(m[0]!),
];

/// Light plural stemmer for lowercase, folded words.
String stem(String w) {
  final n = w.length;
  if (n <= 3) return w;
  final last = w.codeUnitAt(n - 1);
  if (last != 0x73 /* s */ ) return w;
  if (w.endsWith('ss') || w.endsWith('us') || w.endsWith('is')) return w;
  if (n > 4 && w.endsWith('ies')) return '${w.substring(0, n - 3)}y';
  if (w.endsWith('sses') ||
      w.endsWith('ches') ||
      w.endsWith('shes') ||
      w.endsWith('xes') ||
      w.endsWith('zes')) {
    return w.substring(0, n - 2);
  }
  return w.substring(0, n - 1);
}

/// Folds Latin diacritics and a few ligatures to ASCII; other characters
/// are kept. Expects lowercase input for the ligature mappings to be
/// complete (uppercase letters are folded to lowercase ASCII as well).
String foldDiacritics(String s) {
  var ascii = true;
  for (var i = 0; i < s.length; i++) {
    if (s.codeUnitAt(i) > 0x7f) {
      ascii = false;
      break;
    }
  }
  if (ascii) return s;
  final out = StringBuffer();
  for (final rune in s.runes) {
    if (rune < 0x80) {
      out.writeCharCode(rune);
      continue;
    }
    // Combining diacritical marks (from NFD input): drop.
    if (rune >= 0x0300 && rune <= 0x036f) continue;
    final mapped = _foldMap[rune];
    if (mapped != null) {
      out.write(mapped);
    } else {
      out.writeCharCode(rune);
    }
  }
  return out.toString();
}

final Map<int, String> _foldMap = _buildFoldMap();

Map<int, String> _buildFoldMap() {
  const groups = <String, String>{
    'a': 'àáâãäåāăąǎǟǡǻȁȃȧẚạảấầẩẫậắằẳẵặÀÁÂÃÄÅĀĂĄǍǞǠǺȀȂȦẠẢẤẦẨẪẬẮẰẲẴẶ',
    'c': 'çćĉċčÇĆĈĊČ',
    'd': 'ďđðĎĐÐ',
    'e': 'èéêëēĕėęěȅȇȩẹẻẽếềểễệÈÉÊËĒĔĖĘĚȄȆȨẸẺẼẾỀỂỄỆ',
    'g': 'ĝğġģǧǵĜĞĠĢǦǴ',
    'h': 'ĥħȟĤĦȞ',
    'i': 'ìíîïĩīĭįıǐȉȋịỉÌÍÎÏĨĪĬĮİǏȈȊỊỈ',
    'j': 'ĵǰĴ',
    'k': 'ķǩĶǨ',
    'l': 'ĺļľŀłĹĻĽĿŁ',
    'n': 'ñńņňŉǹÑŃŅŇǸ',
    'o': 'òóôõöøōŏőơǒǫǭǿȍȏȫȭȯȱọỏốồổỗộớờởỡợÒÓÔÕÖØŌŎŐƠǑǪǬǾȌȎȪȬȮȰỌỎỐỒỔỖỘỚỜỞỠỢ',
    'r': 'ŕŗřȑȓŔŖŘȐȒ',
    's': 'śŝşšșŚŜŞŠȘ',
    't': 'ţťŧțŢŤŦȚ',
    'u': 'ùúûüũūŭůűųưǔǖǘǚǜȕȗụủứừửữựÙÚÛÜŨŪŬŮŰŲƯǓǕǗǙǛȔȖỤỦỨỪỬỮỰ',
    'w': 'ŵẁẃẅŴẀẂẄ',
    'y': 'ýÿŷỳỵỷỹÝŸŶỲỴỶỸ',
    'z': 'źżžŹŻŽ',
    'ss': 'ßẞ',
    'ae': 'æǽÆǼ',
    'oe': 'œŒ',
    'th': 'þÞ',
  };
  final map = <int, String>{};
  for (final MapEntry(key: ascii, value: chars) in groups.entries) {
    for (final rune in chars.runes) {
      map[rune] = ascii;
    }
  }
  return map;
}
