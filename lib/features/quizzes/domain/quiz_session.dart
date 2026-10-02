import 'dart:math';

import '../../../data/models/question.dart';
import '../../../data/models/quiz_attempt.dart';
import 'question_rules.dart';

/// One question as presented in a play session.
class PlayItem {
  const PlayItem(this.question, this.optionOrder);

  final Question question;

  /// `optionOrder[displayIndex]` = index into `question.options`.
  final List<int> optionOrder;

  String get id => question.id;

  List<String> get displayOptions => [
    for (final i in optionOrder) question.options[i],
  ];
}

/// Play items for [questions], optionally shuffling the question order and
/// the answer options (true/false keeps its natural order).
List<PlayItem> buildPlayItems(
  List<Question> questions, {
  bool shuffleQuestions = false,
  bool shuffleOptions = false,
  Random? random,
}) {
  final rng = random ?? Random();
  final ordered = [...questions];
  if (shuffleQuestions) ordered.shuffle(rng);
  return [
    for (final q in ordered)
      PlayItem(q, () {
        final order = List<int>.generate(q.options.length, (i) => i);
        if (shuffleOptions && q.type != QuestionType.trueFalse) {
          order.shuffle(rng);
        }
        return order;
      }()),
  ];
}

/// Mutable state of one run through a quiz (UI calls `setState` after each
/// mutation). Selections are stored as *original* option indices so the
/// recorded [QuestionAnswer]s do not depend on shuffling.
class QuizSession {
  QuizSession({
    required List<Question> questions,
    required this.startedAt,
    this.shuffleQuestions = false,
    this.shuffleOptions = false,
    this.isPractice = false,
    Random? random,
  }) : items = buildPlayItems(
         questions,
         shuffleQuestions: shuffleQuestions,
         shuffleOptions: shuffleOptions,
         random: random,
       );

  final List<PlayItem> items;
  final DateTime startedAt;
  final bool shuffleQuestions;
  final bool shuffleOptions;

  /// "Retry missed only" rounds: not saved to the attempt history.
  final bool isPractice;

  int index = 0;
  final Map<String, Set<int>> _selected = {};
  final Map<String, String> _texts = {};
  final Map<String, bool> _grades = {};
  final Set<String> _revealed = {};
  final Set<String> _partial = {};

  int get length => items.length;
  PlayItem get current => items[index];
  bool get isLast => index >= items.length - 1;

  Set<int> selectedFor(String id) => _selected[id] ?? const {};
  String textFor(String id) => _texts[id] ?? '';

  /// Grade of a question, null while unanswered.
  bool? gradeFor(String id) => _grades[id];
  bool isChecked(String id) => _grades.containsKey(id);
  bool isRevealed(String id) => _revealed.contains(id);

  /// Graded "partly correct" (AI grading): counts as wrong for mistakes and
  /// "retry missed", and as half a point in [credit].
  bool isPartial(String id) => _partial.contains(id) && _grades[id] == false;

  /// Number of graded questions so far.
  int get answeredCount => _grades.length;
  int get correctCount => _grades.values.where((g) => g).length;

  /// Questions graded partly correct.
  int get partialCount => items.where((i) => isPartial(i.id)).length;

  /// Score in points: correct answers plus half a point per partly correct
  /// answer (stored as `QuizAttempt.score`).
  double get credit => correctCount + partialCount * 0.5;
  bool get isComplete => items.every((i) => _grades.containsKey(i.id));

  /// Toggles/sets the option shown at [displayIndex] of the current question.
  void toggleOption(int displayIndex) {
    final item = current;
    if (isChecked(item.id)) return;
    if (displayIndex < 0 || displayIndex >= item.optionOrder.length) return;
    final original = item.optionOrder[displayIndex];
    final set = {...selectedFor(item.id)};
    if (item.question.type == QuestionType.mcqMulti) {
      if (!set.remove(original)) set.add(original);
    } else {
      set
        ..clear()
        ..add(original);
    }
    _selected[item.id] = set;
  }

  void setText(String text) => _texts[current.id] = text;

  bool get canCheck {
    final item = current;
    if (isChecked(item.id)) return false;
    return item.question.type.hasOptions
        ? selectedFor(item.id).isNotEmpty
        : !isRevealed(item.id);
  }

  /// Auto-grades the current option question. Returns the grade.
  bool check() {
    final item = current;
    final grade = isCorrectSelection(item.question, selectedFor(item.id));
    _grades[item.id] = grade;
    return grade;
  }

  /// Shows the model answer of the current short-answer question.
  void reveal() => _revealed.add(current.id);

  /// Records the grade of the current short-answer question (self-grade or
  /// AI verdict). [partial] (only with `correct: false`) marks it partly
  /// correct.
  void selfGrade({required bool correct, bool partial = false}) {
    final id = current.id;
    _revealed.add(id);
    _grades[id] = correct;
    if (partial && !correct) {
      _partial.add(id);
    } else {
      _partial.remove(id);
    }
  }

  void next() {
    if (!isLast) index++;
  }

  void previous() {
    if (index > 0) index--;
  }

  /// Answers in play order (ungraded questions get `isCorrect: null`).
  List<QuestionAnswer> answers() => [
    for (final item in items) answerFor(item.id),
  ];

  /// The answer to question [id] so far.
  QuestionAnswer answerFor(String id) => QuestionAnswer(
    questionId: id,
    selectedIndices: (selectedFor(id).toList()..sort()),
    textAnswer: _texts[id]?.trim().isEmpty ?? true ? null : _texts[id]!.trim(),
    isCorrect: _grades[id],
  );

  /// Questions answered wrong or not at all, in play order.
  List<Question> get missedQuestions => [
    for (final item in items)
      if (_grades[item.id] != true) item.question,
  ];

  /// Score as a fraction 0..1.
  double get fraction => items.isEmpty ? 0 : credit / items.length;

  /// Graded answers only (`isCorrect != null`), e.g. for mistake tracking.
  List<QuestionAnswer> gradedAnswers() => [
    for (final a in answers())
      if (a.isCorrect != null) a,
  ];

  /// Whole seconds between [startedAt] and [completedAt] (never negative).
  int durationSecondsAt(DateTime completedAt) =>
      max(0, completedAt.difference(startedAt).inSeconds);

  /// Attempt record for this session (answers, score, completion and
  /// `durationSeconds`).
  QuizAttempt toAttempt(QuizAttempt started, {required DateTime completedAt}) =>
      started.copyWith(
        answers: answers(),
        score: credit,
        total: items.length,
        startedAt: startedAt,
        completedAt: completedAt,
        durationSeconds: durationSecondsAt(completedAt),
      );
}
