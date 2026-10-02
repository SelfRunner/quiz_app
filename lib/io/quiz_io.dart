import 'dart:convert';

import '../core/utils/clock.dart';
import '../data/models/models.dart';
import 'csv.dart';
import 'import_report.dart';

/// Quiz export / import (pure Dart, strings in and out).
///
/// **JSON** (lossless): `{"format": "quiz_app.quiz", "version": 1,
/// "quiz": {...}}` where `quiz` is the quiz row JSON (snake_case, see
/// `Quiz.toJson`) without `owner_id`, `subject_id`, `note_id` and
/// `deleted_at`. Import also accepts a bare quiz object or a bare list of
/// questions (camelCase keys too).
///
/// **CSV**: header `type,prompt,options,correct,answer,explanation`;
/// options separated by `|` (`\|` = literal pipe, `\\` = backslash);
/// `correct` = **1-based** option numbers separated by `|` (`1|3`).
/// Import also accepts letters (`A|C`), the option text, `true` / `false`
/// for true/false questions, 0-based numbers (when a `0` appears; reported
/// as a warning), headers in any order (aliases: question, choices,
/// answer_text, ...) and files without a header (default column order).
abstract final class QuizFormats {
  static const String jsonFormat = 'quiz_app.quiz';
  static const int jsonVersion = 1;
  static const List<String> csvHeader = [
    'type',
    'prompt',
    'options',
    'correct',
    'answer',
    'explanation',
  ];
  static const List<String> trueFalseOptions = ['True', 'False'];
  static const int minOptions = 2;
  static const int maxOptions = 8;
}

// -----------------------------------------------------------------------------
// Export
// -----------------------------------------------------------------------------

/// Lossless, pretty-printed JSON of [quiz].
String quizToJson(Quiz quiz) {
  final json = quiz.toJson()
    ..remove('owner_id')
    ..remove('subject_id')
    ..remove('note_id')
    ..remove('deleted_at');
  return const JsonEncoder.withIndent('  ').convert({
    'format': QuizFormats.jsonFormat,
    'version': QuizFormats.jsonVersion,
    'quiz': json,
  });
}

/// CSV of [quiz]'s questions (with header, CRLF line ends).
String quizToCsv(Quiz quiz) => encodeCsv([
  QuizFormats.csvHeader,
  for (final q in quiz.questions)
    [
      q.type.wireName,
      q.prompt,
      q.options.map(_escapeOption).join('|'),
      q.correctIndices.map((i) => i + 1).join('|'),
      q.answerText ?? '',
      q.explanation ?? '',
    ],
]);

String _escapeOption(String o) =>
    o.replaceAll(r'\', r'\\').replaceAll('|', r'\|');

List<String> _splitOptions(String s) {
  if (s.trim().isEmpty) return const [];
  final out = <String>[];
  final cur = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (c == r'\' && i + 1 < s.length) {
      cur.write(s[++i]);
    } else if (c == '|') {
      out.add(cur.toString().trim());
      cur.clear();
    } else {
      cur.write(c);
    }
  }
  out.add(cur.toString().trim());
  return out;
}

// -----------------------------------------------------------------------------
// Import
// -----------------------------------------------------------------------------

/// Parses quiz JSON. Questions keep their ids when present and unique
/// (round trip), unless [newIds]; missing ids come from [newId].
ImportResult<Question> importQuizJson(
  String text, {
  IdGenerator newId = uuidV4,
  bool newIds = false,
}) {
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException catch (e) {
    return ImportResult(
      errors: [
        ImportIssue(
          'Not valid JSON: ${e.message}',
          line: _lineOf(text, e.offset),
        ),
      ],
    );
  }
  Object? quizJson = decoded;
  if (decoded is Map<String, dynamic> && decoded['quiz'] is Map) {
    final format = decoded['format'];
    if (format != null && format != QuizFormats.jsonFormat) {
      return ImportResult(
        errors: [ImportIssue('Unknown format "$format".', field: 'format')],
      );
    }
    quizJson = decoded['quiz'];
  }
  final List<dynamic> rawQuestions;
  String? title;
  String? description;
  var tags = const <String>[];
  final warnings = <ImportIssue>[];
  if (quizJson is List) {
    rawQuestions = quizJson;
  } else if (quizJson is Map<String, dynamic>) {
    final q = quizJson['questions'];
    if (q is! List) {
      return const ImportResult(
        errors: [ImportIssue('No "questions" list found.', field: 'questions')],
      );
    }
    rawQuestions = q;
    title = _string(quizJson['title'])?.trim();
    description = _string(quizJson['description']);
    final rawTags = quizJson['tags'];
    if (rawTags is List) {
      tags = normalizeTags(rawTags.whereType<String>());
    }
  } else {
    return const ImportResult(
      errors: [ImportIssue('Expected a quiz object or a list of questions.')],
    );
  }

  final questions = <Question>[];
  final errors = <ImportIssue>[];
  final usedIds = <String>{};
  for (var i = 0; i < rawQuestions.length; i++) {
    final path = 'questions[$i]';
    final raw = rawQuestions[i];
    if (raw is! Map<String, dynamic>) {
      errors.add(ImportIssue('Expected an object.', field: path));
      continue;
    }
    final type = _parseType(_string(raw['type']));
    final options = [
      for (final o in (raw['options'] is List ? raw['options'] as List : []))
        if (o != null) o.toString(),
    ];
    final correctRaw =
        raw['correct_indices'] ?? raw['correctIndices'] ?? raw['correct'];
    final correct = <int>[
      if (correctRaw is List)
        for (final c in correctRaw)
          if (c is int) c else if (c is num) c.toInt(),
      if (correctRaw is int) correctRaw,
    ];
    final draft = _Draft(
      type: type.type,
      typeName: type.raw,
      prompt: _string(raw['prompt']) ?? _string(raw['question']) ?? '',
      options: options,
      correct: correct,
      answer:
          _string(raw['answer_text']) ??
          _string(raw['answerText']) ??
          _string(raw['answer']),
      explanation: _string(raw['explanation']),
    );
    final result = draft.build();
    if (result.error != null) {
      errors.add(ImportIssue(result.error!, field: path));
      continue;
    }
    var id = newIds ? null : _string(raw['id']);
    if (id != null && (id.isEmpty || id.length > 255 || !usedIds.add(id))) {
      id = null;
    }
    id ??= _uniqueId(newId, usedIds);
    questions.add(result.question!.copyWith(id: id));
  }
  if (rawQuestions.isEmpty) {
    warnings.add(const ImportIssue('The file has no questions.'));
  }
  return ImportResult(
    items: questions,
    errors: errors,
    warnings: warnings,
    title: title == null || title.isEmpty ? null : title,
    description: description,
    tags: tags,
  );
}

/// Parses quiz CSV (see [QuizFormats]). Invalid rows are reported with
/// their line number and skipped.
ImportResult<Question> importQuizCsv(
  String text, {
  IdGenerator newId = uuidV4,
}) {
  final List<CsvRow> rows;
  try {
    rows = decodeCsv(text, delimiter: _guessDelimiter(text));
  } on CsvFormatException catch (e) {
    return ImportResult(errors: [ImportIssue(e.message, line: e.line)]);
  }
  final dataRows = rows.where((r) => !r.isBlank).toList();
  if (dataRows.isEmpty) {
    return const ImportResult(
      warnings: [ImportIssue('The file has no questions.')],
    );
  }
  var columns = const _Columns.defaults();
  var start = 0;
  final header = _Columns.fromHeader(dataRows.first);
  if (header != null) {
    columns = header;
    start = 1;
  }
  final questions = <Question>[];
  final errors = <ImportIssue>[];
  final warnings = <ImportIssue>[];
  final usedIds = <String>{};
  for (final row in dataRows.skip(start)) {
    final type = _parseType(row.at(columns.type));
    final options = _splitOptions(row.at(columns.options));
    final correct = _parseCorrect(row.at(columns.correct), options, type.type);
    if (correct.zeroBased) {
      warnings.add(
        ImportIssue(
          'Correct answers look 0-based (a "0" was found); read them as '
          '0-based.',
          line: row.line,
          field: 'correct',
        ),
      );
    }
    if (correct.error != null) {
      errors.add(ImportIssue(correct.error!, line: row.line, field: 'correct'));
      continue;
    }
    final answer = row.at(columns.answer).trim();
    final explanation = row.at(columns.explanation).trim();
    final result = _Draft(
      type: type.type,
      typeName: type.raw,
      prompt: row.at(columns.prompt),
      options: options,
      correct: correct.indices,
      answer: answer.isEmpty ? null : answer,
      explanation: explanation.isEmpty ? null : explanation,
    ).build();
    if (result.error != null) {
      errors.add(ImportIssue(result.error!, line: row.line));
      continue;
    }
    questions.add(result.question!.copyWith(id: _uniqueId(newId, usedIds)));
  }
  return ImportResult(items: questions, errors: errors, warnings: warnings);
}

// -----------------------------------------------------------------------------
// Helpers
// -----------------------------------------------------------------------------

String _guessDelimiter(String text) {
  final firstLine = text.split('\n').first;
  final commas = ','.allMatches(firstLine).length;
  final semis = ';'.allMatches(firstLine).length;
  final tabs = '\t'.allMatches(firstLine).length;
  if (tabs > commas && tabs >= semis) return '\t';
  if (semis > commas) return ';';
  return ',';
}

String _uniqueId(IdGenerator newId, Set<String> used) {
  var id = newId();
  while (!used.add(id)) {
    id = newId();
  }
  return id;
}

String? _string(Object? v) => v is String ? v : null;

int _lineOf(String text, int? offset) {
  if (offset == null) return 1;
  final end = offset.clamp(0, text.length);
  return '\n'.allMatches(text.substring(0, end)).length + 1;
}

/// Parsed type: null type = infer from the data; [raw] kept for messages.
({QuestionType? type, String? raw}) _parseType(String? value) {
  final v = value?.trim().toLowerCase().replaceAll(RegExp(r'[\s-]+'), '_');
  if (v == null || v.isEmpty) return (type: null, raw: null);
  final type = switch (v) {
    'mcq_single' ||
    'mcqsingle' ||
    'single' ||
    'mcq' ||
    'multiple_choice' ||
    'choice' => QuestionType.mcqSingle,
    'mcq_multi' ||
    'mcqmulti' ||
    'multi' ||
    'multiple' ||
    'multiple_answer' ||
    'checkbox' => QuestionType.mcqMulti,
    'true_false' ||
    'truefalse' ||
    'tf' ||
    'boolean' ||
    'true/false' => QuestionType.trueFalse,
    'short_answer' ||
    'shortanswer' ||
    'short' ||
    'text' ||
    'open' ||
    'flashcard' => QuestionType.shortAnswer,
    _ => null,
  };
  return (type: type, raw: value!.trim());
}

({List<int> indices, String? error, bool zeroBased}) _parseCorrect(
  String raw,
  List<String> options,
  QuestionType? type,
) {
  final parts = raw
      .split(RegExp(r'[|;,]'))
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return (indices: const [], error: null, zeroBased: false);
  final isTrueFalse =
      type == QuestionType.trueFalse ||
      (type == null &&
          options.isEmpty &&
          parts.length == 1 &&
          {'true', 'false', 't', 'f'}.contains(parts.single.toLowerCase()));
  if (isTrueFalse && parts.length == 1) {
    final v = parts.single.toLowerCase();
    if (v == 'true' || v == 't') {
      return (indices: const [0], error: null, zeroBased: false);
    }
    if (v == 'false' || v == 'f') {
      return (indices: const [1], error: null, zeroBased: false);
    }
  }
  final numbers = parts.map(int.tryParse).toList();
  if (numbers.every((n) => n != null)) {
    final zeroBased = numbers.contains(0);
    return (
      indices: [for (final n in numbers) zeroBased ? n! : n! - 1],
      error: null,
      zeroBased: zeroBased,
    );
  }
  final indices = <int>[];
  for (final p in parts) {
    if (p.length == 1 && RegExp('[A-Za-z]').hasMatch(p)) {
      indices.add(p.toUpperCase().codeUnitAt(0) - 0x41);
      continue;
    }
    final byText = options.indexWhere(
      (o) => o.toLowerCase() == p.toLowerCase(),
    );
    if (byText < 0) {
      return (
        indices: const [],
        error: 'Unknown correct answer "$p" (use option numbers, e.g. 1|3).',
        zeroBased: false,
      );
    }
    indices.add(byText);
  }
  return (indices: indices, error: null, zeroBased: false);
}

/// Column positions of a CSV file.
class _Columns {
  const _Columns({
    required this.type,
    required this.prompt,
    required this.options,
    required this.correct,
    required this.answer,
    required this.explanation,
  });

  const _Columns.defaults()
    : type = 0,
      prompt = 1,
      options = 2,
      correct = 3,
      answer = 4,
      explanation = 5;

  final int type;
  final int prompt;
  final int options;
  final int correct;
  final int answer;
  final int explanation;

  /// Columns from a header row, or null when [row] is not a header.
  static _Columns? fromHeader(CsvRow row) {
    int find(Set<String> names) {
      for (var i = 0; i < row.fields.length; i++) {
        final name = row.fields[i].trim().toLowerCase().replaceAll(
          RegExp(r'[\s-]+'),
          '_',
        );
        if (names.contains(name)) return i;
      }
      return -1;
    }

    final prompt = find({'prompt', 'question', 'text'});
    if (prompt < 0) return null;
    return _Columns(
      type: find({'type', 'question_type', 'kind'}),
      prompt: prompt,
      options: find({'options', 'choices', 'answers'}),
      correct: find({
        'correct',
        'correct_indices',
        'correct_index',
        'correct_answer',
        'correct_answers',
        'solution',
      }),
      answer: find({'answer', 'answer_text', 'expected_answer'}),
      explanation: find({'explanation', 'explain', 'rationale', 'notes'}),
    );
  }
}

extension on CsvRow {
  String at(int column) => column < 0 ? '' : this[column];
}

/// Raw question fields before validation.
class _Draft {
  _Draft({
    required this.type,
    required this.typeName,
    required this.prompt,
    required this.options,
    required this.correct,
    required this.answer,
    required this.explanation,
  });

  final QuestionType? type;
  final String? typeName;
  final String prompt;
  final List<String> options;
  final List<int> correct;
  final String? answer;
  final String? explanation;

  /// A valid question (id empty) or an error message.
  ({Question? question, String? error}) build() {
    if (typeName != null && type == null) {
      return (question: null, error: 'Unknown question type "$typeName".');
    }
    final p = prompt.trim();
    if (p.isEmpty) return (question: null, error: 'The question is empty.');
    final explanationText = explanation?.trim();
    final expl = explanationText == null || explanationText.isEmpty
        ? null
        : explanationText;
    final answerText = answer?.trim();
    final ans = answerText == null || answerText.isEmpty ? null : answerText;
    final resolved =
        type ??
        (options.isEmpty
            ? (correct.isEmpty ? QuestionType.shortAnswer : null)
            : (correct.length > 1
                  ? QuestionType.mcqMulti
                  : QuestionType.mcqSingle));
    switch (resolved) {
      case null:
        return (question: null, error: 'Add options or a question type.');
      case QuestionType.shortAnswer:
        if (ans == null) {
          return (question: null, error: 'Short answer needs an answer.');
        }
        return (
          question: Question(
            id: '',
            type: QuestionType.shortAnswer,
            prompt: p,
            answerText: ans,
            explanation: expl,
          ),
          error: null,
        );
      case QuestionType.trueFalse:
        if (correct.length != 1 ||
            (correct.single != 0 && correct.single != 1)) {
          return (
            question: null,
            error: 'True/false needs one correct answer: true or false.',
          );
        }
        if (options.isNotEmpty) {
          final lower = options.map((o) => o.toLowerCase()).toList();
          if (lower.length != 2 || lower[0] != 'true' || lower[1] != 'false') {
            return (
              question: null,
              error: 'True/false options must be True|False.',
            );
          }
        }
        return (
          question: Question(
            id: '',
            type: QuestionType.trueFalse,
            prompt: p,
            options: QuizFormats.trueFalseOptions,
            correctIndices: correct,
            answerText: ans,
            explanation: expl,
          ),
          error: null,
        );
      case QuestionType.mcqSingle:
      case QuestionType.mcqMulti:
        final opts = [for (final o in options) o.trim()];
        if (opts.length < QuizFormats.minOptions) {
          return (
            question: null,
            error: 'Add at least ${QuizFormats.minOptions} options.',
          );
        }
        if (opts.length > QuizFormats.maxOptions) {
          return (
            question: null,
            error: 'Use at most ${QuizFormats.maxOptions} options.',
          );
        }
        if (opts.any((o) => o.isEmpty)) {
          return (question: null, error: "An option can't be empty.");
        }
        if (opts.map((o) => o.toLowerCase()).toSet().length != opts.length) {
          return (question: null, error: 'Options must be different.');
        }
        final unique = correct.toSet().toList()..sort();
        if (unique.any((i) => i < 0 || i >= opts.length)) {
          return (
            question: null,
            error: 'A correct answer points to a missing option.',
          );
        }
        if (unique.isEmpty) {
          return (question: null, error: 'Mark the correct answer.');
        }
        if (resolved == QuestionType.mcqSingle && unique.length != 1) {
          return (
            question: null,
            error: 'Single choice needs exactly one correct answer.',
          );
        }
        return (
          question: Question(
            id: '',
            type: resolved,
            prompt: p,
            options: opts,
            correctIndices: unique,
            answerText: ans,
            explanation: expl,
          ),
          error: null,
        );
    }
  }
}
