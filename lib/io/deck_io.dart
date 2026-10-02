import '../core/utils/clock.dart';
import '../data/models/models.dart';
import 'csv.dart';
import 'import_report.dart';

/// Flashcard deck export / import (pure Dart, strings in and out).
///
/// - **CSV**: header `front,back,hint`, RFC 4180 quoting (newlines kept).
/// - **Anki TSV** ("Notes in Plain Text"): file headers `#separator:tab`,
///   `#html:true`, `#columns:Front\tBack\tHint` (and `#tags:` with the
///   deck's tags), one card per line, HTML-escaped, newlines as `<br>`.
///   Import into Anki with a note type that has 2-3 fields.
/// - Import of either (see [importDeckText] for auto-detection): blank
///   lines and `#` lines skipped, header row optional, rows without a
///   front or back reported with their line number and skipped.
abstract final class DeckFormats {
  static const List<String> csvHeader = ['front', 'back', 'hint'];
}

String deckToCsv(Deck deck) => encodeCsv([
  DeckFormats.csvHeader,
  for (final c in deck.cards) [c.front, c.back, c.hint ?? ''],
]);

String deckToAnkiTsv(Deck deck) {
  final out = StringBuffer()
    ..writeln('#separator:tab')
    ..writeln('#html:true')
    ..writeln('#columns:Front\tBack\tHint');
  final tags = [for (final t in deck.tags) t.replaceAll(RegExp(r'\s+'), '_')];
  if (tags.isNotEmpty) out.writeln('#tags:${tags.join(' ')}');
  for (final c in deck.cards) {
    out.writeln([c.front, c.back, c.hint ?? ''].map(_toAnkiHtml).join('\t'));
  }
  return out.toString();
}

String _toAnkiHtml(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll('\t', '    ')
    .replaceAll(RegExp(r'\r?\n'), '<br>');

/// Imports CSV or Anki TSV, detected from the content: `#separator:` /
/// `#html:` headers or tabs in the first data line mean TSV.
ImportResult<Flashcard> importDeckText(
  String text, {
  IdGenerator newId = uuidV4,
}) {
  final firstData = text
      .split(RegExp(r'\r?\n'))
      .firstWhere(
        (l) => l.trim().isNotEmpty && !l.startsWith('#'),
        orElse: () => '',
      );
  final tsv =
      text.contains('#separator:') ||
      text.contains('#html:') ||
      firstData.contains('\t');
  return tsv
      ? importDeckTsv(text, newId: newId)
      : importDeckCsv(text, newId: newId);
}

ImportResult<Flashcard> importDeckCsv(
  String text, {
  IdGenerator newId = uuidV4,
}) => _import(text, delimiter: ',', html: false, comments: false, newId: newId);

/// Anki-style TSV. HTML is converted to text (`<br>` / `<div>` -> newline,
/// other tags dropped, entities decoded) when the file says `#html:true`,
/// or has no `#html:` header and contains `<br>`.
ImportResult<Flashcard> importDeckTsv(
  String text, {
  IdGenerator newId = uuidV4,
}) {
  var separator = '\t';
  bool? html;
  for (final line in text.split(RegExp(r'\r?\n'))) {
    if (!line.startsWith('#')) continue;
    final lower = line.toLowerCase();
    if (lower.startsWith('#separator:')) {
      separator = switch (lower.substring(11).trim()) {
        'comma' || ',' => ',',
        'semicolon' || ';' => ';',
        'pipe' || '|' => '|',
        'colon' || ':' => ':',
        'space' || ' ' => ' ',
        _ => '\t',
      };
    } else if (lower.startsWith('#html:')) {
      html = lower.substring(6).trim() == 'true';
    }
  }
  html ??= RegExp('<br ?/?>', caseSensitive: false).hasMatch(text);
  return _import(
    text,
    delimiter: separator,
    html: html,
    comments: true,
    newId: newId,
  );
}

ImportResult<Flashcard> _import(
  String text, {
  required String delimiter,
  required bool html,
  required bool comments,
  required IdGenerator newId,
}) {
  // `#` lines (Anki file headers, comments) are blanked, keeping line
  // numbers.
  final cleaned = comments
      ? text.split('\n').map((l) => l.startsWith('#') ? '' : l).join('\n')
      : text;
  final List<CsvRow> rows;
  try {
    rows = decodeCsv(cleaned, delimiter: delimiter);
  } on CsvFormatException catch (e) {
    return ImportResult(errors: [ImportIssue(e.message, line: e.line)]);
  }
  final data = rows.where((r) => !r.isBlank).toList();
  var front = 0;
  var back = 1;
  var hint = 2;
  if (data.isNotEmpty) {
    final names = [for (final f in data.first.fields) f.trim().toLowerCase()];
    if (names.contains('front') && names.contains('back')) {
      front = names.indexOf('front');
      back = names.indexOf('back');
      hint = names.indexOf('hint');
      data.removeAt(0);
    }
  }
  String clean(String s) => (html ? _fromHtml(s) : s).trim();
  final cards = <Flashcard>[];
  final errors = <ImportIssue>[];
  final warnings = <ImportIssue>[];
  final used = <String>{};
  for (final row in data) {
    final f = clean(row[front]);
    final b = clean(row[back]);
    if (f.isEmpty || b.isEmpty) {
      errors.add(
        ImportIssue(
          f.isEmpty && b.isEmpty
              ? 'Missing front and back.'
              : f.isEmpty
              ? 'Missing front.'
              : 'Missing back.',
          line: row.line,
        ),
      );
      continue;
    }
    final h = hint < 0 ? '' : clean(row[hint]);
    final extra = hint < 0 ? 2 : 3;
    if (row.fields.length > extra &&
        row.fields.skip(extra).any((x) => x.trim().isNotEmpty)) {
      warnings.add(ImportIssue('Extra columns ignored.', line: row.line));
    }
    var id = newId();
    while (!used.add(id)) {
      id = newId();
    }
    cards.add(Flashcard(id: id, front: f, back: b, hint: h.isEmpty ? null : h));
  }
  if (data.isEmpty) {
    warnings.add(const ImportIssue('The file has no cards.'));
  }
  return ImportResult(items: cards, errors: errors, warnings: warnings);
}

String _fromHtml(String s) => s
    .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
    .replaceAll(RegExp(r'</(div|p|li)>', caseSensitive: false), '\n')
    .replaceAll(RegExp(r'<[^>]+>'), '')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&amp;', '&');
