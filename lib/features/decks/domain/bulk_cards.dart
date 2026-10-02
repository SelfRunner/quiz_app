import 'package:meta/meta.dart';

/// One card parsed from bulk text (no id yet).
@immutable
class CardText {
  const CardText({required this.front, required this.back, this.hint});

  final String front;
  final String back;
  final String? hint;

  @override
  bool operator ==(Object other) =>
      other is CardText &&
      other.front == front &&
      other.back == back &&
      other.hint == hint;

  @override
  int get hashCode => Object.hash(front, back, hint);

  @override
  String toString() =>
      'CardText($front :: $back${hint == null ? '' : ' :: $hint'})';
}

/// Result of [parseBulkCards].
@immutable
class BulkParseResult {
  const BulkParseResult({this.cards = const [], this.invalidLines = const []});

  final List<CardText> cards;

  /// 1-based numbers of non-blank lines that could not be parsed.
  final List<int> invalidLines;

  bool get isEmpty => cards.isEmpty;
}

/// Separator between front, back and the optional hint.
const String bulkSeparator = '::';

/// Parses one card per line: `front :: back` or `front :: back :: hint`.
/// A tab also separates the sides (pasted spreadsheet / Anki / Quizlet
/// exports). `\n` inside a side becomes a line break. Blank lines and lines
/// starting with `#` are skipped; lines without both a front and a back are
/// reported in [BulkParseResult.invalidLines].
BulkParseResult parseBulkCards(String text) {
  final cards = <CardText>[];
  final invalid = <int>[];
  final lines = text.split(RegExp(r'\r?\n'));
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final parts = line.contains(bulkSeparator)
        ? line.split(bulkSeparator)
        : line.split('\t');
    if (parts.length < 2) {
      invalid.add(i + 1);
      continue;
    }
    String clean(String s) => s.trim().replaceAll(r'\n', '\n');
    final front = clean(parts[0]);
    // Extra separators beyond the hint stay part of the hint.
    final back = clean(parts[1]);
    final hint = parts.length > 2
        ? clean(parts.sublist(2).join(bulkSeparator))
        : '';
    if (front.isEmpty || back.isEmpty) {
      invalid.add(i + 1);
      continue;
    }
    cards.add(
      CardText(front: front, back: back, hint: hint.isEmpty ? null : hint),
    );
  }
  return BulkParseResult(cards: cards, invalidLines: invalid);
}
