import '../../../data/models/question.dart';

/// Fixed options of a true/false question.
const List<String> trueFalseOptions = ['True', 'False'];

/// Limits for option questions in the editor.
const int minOptions = 2;
const int maxOptions = 8;

/// Field-level problems of one question (null / empty = fine). Mirrors the
/// question rules in `docs/CONTRACTS.md` (same as the AI `DraftValidator`),
/// phrased for people instead of the model.
class QuestionIssues {
  const QuestionIssues({
    this.prompt,
    this.optionErrors = const {},
    this.choice,
    this.answer,
  });

  /// Problem with the question text.
  final String? prompt;

  /// Problems of single options, by option index.
  final Map<int, String> optionErrors;

  /// Problem with the option list as a whole or with the correct marking.
  final String? choice;

  /// Problem with the expected answer (short answer).
  final String? answer;

  static const none = QuestionIssues();

  bool get isEmpty =>
      prompt == null &&
      optionErrors.isEmpty &&
      choice == null &&
      answer == null;

  bool get isNotEmpty => !isEmpty;

  /// All messages, deduplicated, in display order.
  List<String> get messages =>
      {?prompt, ...optionErrors.values, ?choice, ?answer}.toList();
}

abstract final class QuestionMessages {
  static const prompt = 'Enter the question text.';
  static const emptyOption = "Option can't be empty.";
  static const duplicateOption = 'Options must be different.';
  static const tooFewOptions = 'Add at least $minOptions options.';
  static const tooManyOptions = 'Use at most $maxOptions options.';
  static const markOne = 'Mark the correct answer.';
  static const markAtLeastOne = 'Mark at least one correct answer.';
  static const trueOrFalse = 'Choose whether the statement is True or False.';
  static const answer = 'Enter the expected answer.';
}

/// Validates [q] against the question rules.
QuestionIssues validateQuestion(Question q) {
  final prompt = q.prompt.trim().isEmpty ? QuestionMessages.prompt : null;
  switch (q.type) {
    case QuestionType.shortAnswer:
      return QuestionIssues(
        prompt: prompt,
        answer: (q.answerText ?? '').trim().isEmpty
            ? QuestionMessages.answer
            : null,
      );
    case QuestionType.trueFalse:
      final ok =
          q.correctIndices.length == 1 &&
          (q.correctIndices.first == 0 || q.correctIndices.first == 1);
      return QuestionIssues(
        prompt: prompt,
        choice: ok ? null : QuestionMessages.trueOrFalse,
      );
    case QuestionType.mcqSingle:
    case QuestionType.mcqMulti:
      final optionErrors = <int, String>{};
      final seen = <String>{};
      for (var i = 0; i < q.options.length; i++) {
        final text = q.options[i].trim();
        if (text.isEmpty) {
          optionErrors[i] = QuestionMessages.emptyOption;
        } else if (!seen.add(text.toLowerCase())) {
          optionErrors[i] = QuestionMessages.duplicateOption;
        }
      }
      String? choice;
      final valid = {
        for (final i in q.correctIndices)
          if (i >= 0 && i < q.options.length) i,
      };
      if (q.options.length < minOptions) {
        choice = QuestionMessages.tooFewOptions;
      } else if (q.options.length > maxOptions) {
        choice = QuestionMessages.tooManyOptions;
      } else if (q.type == QuestionType.mcqSingle && valid.length != 1) {
        choice = QuestionMessages.markOne;
      } else if (q.type == QuestionType.mcqMulti && valid.isEmpty) {
        choice = QuestionMessages.markAtLeastOne;
      }
      return QuestionIssues(
        prompt: prompt,
        optionErrors: optionErrors,
        choice: choice,
      );
  }
}

/// Trims text, drops empty optional fields and enforces the per-type shape
/// (sorted unique indices, fixed True/False options, no options for short
/// answers). Call before saving.
Question normalizeQuestion(Question q) {
  String? opt(String? s) {
    final t = s?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  final indices = q.correctIndices.toSet().toList()..sort();
  return switch (q.type) {
    QuestionType.shortAnswer => q.copyWith(
      prompt: q.prompt.trim(),
      options: const [],
      correctIndices: const [],
      answerText: opt(q.answerText),
      explanation: opt(q.explanation),
    ),
    QuestionType.trueFalse => q.copyWith(
      prompt: q.prompt.trim(),
      options: trueFalseOptions,
      correctIndices: indices,
      answerText: null,
      explanation: opt(q.explanation),
    ),
    QuestionType.mcqSingle || QuestionType.mcqMulti => q.copyWith(
      prompt: q.prompt.trim(),
      options: [for (final o in q.options) o.trim()],
      correctIndices: indices,
      answerText: opt(q.answerText),
      explanation: opt(q.explanation),
    ),
  };
}

/// A blank question of [type] ready for the editor.
Question blankQuestion(
  String id, {
  QuestionType type = QuestionType.mcqSingle,
}) => switch (type) {
  QuestionType.trueFalse => Question(
    id: id,
    type: type,
    prompt: '',
    options: trueFalseOptions,
    correctIndices: const [0],
  ),
  QuestionType.shortAnswer => Question(id: id, type: type, prompt: ''),
  _ => Question(
    id: id,
    type: type,
    prompt: '',
    options: const ['', '', '', ''],
  ),
};

/// Whether a selection of option indices answers [q] correctly (exact set
/// match; order and duplicates do not matter).
bool isCorrectSelection(Question q, Iterable<int> selected) {
  final a = selected.toSet();
  final b = q.correctIndices.toSet();
  return a.length == b.length && a.containsAll(b);
}
