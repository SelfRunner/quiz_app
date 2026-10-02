import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/data_providers.dart';
import '../../../data/models/question.dart';
import '../../../data/models/quiz_attempt.dart';
import '../../../data/repositories/mistake_repository.dart';
import '../application/attempt_recording.dart';
import '../domain/quiz_session.dart';
import '../widgets/practice_player.dart';
import '../widgets/quiz_format.dart';

/// Where a question of a combined session comes from.
typedef MistakeOrigin = ({String quizId, String questionId});

/// A combined practice session over the open mistakes of several quizzes
/// ("Practice all"). Questions get session-unique ids (question ids are only
/// unique within a quiz); on completion one `mistakes`-mode attempt is saved
/// per quiz and every graded answer is recorded in the Mistakes set.
///
/// Push it with `Navigator.push` (no route); [groups] is a snapshot so the
/// set does not change under the player.
class MistakesPracticeScreen extends ConsumerStatefulWidget {
  const MistakesPracticeScreen({super.key, required this.groups});

  final List<MistakeGroup> groups;

  @override
  ConsumerState<MistakesPracticeScreen> createState() =>
      _MistakesPracticeScreenState();
}

class _MistakesPracticeScreenState
    extends ConsumerState<MistakesPracticeScreen> {
  late final Map<String, MistakeOrigin> _origins;
  late final List<Question> _questions;

  @override
  void initState() {
    super.initState();
    final (questions, origins) = combineMistakeGroups(widget.groups);
    _questions = questions;
    _origins = origins;
  }

  Future<void> _save(QuizSession session, DateTime completedAt) async {
    final attempts = ref.read(attemptRepositoryProvider);
    final mistakes = ref.read(mistakeRepositoryProvider);
    final byQuiz = splitAnswersByQuiz(session.answers(), _origins);
    final total = session.length;
    final duration = session.durationSecondsAt(completedAt);
    for (final MapEntry(key: quizId, value: answers) in byQuiz.entries) {
      final started = await attempts.start(
        quizId: quizId,
        total: answers.length,
        mode: AttemptMode.mistakes,
        questionIds: [for (final a in answers) a.questionId],
      );
      final saved = await attempts.save(
        started.copyWith(
          answers: answers,
          score: answers.where((a) => a.isCorrect == true).length.toDouble(),
          total: answers.length,
          startedAt: session.startedAt,
          completedAt: completedAt,
          // The session's time, shared by question count.
          durationSeconds: total == 0
              ? 0
              : max(0, (duration * answers.length / total).round()),
        ),
      );
      await recordAttemptMistakes(mistakes, saved);
    }
  }

  Future<void> _practiceRound(QuizSession session, DateTime _) async {
    final mistakes = ref.read(mistakeRepositoryProvider);
    final byQuiz = splitAnswersByQuiz(session.gradedAnswers(), _origins);
    for (final MapEntry(key: quizId, value: answers) in byQuiz.entries) {
      await recordAnswers(mistakes, quizId, answers);
    }
  }

  @override
  Widget build(BuildContext context) {
    final quizCount = widget.groups.where((g) => g.entries.isNotEmpty).length;
    return PracticePlayer(
      title: 'All mistakes',
      heading: 'Practise all mistakes',
      subheading:
          'From ${plural(quizCount, 'quiz', 'quizzes')} · answer each '
          'correctly twice in a row to clear it',
      icon: Icons.replay_circle_filled_outlined,
      questions: _questions,
      emptyMessage: 'No open mistakes. Nice work!',
      onSave: _save,
      onPracticeRound: _practiceRound,
      onClose: () => Navigator.of(context).maybePop(),
    );
  }
}

/// Questions of [groups] in order, re-keyed with session-unique ids, and the
/// map back to their quiz and original question id.
(List<Question>, Map<String, MistakeOrigin>) combineMistakeGroups(
  List<MistakeGroup> groups,
) {
  final questions = <Question>[];
  final origins = <String, MistakeOrigin>{};
  for (final g in groups) {
    for (final q in g.questions) {
      final id = 'm${questions.length}';
      origins[id] = (quizId: g.quiz.id, questionId: q.id);
      questions.add(q.copyWith(id: id));
    }
  }
  return (questions, origins);
}

/// [answers] with session ids mapped back, grouped by quiz (first-seen
/// order).
Map<String, List<QuestionAnswer>> splitAnswersByQuiz(
  Iterable<QuestionAnswer> answers,
  Map<String, MistakeOrigin> origins,
) {
  final out = <String, List<QuestionAnswer>>{};
  for (final a in answers) {
    final origin = origins[a.questionId];
    if (origin == null) continue;
    (out[origin.quizId] ??= []).add(a.copyWith(questionId: origin.questionId));
  }
  return out;
}
