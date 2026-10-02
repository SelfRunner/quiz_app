/// Minimal RFC 4180 CSV / delimiter-separated values codec (pure Dart).
///
/// Writing quotes a field when it contains the delimiter, a quote, CR or LF
/// (or starts / ends with spaces); rows end with CRLF. Reading accepts LF or
/// CRLF line ends, quoted fields with `""` escapes and embedded newlines,
/// and reports for every row the 1-based physical line it starts on.
library;

/// One parsed row and the (1-based) line it starts on.
class CsvRow {
  const CsvRow(this.line, this.fields);

  final int line;
  final List<String> fields;

  /// Field [i] or '' when the row is shorter.
  String operator [](int i) => i < fields.length ? fields[i] : '';

  /// Whether every field is blank.
  bool get isBlank => fields.every((f) => f.trim().isEmpty);

  @override
  String toString() => 'CsvRow($line, $fields)';
}

/// Thrown for structurally broken input (e.g. an unterminated quote).
class CsvFormatException implements Exception {
  const CsvFormatException(this.message, this.line);

  final String message;
  final int line;

  @override
  String toString() => 'CsvFormatException(line $line): $message';
}

/// Encodes [rows] (fields are converted with `toString`, null -> '').
String encodeCsv(
  Iterable<Iterable<Object?>> rows, {
  String delimiter = ',',
  String eol = '\r\n',
}) {
  final out = StringBuffer();
  for (final row in rows) {
    var first = true;
    for (final value in row) {
      if (!first) out.write(delimiter);
      first = false;
      out.write(_quote(value?.toString() ?? '', delimiter));
    }
    out.write(eol);
  }
  return out.toString();
}

String _quote(String field, String delimiter) {
  final needs =
      field.contains(delimiter) ||
      field.contains('"') ||
      field.contains('\n') ||
      field.contains('\r') ||
      (field.isNotEmpty && (field.startsWith(' ') || field.endsWith(' ')));
  if (!needs) return field;
  return '"${field.replaceAll('"', '""')}"';
}

/// Parses [input]; a leading UTF-8 BOM is ignored. Throws
/// [CsvFormatException] for an unterminated quoted field.
List<CsvRow> decodeCsv(String input, {String delimiter = ','}) {
  assert(delimiter.length == 1, 'delimiter must be one character');
  final text = input.startsWith('﻿') ? input.substring(1) : input;
  final d = delimiter.codeUnitAt(0);
  const quote = 0x22;
  const cr = 0x0d;
  const lf = 0x0a;
  final rows = <CsvRow>[];
  var fields = <String>[];
  final field = StringBuffer();
  var line = 1;
  var rowLine = 1;
  var i = 0;
  var inQuotes = false;
  var quotedStartLine = 1;
  var atFieldStart = true;
  var rowHasContent = false;

  void endField() {
    fields.add(field.toString());
    field.clear();
    atFieldStart = true;
  }

  void endRow() {
    endField();
    rows.add(CsvRow(rowLine, fields));
    fields = <String>[];
    rowHasContent = false;
  }

  while (i < text.length) {
    final c = text.codeUnitAt(i);
    if (inQuotes) {
      if (c == quote) {
        if (i + 1 < text.length && text.codeUnitAt(i + 1) == quote) {
          field.writeCharCode(quote);
          i += 2;
          continue;
        }
        inQuotes = false;
        i++;
        continue;
      }
      if (c == lf) line++;
      field.writeCharCode(c);
      i++;
      continue;
    }
    if (c == quote && atFieldStart) {
      inQuotes = true;
      quotedStartLine = line;
      atFieldStart = false;
      rowHasContent = true;
      i++;
      continue;
    }
    if (c == d) {
      endField();
      rowHasContent = true;
      i++;
      continue;
    }
    if (c == cr || c == lf) {
      endRow();
      if (c == cr && i + 1 < text.length && text.codeUnitAt(i + 1) == lf) i++;
      i++;
      line++;
      rowLine = line;
      continue;
    }
    field.writeCharCode(c);
    atFieldStart = false;
    rowHasContent = true;
    i++;
  }
  if (inQuotes) {
    throw CsvFormatException('A quoted field is not closed.', quotedStartLine);
  }
  if (rowHasContent || field.isNotEmpty || fields.isNotEmpty) endRow();
  return rows;
}
