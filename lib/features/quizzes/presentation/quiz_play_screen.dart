import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/widgets/design_system.dart' hide MaxWidth;
import '../../../data/data_providers.dart';
import '../../../data/models/quiz_attempt.dart';
import '../application/attempt_recording.dart';
import '../domain/exam_session.dart';
import '../widgets/exam_player.dart';
import '../widgets/practice_player.dart';
import '../widgets/quiz_format.dart';

/// Plays a quiz and saves a `QuizAttempt` owned by the player (also for
/// shared quizzes); graded answers feed the user's Mistakes set.
///
/// Modes (query `mode`): null/`practice` — feedback after each question;
/// `exam` — random pool, optional time limit, feedback at the end (see
/// [ExamPlayer]); `mistakes` — only the open mistakes of this quiz.
class QuizPlayScreen extends ConsumerStatefulWidget {
  const QuizPlayScreen({super.key, required this.quizId, this.mode});

  final String quizId;

  /// Query `mode`: null/'practice', 'exam' or 'mistakes'.
  final String? mode;

  @override
  ConsumerState<QuizPlayScreen> createState() => _QuizPlayScreenState();
}

class _QuizPlayScreenState extends ConsumerState<QuizPlayScreen> {
  ExamConfig? _examConfig;

  AttemptMode get _mode => switch (widget.mode) {
    'exam' => AttemptMode.exam,
    'mistakes' => AttemptMode.mistakes,
    _ => AttemptMode.practice,
  };

  @override
  void initState() {
    super.initState();
    if (_mode == AttemptMode.exam) {
      _examConfig = ref.read(pendingExamConfigProvider)[widget.quizId];
      if (_examConfig != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ref.read(pendingExamConfigProvider.notifier).clear(widget.quizId);
          }
        });
      }
    }
  }

  void _close() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.quiz(widget.quizId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final quizAsync = ref.watch(quizProvider(widget.quizId));
    final quiz = quizAsync.value;
    if (quiz == null) {
      return PlayScaffold(
        title: 'Play quiz',
        onClose: _close,
        body: quizAsync.hasValue
            ? const NotFoundView(what: 'Quiz')
            : quizAsync.hasError
            ? EmptyState(
                icon: Icons.error_outline,
                title: 'Could not load the quiz',
                message: errorText(quizAsync.error!),
              )
            : const _Loading(),
      );
    }

    switch (_mode) {
      case AttemptMode.exam:
        return ExamPlayer(quiz: quiz, config: _examConfig, onClose: _close);
      case AttemptMode.practice:
        return PracticePlayer(
          title: quiz.title,
          heading: quiz.title,
          questions: quiz.questions,
          onSave: (s, completedAt) => saveSessionAttempt(
            attempts: ref.read(attemptRepositoryProvider),
            mistakes: ref.read(mistakeRepositoryProvider),
            quizId: quiz.id,
            session: s,
            completedAt: completedAt,
          ),
          onPracticeRound: (s, _) => recordAnswers(
            ref.read(mistakeRepositoryProvider),
            quiz.id,
            s.gradedAnswers(),
          ),
          onClose: _close,
          quizFor: (_) => quiz,
        );
      case AttemptMode.mistakes:
        final groupsAsync = ref.watch(openMistakesProvider);
        final groups = groupsAsync.value;
        if (groups == null) {
          return PlayScaffold(
            title: quiz.title,
            onClose: _close,
            body: groupsAsync.hasError
                ? EmptyState(
                    icon: Icons.error_outline,
                    title: 'Could not load your mistakes',
                    message: errorText(groupsAsync.error!),
                  )
                : const _Loading(),
          );
        }
        final open = [
          for (final g in groups)
            if (g.quiz.id == quiz.id) ...g.questions,
        ];
        return PracticePlayer(
          title: quiz.title,
          heading: 'Practise mistakes',
          subheading:
              '${quiz.title} · answer each correctly twice in a row to '
              'clear it',
          icon: Icons.replay_circle_filled_outlined,
          questions: open,
          emptyMessage: 'No open mistakes in this quiz. Nice work!',
          onSave: (s, completedAt) => saveSessionAttempt(
            attempts: ref.read(attemptRepositoryProvider),
            mistakes: ref.read(mistakeRepositoryProvider),
            quizId: quiz.id,
            session: s,
            completedAt: completedAt,
            mode: AttemptMode.mistakes,
            questionIds: [for (final i in s.items) i.id],
          ),
          onPracticeRound: (s, _) => recordAnswers(
            ref.read(mistakeRepositoryProvider),
            quiz.id,
            s.gradedAnswers(),
          ),
          onClose: _close,
          quizFor: (_) => quiz,
        );
    }
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => const ContentContainer(
    maxWidth: ContentWidth.form,
    child: Padding(
      padding: EdgeInsets.only(top: Insets.xl),
      child: LoadingSkeleton(rows: 3, leading: false),
    ),
  );
}
