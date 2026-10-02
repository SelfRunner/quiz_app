import 'package:meta/meta.dart';

/// A problem found while importing (line numbers are 1-based; null when the
/// input has no lines, e.g. a JSON path problem).
@immutable
class ImportIssue {
  const ImportIssue(this.message, {this.line, this.field});

  final String message;
  final int? line;

  /// Column / JSON path the issue is about (e.g. `correct`,
  /// `questions[2].options`).
  final String? field;

  @override
  bool operator ==(Object other) =>
      other is ImportIssue &&
      other.message == message &&
      other.line == line &&
      other.field == field;

  @override
  int get hashCode => Object.hash(message, line, field);

  @override
  String toString() {
    final where = [if (line != null) 'line $line', ?field].join(', ');
    return where.isEmpty ? message : '$where: $message';
  }
}

/// Outcome of an import: the valid [items], the rows that were skipped
/// ([errors]) and non-fatal [warnings]. [title] / [description] / [tags]
/// come from the file when it has them (JSON, front matter).
@immutable
class ImportResult<T> {
  const ImportResult({
    this.items = const [],
    this.errors = const [],
    this.warnings = const [],
    this.title,
    this.description,
    this.tags = const [],
  });

  final List<T> items;
  final List<ImportIssue> errors;
  final List<ImportIssue> warnings;
  final String? title;
  final String? description;
  final List<String> tags;

  bool get hasErrors => errors.isNotEmpty;

  /// Nothing usable was found.
  bool get isEmpty => items.isEmpty;

  /// Human-readable report, one issue per line (errors first).
  String get report => [
    for (final e in errors) 'Error: $e',
    for (final w in warnings) 'Warning: $w',
  ].join('\n');
}
