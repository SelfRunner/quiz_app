import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive_ce.dart';

import '../../../ai/ai_providers.dart';
import '../../../ai/ai_tools_service.dart';
import '../../../core/errors/app_exception.dart';
import '../../../data/data_providers.dart';
import '../../../data/local/hive_boxes.dart';
import '../../../data/models/question.dart';

/// "Grade short answers with AI" (quiz player setting, off by default).
///
/// Persisted per user in the device `prefs` box under
/// `quiz.ai_grade_short_answers.<userId>`; kept in memory only when the box
/// is not open (tests) or nobody is signed in. Only takes effect while AI
/// is ready (see [aiGradingActiveProvider]).
final aiGradeShortAnswersProvider =
    NotifierProvider<AiGradeShortAnswersSetting, bool>(
      AiGradeShortAnswersSetting.new,
    );

class AiGradeShortAnswersSetting extends Notifier<bool> {
  static String prefsKeyFor(String userId) =>
      'quiz.ai_grade_short_answers.$userId';

  static Box<String>? get _prefs => Hive.isBoxOpen(HiveBoxes.prefs)
      ? Hive.box<String>(HiveBoxes.prefs)
      : null;

  String? _userId;

  @override
  bool build() {
    _userId = ref.watch(currentUserIdProvider);
    final id = _userId;
    if (id == null) return false;
    return _prefs?.get(prefsKeyFor(id)) == 'true';
  }

  void set(bool enabled) {
    state = enabled;
    final id = _userId;
    if (id != null) {
      _prefs?.put(prefsKeyFor(id), enabled ? 'true' : 'false').ignore();
    }
  }
}

/// True when short answers are graded with AI: the setting is on and AI is
/// configured.
final aiGradingActiveProvider = Provider<bool>(
  (ref) =>
      ref.watch(aiGradeShortAnswersProvider) &&
      (ref.watch(aiReadinessProvider).value?.isConfigured ?? false),
);

/// Whether [question] with the typed [answer] can be graded by AI: a short
/// answer with a model answer and a non-blank answer (blank ones stay
/// self-graded, e.g. flashcard use).
bool canAiGrade(Question question, String answer) =>
    question.type == QuestionType.shortAnswer &&
    (question.answerText?.trim().isNotEmpty ?? false) &&
    answer.trim().isNotEmpty;

/// How the user resolved an AI grade.
enum AiGradeDecision {
  /// Not decided yet (practice) / applied automatically (exam).
  pending,

  /// Took the AI verdict.
  accepted,

  /// Overrode: counted as right.
  markedRight,

  /// Overrode: counted as wrong.
  markedWrong,
}

/// AI grading of one short answer.
@immutable
class AiGradeState {
  const AiGradeState._({
    required this.loading,
    this.grade,
    this.error,
    this.skipped = false,
    this.decision = AiGradeDecision.pending,
  });

  const AiGradeState.loading() : this._(loading: true);

  const AiGradeState.done(ShortAnswerGrade grade)
    : this._(loading: false, grade: grade);

  const AiGradeState.failed(String error)
    : this._(loading: false, error: error);

  /// The user chose to grade themselves while the AI was working.
  const AiGradeState.skipped() : this._(loading: false, skipped: true);

  final bool loading;
  final ShortAnswerGrade? grade;
  final String? error;
  final bool skipped;
  final AiGradeDecision decision;

  /// Falls back to self-grading (error or skipped).
  bool get fallBack => error != null || skipped;

  bool get hasVerdict => grade != null;

  AiGradeState decide(AiGradeDecision decision) => AiGradeState._(
    loading: loading,
    grade: grade,
    error: error,
    skipped: skipped,
    decision: decision,
  );
}

/// Credit of a verdict: correct 1, partial 0.5, incorrect 0.
double verdictCredit(GradeVerdict verdict) => switch (verdict) {
  GradeVerdict.correct => 1,
  GradeVerdict.partial => 0.5,
  GradeVerdict.incorrect => 0,
};

/// Grades one short answer; never throws (errors become
/// [AiGradeState.failed]).
Future<AiGradeState> gradeShortAnswerSafely(
  AiToolsService tools,
  Question question,
  String answer,
) async {
  try {
    final grade = await tools.gradeShortAnswer(
      question.prompt,
      question.answerText ?? '',
      answer.trim(),
    );
    return AiGradeState.done(grade);
  } on Object catch (e) {
    return AiGradeState.failed(aiGradeErrorText(e));
  }
}

/// Message for a failed AI grade.
String aiGradeErrorText(Object error) =>
    error is AppException ? error.message : 'Something went wrong.';

/// Grades [items] (question + typed answer) with at most [concurrency]
/// requests at a time, reporting each result as it arrives.
Future<void> gradeShortAnswersBatch(
  AiToolsService tools,
  List<({Question question, String answer})> items, {
  required void Function(String questionId, AiGradeState state) onResult,
  int concurrency = 3,
  bool Function()? isCancelled,
}) async {
  var next = 0;
  Future<void> worker() async {
    while (next < items.length) {
      if (isCancelled?.call() ?? false) return;
      final item = items[next++];
      final state = await gradeShortAnswerSafely(
        tools,
        item.question,
        item.answer,
      );
      if (isCancelled?.call() ?? false) return;
      onResult(item.question.id, state);
    }
  }

  await Future.wait([
    for (var i = 0; i < concurrency.clamp(1, max(1, items.length)); i++)
      worker(),
  ]);
}
