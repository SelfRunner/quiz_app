import '../data/models/drafts.dart';
import '../data/models/question.dart';

/// Outcome of validating model output.
///
/// [value] holds the normalized draft built from the *valid* parts (invalid
/// questions are dropped), or null when nothing usable remains. [errors]
/// lists every problem found, phrased so they can be sent back to the model
/// in a repair prompt.
class DraftValidation<T> {
  const DraftValidation(this.value, this.errors);

  final T? value;
  final List<String> errors;

  bool get isValid => value != null && errors.isEmpty;
}

/// Validates and normalizes AI output against the draft contracts
/// (`QuizDraft` / `NoteDraft`, see `docs/CONTRACTS.md` question rules).
///
/// Lenient about harmless variations (whitespace, camelCase keys, numeric
/// strings, `true`/`false` casing, duplicate indices) and strict about
/// anything that would make a question wrong or unanswerable.
abstract final class DraftValidator {
  static const trueFalseOptions = ['True', 'False'];

  static DraftValidation<QuizDraft> validateQuiz(
    Map<String, dynamic> json, {
    Set<QuestionType>? allowedTypes,
    int? maxQuestions,
  }) {
    final errors = <String>[];
    final title = _string(json['title']);
    if (title == null || title.isEmpty) {
      errors.add('"title" must be a non-empty string.');
    }
    final description = _string(json['description']);

    final rawQuestions = json['questions'];
    if (rawQuestions is! List) {
      errors.add('"questions" must be an array of question objects.');
      return DraftValidation(null, errors);
    }

    final questions = <QuestionDraft>[];
    final seenPrompts = <String>{};
    for (var i = 0; i < rawQuestions.length; i++) {
      final raw = rawQuestions[i];
      final label = 'questions[$i]';
      if (raw is! Map) {
        errors.add('$label must be an object.');
        continue;
      }
      final q = _validateQuestion(
        raw.cast<String, dynamic>(),
        label,
        errors,
        allowedTypes,
      );
      if (q == null) continue;
      final key = _normalizeForDedupe(q.prompt);
      if (!seenPrompts.add(key)) continue; // silently drop duplicates
      questions.add(q);
    }

    if (questions.isEmpty) {
      errors.add('The quiz must contain at least one valid question.');
      return DraftValidation(null, errors);
    }
    final limited = (maxQuestions != null && questions.length > maxQuestions)
        ? questions.sublist(0, maxQuestions)
        : questions;
    return DraftValidation(
      QuizDraft(
        title: (title == null || title.isEmpty) ? 'Generated quiz' : title,
        description: (description == null || description.isEmpty)
            ? null
            : description,
        questions: limited,
      ),
      errors,
    );
  }

  static QuestionDraft? _validateQuestion(
    Map<String, dynamic> raw,
    String label,
    List<String> errors,
    Set<QuestionType>? allowedTypes,
  ) {
    final before = errors.length;
    final type = _parseType(raw['type']);
    if (type == null) {
      errors.add(
        '$label.type must be one of mcq_single, mcq_multi, true_false, '
        'short_answer (got ${raw['type']}).',
      );
      return null;
    }
    if (allowedTypes != null && !allowedTypes.contains(type)) {
      errors.add(
        '$label.type "${type.wireName}" is not allowed; use only '
        '${allowedTypes.map((t) => t.wireName).join(', ')}.',
      );
      return null;
    }
    final prompt = _string(raw['prompt']) ?? _string(raw['question']);
    if (prompt == null || prompt.isEmpty) {
      errors.add('$label.prompt must be a non-empty string.');
    }
    var options = <String>[
      for (final o in (raw['options'] as List?) ?? const <Object?>[])
        if (o != null) o.toString().trim(),
    ];
    final rawIndices =
        (raw['correct_indices'] ?? raw['correctIndices']) as Object?;
    final indicesOk = rawIndices == null || rawIndices is List;
    var indices = <int>[
      if (rawIndices is List)
        for (final v in rawIndices) ?_toInt(v),
    ];
    if (!indicesOk ||
        (rawIndices is List && indices.length != rawIndices.length)) {
      errors.add('$label.correct_indices must be an array of integers.');
    }
    indices = indices.toSet().toList()..sort();
    final answerText = _string(raw['answer_text'] ?? raw['answerText']);
    final explanation = _string(raw['explanation']);

    switch (type) {
      case QuestionType.shortAnswer:
        options = const [];
        indices = const [];
        if (answerText == null || answerText.isEmpty) {
          errors.add(
            '$label is short_answer and needs a non-empty answer_text.',
          );
        }
      case QuestionType.trueFalse:
        final mapped = _normalizeTrueFalse(options, indices);
        if (mapped == null) {
          errors.add(
            '$label is true_false: options must be exactly ["True","False"] '
            'and correct_indices exactly one of [0] or [1].',
          );
        } else {
          options = trueFalseOptions;
          indices = mapped;
        }
      case QuestionType.mcqSingle:
      case QuestionType.mcqMulti:
        if (options.length < 2) {
          errors.add('$label needs at least 2 options.');
        } else if (options.any((o) => o.isEmpty)) {
          errors.add('$label has an empty option.');
        } else if (options.map((o) => o.toLowerCase()).toSet().length !=
            options.length) {
          errors.add('$label has duplicate options.');
        }
        final outOfRange = indices.where((i) => i < 0 || i >= options.length);
        if (outOfRange.isNotEmpty) {
          errors.add(
            '$label.correct_indices ${outOfRange.toList()} are out of range '
            'for ${options.length} options (zero-based).',
          );
        } else if (type == QuestionType.mcqSingle && indices.length != 1) {
          errors.add(
            '$label is mcq_single and needs exactly 1 correct index (got '
            '${indices.length}).',
          );
        } else if (type == QuestionType.mcqMulti && indices.isEmpty) {
          errors.add('$label is mcq_multi and needs at least 1 correct index.');
        }
    }
    if (errors.length != before) return null;
    return QuestionDraft(
      type: type,
      prompt: prompt!,
      options: options,
      correctIndices: indices,
      answerText: (answerText == null || answerText.isEmpty)
          ? null
          : answerText,
      explanation: (explanation == null || explanation.isEmpty)
          ? null
          : explanation,
    );
  }

  /// Returns the correct index in `['True','False']` order, or null if the
  /// options/indices do not describe a valid true/false question. Accepts
  /// `['False','True']` (remapped) and empty options with one index.
  static List<int>? _normalizeTrueFalse(List<String> options, List<int> idx) {
    if (idx.length != 1) return null;
    final lower = options.map((o) => o.toLowerCase()).toList();
    if (lower.isEmpty) {
      return (idx.first == 0 || idx.first == 1) ? idx : null;
    }
    if (lower.length != 2 || idx.first < 0 || idx.first > 1) return null;
    if (lower[0] == 'true' && lower[1] == 'false') return idx;
    if (lower[0] == 'false' && lower[1] == 'true') return [1 - idx.first];
    return null;
  }

  static DraftValidation<NoteDraft> validateNote(Map<String, dynamic> json) {
    final errors = <String>[];
    final title = _string(json['title']);
    final content = _string(
      json['content_markdown'] ?? json['contentMarkdown'],
    );
    if (title == null || title.isEmpty) {
      errors.add('"title" must be a non-empty string.');
    }
    if (content == null || content.isEmpty) {
      errors.add('"content_markdown" must be non-empty Markdown.');
    }
    if (errors.isNotEmpty) return DraftValidation(null, errors);
    return DraftValidation(
      NoteDraft(title: title!, contentMarkdown: content!),
      errors,
    );
  }

  static QuestionType? _parseType(Object? raw) {
    if (raw is! String) return null;
    final v = raw
        .trim()
        .toLowerCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_');
    for (final t in QuestionType.values) {
      if (t.wireName == v || t.name.toLowerCase() == v) return t;
    }
    return null;
  }

  static String? _string(Object? v) => v is String ? v.trim() : null;

  static int? _toInt(Object? v) => switch (v) {
    final int i => i,
    final double d when d == d.roundToDouble() => d.toInt(),
    final String s => int.tryParse(s.trim()),
    _ => null,
  };

  static String _normalizeForDedupe(String s) =>
      s.toLowerCase().replaceAll(_dedupeNoise, ' ').trim();

  static final _dedupeNoise = RegExp(r'[\s\p{P}\p{S}]+', unicode: true);
}
