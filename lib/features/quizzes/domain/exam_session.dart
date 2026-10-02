import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';

import '../../../data/models/question.dart';
import '../../../data/models/quiz_attempt.dart';
import 'quiz_session.dart';

/// Options chosen in the exam setup.
@immutable
class ExamConfig {
  const ExamConfig({
    this.questionCount,
    this.timeLimitMinutes,
    this.shuffleOptions = false,
  });

  /// Random pool size; null = every question.
  final int? questionCount;

  /// Null = untimed.
  final int? timeLimitMinutes;
  final bool shuffleOptions;

  int? get timeLimitSeconds =>
      timeLimitMinutes == null ? null : timeLimitMinutes! * 60;

  @override
  bool operator ==(Object other) =>
      other is ExamConfig &&
      other.questionCount == questionCount &&
      other.timeLimitMinutes == timeLimitMinutes &&
      other.shuffleOptions == shuffleOptions;

  @override
  int get hashCode =>
      Object.hash(questionCount, timeLimitMinutes, shuffleOptions);
}

/// Hand-off of an exam configured on the quiz screen (setup dialog) to the
/// play screen, keyed by quiz id. The play screen shows its own setup when
/// nothing is pending (deep link, reload).
final pendingExamConfigProvider =
    NotifierProvider<PendingExamConfigs, Map<String, ExamConfig>>(
      PendingExamConfigs.new,
    );

class PendingExamConfigs extends Notifier<Map<String, ExamConfig>> {
  @override
  Map<String, ExamConfig> build() => const {};

  void put(String quizId, ExamConfig config) =>
      state = {...state, quizId: config};

  void clear(String quizId) {
    if (!state.containsKey(quizId)) return;
    state = {...state}..remove(quizId);
  }
}

/// Mutable state of a running exam (UI calls `setState` after mutations):
/// free navigation, answers without feedback, flags. Selections are stored
/// as original option indices.
class ExamSession {
  ExamSession({
    required this.attempt,
    required List<Question> questions,
    bool shuffleOptions = false,
    Random? random,
  }) : items = buildPlayItems(
         questions,
         shuffleOptions: shuffleOptions,
         random: random,
       );

  /// The in-progress attempt (`mode: exam`, time limit, pool ids).
  final QuizAttempt attempt;
  final List<PlayItem> items;

  int index = 0;
  final Map<String, Set<int>> _selected = {};
  final Map<String, String> _texts = {};
  final Set<String> _flagged = {};

  int get length => items.length;
  PlayItem get current => items[index];
  bool get isFirst => index == 0;
  bool get isLast => index >= items.length - 1;
  List<Question> get questions => [for (final i in items) i.question];

  Set<int> selectedFor(String id) => _selected[id] ?? const {};
  String textFor(String id) => _texts[id] ?? '';
  bool isFlagged(String id) => _flagged.contains(id);

  bool isAnswered(String id) =>
      selectedFor(id).isNotEmpty || textFor(id).trim().isNotEmpty;

  int get answeredCount => items.where((i) => isAnswered(i.id)).length;
  int get unansweredCount => length - answeredCount;
  int get flaggedCount => _flagged.length;

  void goTo(int i) {
    if (i >= 0 && i < items.length) index = i;
  }

  void next() => goTo(index + 1);
  void previous() => goTo(index - 1);

  /// Toggles/sets the option shown at [displayIndex] of the current question.
  void toggleOption(int displayIndex) {
    final item = current;
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

  void toggleFlag() {
    final id = current.id;
    if (!_flagged.remove(id)) _flagged.add(id);
  }

  /// Answers given so far (no grades; graded by `completeExam`).
  List<QuestionAnswer> answers() => [
    for (final item in items)
      if (isAnswered(item.id))
        QuestionAnswer(
          questionId: item.id,
          selectedIndices: selectedFor(item.id).toList()..sort(),
          textAnswer: textFor(item.id).trim().isEmpty
              ? null
              : textFor(item.id).trim(),
        ),
  ];
}
