import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ai/ai_providers.dart';
import '../../../ai/ai_tools_service.dart';
import '../../../core/providers.dart';
import '../../../core/widgets/design_system.dart' hide MaxWidth;
import '../../../data/data_providers.dart';
import '../../../data/models/question.dart';
import '../../../data/models/quiz.dart';
import '../../../data/models/quiz_attempt.dart';
import '../../../study/exam.dart';
import '../application/ai_grading.dart';
import '../application/attempt_recording.dart';
import '../domain/exam_session.dart';
import 'exam_results_view.dart';
import 'exam_setup.dart';
import 'practice_player.dart';
import 'practice_question_view.dart';
import 'quiz_format.dart';
import 'quiz_results_view.dart';

enum _Phase { setup, starting, playing, results }

/// Time left at which the timer turns red and a warning is shown.
const Duration examWarningThreshold = Duration(minutes: 1);

/// Exam mode: random question pool, optional countdown (auto-submit at 0),
/// free navigation with a question grid and flags, no feedback until the
/// exam is submitted; then score, time used and a review.
class ExamPlayer extends ConsumerStatefulWidget {
  const ExamPlayer({
    super.key,
    required this.quiz,
    required this.onClose,
    this.config,
  });

  final Quiz quiz;

  /// Config from the setup dialog; null shows the setup page first.
  final ExamConfig? config;
  final VoidCallback onClose;

  @override
  ConsumerState<ExamPlayer> createState() => _ExamPlayerState();
}

class _ExamPlayerState extends ConsumerState<ExamPlayer> {
  late _Phase _phase = widget.config == null ? _Phase.setup : _Phase.starting;
  ExamConfig? _config = const ExamConfig();
  ExamConfig _lastConfig = const ExamConfig();
  String? _startError;

  ExamSession? _session;
  Timer? _ticker;
  bool _warned = false;
  bool _dialogOpen = false;

  QuizAttempt? _result;
  bool _autoSubmitted = false;
  bool _mistakesRecorded = false;
  SaveStatus _saveStatus = SaveStatus.idle;
  String? _saveError;

  /// AI grades of written answers (batch after submitting), by question id.
  final Map<String, AiGradeState> _aiGrades = {};

  /// Questions graded partly correct (half a point).
  final Set<String> _partial = {};

  /// Batch AI grading progress; null when not grading.
  ({int done, int total})? _gradingProgress;

  final _answer = TextEditingController();
  final _focus = FocusNode(debugLabel: 'exam');

  @override
  void initState() {
    super.initState();
    final config = widget.config;
    if (config != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _begin(config);
      });
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _answer.dispose();
    _focus.dispose();
    super.dispose();
  }

  DateTime _now() => ref.read(clockProvider)();

  // -------------------------------------------------------------------------
  // Lifecycle
  // -------------------------------------------------------------------------

  Future<void> _begin(ExamConfig config) async {
    setState(() {
      _phase = _Phase.starting;
      _startError = null;
      _lastConfig = config;
    });
    try {
      final random = Random(_now().microsecondsSinceEpoch);
      final pool = selectQuestionPool(
        widget.quiz.questions,
        count: config.questionCount,
        random: random,
      );
      if (pool.isEmpty) throw StateError('empty');
      final attempt = await ref
          .read(attemptRepositoryProvider)
          .start(
            quizId: widget.quiz.id,
            total: pool.length,
            mode: AttemptMode.exam,
            timeLimitSeconds: config.timeLimitSeconds,
            questionIds: [for (final q in pool) q.id],
          );
      if (!mounted) return;
      setState(() {
        _session = ExamSession(
          attempt: attempt,
          questions: pool,
          shuffleOptions: config.shuffleOptions,
          random: random,
        );
        _warned = false;
        _result = null;
        _autoSubmitted = false;
        _mistakesRecorded = false;
        _saveStatus = SaveStatus.idle;
        _saveError = null;
        _aiGrades.clear();
        _partial.clear();
        _gradingProgress = null;
        _phase = _Phase.playing;
      });
      _answer.clear();
      _ticker?.cancel();
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
      _focus.requestFocus();
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.setup;
        _config = config;
        _startError = e is StateError
            ? 'This quiz has no questions yet.'
            : errorText(e);
      });
    }
  }

  void _tick() {
    final s = _session;
    if (s == null || _phase != _Phase.playing) return;
    final left = examTimeRemaining(s.attempt, _now());
    if (left != null) {
      if (left <= Duration.zero) {
        _submit(auto: true);
        return;
      }
      final limit = s.attempt.timeLimitSeconds ?? 0;
      if (!_warned &&
          left <= examWarningThreshold &&
          limit > examWarningThreshold.inSeconds) {
        _warned = true;
        showSnack(context, '1 minute left');
      }
    }
    setState(() {});
  }

  Future<void> _confirmSubmit() async {
    final s = _session;
    if (s == null || _phase != _Phase.playing) return;
    final unanswered = s.unansweredCount;
    final flagged = s.flaggedCount;
    _dialogOpen = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Submit exam?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              unanswered == 0
                  ? 'All questions are answered.'
                  : '$unanswered of ${s.length} questions unanswered. '
                        'Unanswered questions count as wrong.',
              key: const Key('submit-summary'),
            ),
            if (flagged > 0) ...[
              Gaps.h8,
              Text('${plural(flagged, 'question')} flagged for review.'),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep working'),
          ),
          FilledButton(
            key: const Key('confirm-submit'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    _dialogOpen = false;
    if (ok == true && mounted) await _submit();
  }

  Future<void> _submit({bool auto = false}) async {
    final s = _session;
    if (s == null || _phase != _Phase.playing) return;
    _ticker?.cancel();
    if (_dialogOpen) {
      _dialogOpen = false;
      Navigator.of(context, rootNavigator: true).pop();
    }
    final completed = completeExam(
      s.attempt,
      questions: s.questions,
      answers: s.answers(),
      now: _now(),
    );
    setState(() {
      _result = completed;
      _autoSubmitted = auto;
      _phase = _Phase.results;
    });
    await _saveResult();
    if (mounted && ref.read(aiGradingActiveProvider)) await _gradeWithAi(s);
  }

  /// Score with partial credit: correct answers + half a point for each
  /// partly correct one.
  double _creditOf(List<Question> questions, List<QuestionAnswer> answers) {
    final scored = scoreExam(questions, answers);
    final partial = scored.answers
        .where((a) => a.isCorrect == false && _partial.contains(a.questionId))
        .length;
    return scored.score.correct + partial * 0.5;
  }

  /// Sets the grade of a written answer in the result (score updated).
  void _applyGrade(String questionId, bool correct, {bool partial = false}) {
    final r = _result;
    final s = _session;
    if (r == null || s == null) return;
    if (partial && !correct) {
      _partial.add(questionId);
    } else {
      _partial.remove(questionId);
    }
    final answers = [
      for (final a in r.answers)
        a.questionId == questionId ? a.copyWith(isCorrect: correct) : a,
    ];
    final scored = scoreExam(s.questions, answers);
    _result = r.copyWith(
      answers: scored.answers,
      score: _creditOf(s.questions, scored.answers),
    );
  }

  /// Grades every written answer with AI (a few requests at a time), shows
  /// progress, then saves once. Failed ones stay for self-grading.
  Future<void> _gradeWithAi(ExamSession session) async {
    final r = _result;
    if (r == null) return;
    final byId = {for (final a in r.answers) a.questionId: a};
    final items = <({Question question, String answer})>[
      for (final q in session.questions)
        if (byId[q.id] case final a?
            when a.isCorrect == null && canAiGrade(q, a.textAnswer ?? ''))
          (question: q, answer: a.textAnswer!),
    ];
    if (items.isEmpty) return;
    setState(() {
      for (final i in items) {
        _aiGrades[i.question.id] = const AiGradeState.loading();
      }
      _gradingProgress = (done: 0, total: items.length);
    });
    final applied = <QuestionAnswer>[];
    bool cancelled() => !mounted || !identical(_session, session);
    await gradeShortAnswersBatch(
      ref.read(aiToolsServiceProvider),
      items,
      isCancelled: cancelled,
      onResult: (id, state) => setState(() {
        final p = _gradingProgress;
        if (p != null) _gradingProgress = (done: p.done + 1, total: p.total);
        final previous = _aiGrades[id];
        if (previous == null || !previous.loading) return; // self-graded
        _aiGrades[id] = state;
        final grade = state.grade;
        if (grade == null) return;
        final correct = grade.verdict == GradeVerdict.correct;
        _applyGrade(
          id,
          correct,
          partial: grade.verdict == GradeVerdict.partial,
        );
        applied.add(QuestionAnswer(questionId: id, isCorrect: correct));
      }),
    );
    if (cancelled()) return;
    setState(() => _gradingProgress = null);
    if (applied.isEmpty) return;
    final alreadyRecorded = _mistakesRecorded;
    await _saveResult();
    if (alreadyRecorded) {
      await recordAnswers(
        ref.read(mistakeRepositoryProvider),
        session.attempt.quizId,
        applied,
      );
    }
  }

  Future<void> _saveResult() async {
    final result = _result;
    if (result == null) return;
    setState(() {
      _saveStatus = SaveStatus.saving;
      _saveError = null;
    });
    try {
      final saved = await ref.read(attemptRepositoryProvider).save(result);
      if (!_mistakesRecorded) {
        _mistakesRecorded = true;
        await recordAttemptMistakes(ref.read(mistakeRepositoryProvider), saved);
      }
      if (mounted) setState(() => _saveStatus = SaveStatus.saved);
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _saveStatus = SaveStatus.failed;
          _saveError = errorText(e);
        });
      }
    }
  }

  /// Self-grade, or an override of the AI grade.
  Future<void> _selfGrade(String questionId, bool correct) async {
    final r = _result;
    final s = _session;
    if (r == null || s == null) return;
    final alreadyRecorded = _mistakesRecorded;
    setState(() {
      final ai = _aiGrades[questionId];
      if (ai != null) {
        _aiGrades[questionId] = ai.loading
            ? const AiGradeState.skipped()
            : ai.decide(
                correct
                    ? AiGradeDecision.markedRight
                    : AiGradeDecision.markedWrong,
              );
      }
      _applyGrade(questionId, correct);
    });
    await _saveResult();
    if (alreadyRecorded) {
      await recordAnswers(ref.read(mistakeRepositoryProvider), r.quizId, [
        QuestionAnswer(questionId: questionId, isCorrect: correct),
      ]);
    }
  }

  Future<void> _confirmQuit() async {
    _dialogOpen = true;
    final quit = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Quit this exam?'),
        content: const Text('Your answers will be discarded.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep working'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Quit'),
          ),
        ],
      ),
    );
    _dialogOpen = false;
    if (quit != true || !mounted || _phase != _Phase.playing) return;
    _ticker?.cancel();
    final attempt = _session?.attempt;
    setState(() => _phase = _Phase.setup);
    if (attempt != null) {
      unawaited(
        ref
            .read(attemptRepositoryProvider)
            .delete(attempt.id)
            .catchError((Object _) {}),
      );
    }
    widget.onClose();
  }

  // -------------------------------------------------------------------------
  // Navigation & answers
  // -------------------------------------------------------------------------

  void _goTo(int index) {
    final s = _session;
    if (s == null) return;
    setState(() => s.goTo(index));
    _answer.text = s.textFor(s.current.id);
    _focus.requestFocus();
  }

  void _toggle(int displayIndex) {
    final s = _session;
    if (s == null) return;
    setState(() => s.toggleOption(displayIndex));
  }

  void _toggleFlag() {
    final s = _session;
    if (s == null) return;
    setState(s.toggleFlag);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || _phase != _Phase.playing) {
      return KeyEventResult.ignored;
    }
    final s = _session;
    if (s == null) return KeyEventResult.ignored;
    final inText =
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<EditableText>() !=
        null;
    if (inText) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowRight) {
      _goTo(s.index + 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      _goTo(s.index - 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyF) {
      _toggleFlag();
      return KeyEventResult.handled;
    }
    final item = s.current;
    if (item.question.type.hasOptions) {
      final digit = digitOfKey(key);
      if (digit != null && digit <= item.optionOrder.length) {
        _toggle(digit - 1);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  Future<void> _openGrid() async {
    final s = _session;
    if (s == null) return;
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Insets.lg,
            0,
            Insets.lg,
            Insets.lg,
          ),
          child: _QuestionGrid(
            session: s,
            onSelect: (i) => Navigator.of(context).pop(i),
          ),
        ),
      ),
    );
    if (picked != null && mounted) _goTo(picked);
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final s = _session;
    final playing = _phase == _Phase.playing && s != null;
    final Widget body = switch (_phase) {
      _Phase.setup => _ExamSetupPage(
        quiz: widget.quiz,
        initial: _lastConfig,
        error: _startError,
        onChanged: (c) => setState(() => _config = c),
        onStart: _config == null ? null : () => _begin(_config!),
      ),
      _Phase.starting => const Center(
        child: SizedBox.square(
          dimension: 28,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      ),
      _Phase.playing => Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: _ExamBody(
          session: s!,
          answer: _answer,
          onToggle: _toggle,
          onTextChanged: s.setText,
          onAnswered: () => setState(() {}),
          onFlag: _toggleFlag,
          onGoTo: _goTo,
          onOpenGrid: _openGrid,
          onSubmit: _confirmSubmit,
        ),
      ),
      _Phase.results => ExamResultsView(
        attempt: _result!,
        questions: s!.questions,
        flagged: {
          for (final i in s.items)
            if (s.isFlagged(i.id)) i.id,
        },
        autoSubmitted: _autoSubmitted,
        saveStatus: _saveStatus,
        saveError: _saveError,
        onRetrySave: _saveResult,
        onSelfGrade: _selfGrade,
        quiz: widget.quiz,
        aiGrades: _aiGrades,
        partialIds: _partial,
        gradingProgress: _gradingProgress,
        onNewExam: () => setState(() {
          _config = _lastConfig;
          _phase = _Phase.setup;
        }),
        onDone: widget.onClose,
      ),
    };

    return PlayScaffold(
      title: widget.quiz.title,
      canPop: !playing,
      onClose: () => playing ? _confirmQuit() : widget.onClose(),
      onBlockedPop: _confirmQuit,
      actions: [
        if (playing) ...[
          _TimerChip(attempt: s.attempt, now: _now()),
          Gaps.w8,
          Padding(
            padding: const EdgeInsets.only(right: Insets.md),
            child: FilledButton(
              key: const Key('exam-submit'),
              onPressed: _confirmSubmit,
              child: const Text('Submit'),
            ),
          ),
        ],
      ],
      body: body,
    );
  }
}

// ---------------------------------------------------------------------------
// Setup page (deep link / "New exam")
// ---------------------------------------------------------------------------

class _ExamSetupPage extends StatelessWidget {
  const _ExamSetupPage({
    required this.quiz,
    required this.initial,
    required this.onChanged,
    required this.onStart,
    this.error,
  });

  final Quiz quiz;
  final ExamConfig initial;
  final ValueChanged<ExamConfig?> onChanged;
  final VoidCallback? onStart;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final wide = Breakpoints.isMedium(context);
    final count = quiz.questions.length;
    return SingleChildScrollView(
      child: ContentContainer(
        maxWidth: ContentWidth.form,
        padding: wide ? Insets.pageWide : Insets.page,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Gaps.h24,
            Icon(Icons.timer_outlined, size: 32, color: colors.faintText),
            Gaps.h16,
            Text(
              'Exam',
              style: theme.textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
            Gaps.h4,
            Text(
              quiz.title,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: colors.mutedText,
              ),
              textAlign: TextAlign.center,
            ),
            Gaps.h32,
            if (count == 0)
              const EmptyState(
                compact: true,
                icon: Icons.quiz_outlined,
                title: 'This quiz has no questions yet.',
              )
            else ...[
              AppCard(
                child: ExamSetupForm(
                  total: count,
                  initial: initial,
                  onChanged: onChanged,
                ),
              ),
              if (error != null) ...[
                Gaps.h12,
                InfoBanner(kind: InfoBannerKind.error, message: error!),
              ],
              Gaps.h24,
              FilledButton.icon(
                key: const Key('start-exam'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: onStart,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Start exam'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Playing
// ---------------------------------------------------------------------------

class _TimerChip extends StatelessWidget {
  const _TimerChip({required this.attempt, required this.now});

  final QuizAttempt attempt;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final left = examTimeRemaining(attempt, now);
    final timed = left != null;
    final shown = left ?? now.difference(attempt.startedAt);
    final urgent = timed && left <= examWarningThreshold;
    final color = urgent ? colors.danger : colors.mutedText;
    return Tooltip(
      message: timed ? 'Time left' : 'Time spent',
      child: Container(
        key: const Key('exam-timer'),
        padding: const EdgeInsets.symmetric(
          horizontal: Insets.sm,
          vertical: Insets.xs,
        ),
        decoration: BoxDecoration(
          color: urgent ? colors.dangerContainer : null,
          borderRadius: Radii.mdAll,
          border: Border.all(color: urgent ? colors.danger : colors.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              timed ? Icons.timer_outlined : Icons.schedule,
              size: 16,
              color: color,
            ),
            Gaps.w4,
            Text(
              formatClock(shown),
              style: theme.textTheme.labelLarge?.copyWith(
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExamBody extends StatelessWidget {
  const _ExamBody({
    required this.session,
    required this.answer,
    required this.onToggle,
    required this.onTextChanged,
    required this.onAnswered,
    required this.onFlag,
    required this.onGoTo,
    required this.onOpenGrid,
    required this.onSubmit,
  });

  final ExamSession session;
  final TextEditingController answer;
  final ValueChanged<int> onToggle;
  final ValueChanged<String> onTextChanged;
  final VoidCallback onAnswered;
  final VoidCallback onFlag;
  final ValueChanged<int> onGoTo;
  final VoidCallback onOpenGrid;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final s = session;
    final medium = Breakpoints.isMedium(context);
    final sidePanel = MediaQuery.sizeOf(context).width >= Breakpoints.expanded;

    final question = SingleChildScrollView(
      child: ContentContainer(
        padding: EdgeInsets.fromLTRB(
          Breakpoints.gutter(context),
          medium ? Insets.xl : Insets.lg,
          Breakpoints.gutter(context),
          Insets.xl,
        ),
        child: _ExamQuestion(
          session: s,
          answer: answer,
          showKeys: medium,
          onToggle: onToggle,
          onTextChanged: (t) {
            final was = s.isAnswered(s.current.id);
            onTextChanged(t);
            if (was != s.isAnswered(s.current.id)) onAnswered();
          },
          onFlag: onFlag,
        ),
      ),
    );

    final bar = DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: colors.hairline)),
      ),
      child: ContentContainer(
        padding: EdgeInsets.symmetric(
          horizontal: Breakpoints.gutter(context),
          vertical: Insets.md,
        ),
        child: Row(
          children: [
            OutlinedButton.icon(
              key: const Key('exam-prev'),
              onPressed: s.isFirst ? null : () => onGoTo(s.index - 1),
              icon: const Icon(Icons.chevron_left, size: 18),
              label: const Text('Previous'),
            ),
            const Spacer(),
            if (!sidePanel)
              TextButton.icon(
                key: const Key('exam-grid-button'),
                onPressed: onOpenGrid,
                icon: const Icon(Icons.grid_view_rounded, size: 18),
                label: Text('${s.index + 1} / ${s.length}'),
              ),
            const Spacer(),
            if (s.isLast)
              FilledButton.tonal(
                key: const Key('exam-finish'),
                onPressed: onSubmit,
                child: const Text('Finish'),
              )
            else
              FilledButton.tonalIcon(
                key: const Key('exam-next'),
                onPressed: () => onGoTo(s.index + 1),
                iconAlignment: IconAlignment.end,
                icon: const Icon(Icons.chevron_right, size: 18),
                label: const Text('Next'),
              ),
          ],
        ),
      ),
    );

    return Column(
      children: [
        LinearProgressIndicator(
          key: const Key('exam-progress'),
          value: s.length == 0 ? 0 : s.answeredCount / s.length,
          minHeight: 2,
          color: theme.colorScheme.primary,
          backgroundColor: colors.hairline,
        ),
        Expanded(
          child: sidePanel
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: question),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border(
                          left: BorderSide(color: colors.hairline),
                        ),
                      ),
                      child: SizedBox(
                        width: 280,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(Insets.lg),
                          child: _QuestionGrid(session: s, onSelect: onGoTo),
                        ),
                      ),
                    ),
                  ],
                )
              : question,
        ),
        bar,
      ],
    );
  }
}

class _ExamQuestion extends StatelessWidget {
  const _ExamQuestion({
    required this.session,
    required this.answer,
    required this.showKeys,
    required this.onToggle,
    required this.onTextChanged,
    required this.onFlag,
  });

  final ExamSession session;
  final TextEditingController answer;
  final bool showKeys;
  final ValueChanged<int> onToggle;
  final ValueChanged<String> onTextChanged;
  final VoidCallback onFlag;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final s = session;
    final item = s.current;
    final q = item.question;
    final flagged = s.isFlagged(item.id);
    final mono = theme.textTheme.labelMedium?.copyWith(
      color: colors.mutedText,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('Question ${s.index + 1} of ${s.length}', style: mono),
            const Spacer(),
            TextButton.icon(
              key: const Key('exam-flag'),
              style: TextButton.styleFrom(
                foregroundColor: flagged ? colors.warning : colors.mutedText,
              ),
              onPressed: onFlag,
              icon: Icon(flagged ? Icons.flag : Icons.outlined_flag, size: 18),
              label: Text(flagged ? 'Flagged' : 'Flag for review'),
            ),
          ],
        ),
        SizedBox(height: showKeys ? Insets.xl : Insets.lg),
        Text(
          questionHint(q.type, exam: true),
          style: theme.textTheme.labelMedium?.copyWith(color: colors.faintText),
        ),
        Gaps.h8,
        Text(
          q.prompt,
          style:
              (showKeys
                      ? theme.textTheme.headlineMedium
                      : theme.textTheme.headlineSmall)
                  ?.copyWith(height: 1.4),
        ),
        Gaps.h24,
        if (q.type.hasOptions)
          for (var d = 0; d < item.optionOrder.length; d++)
            Padding(
              padding: const EdgeInsets.only(bottom: Insets.sm),
              child: AnswerOptionTile(
                key: Key('option-$d'),
                number: d + 1,
                text: q.options[item.optionOrder[d]],
                multi: q.type == QuestionType.mcqMulti,
                selected: s.selectedFor(item.id).contains(item.optionOrder[d]),
                checked: false,
                correct: false,
                showKey: showKeys,
                onTap: () => onToggle(d),
              ),
            )
        else
          TextField(
            key: const Key('exam-short-answer'),
            controller: answer,
            minLines: 2,
            maxLines: 6,
            style: theme.textTheme.bodyLarge,
            decoration: const InputDecoration(labelText: 'Your answer'),
            onChanged: onTextChanged,
          ),
        if (showKeys) ...[
          Gaps.h16,
          Wrap(
            spacing: Insets.lg,
            runSpacing: Insets.xs,
            children: [
              if (q.type.hasOptions)
                const KeyboardShortcutHint(keys: ['1–9'], label: 'Pick'),
              const KeyboardShortcutHint(keys: ['←', '→'], label: 'Move'),
              const KeyboardShortcutHint(keys: ['F'], label: 'Flag'),
            ],
          ),
        ],
      ],
    );
  }
}

/// Numbered cells (answered = filled, flagged = flag mark, current =
/// outlined) to jump between questions.
class _QuestionGrid extends StatelessWidget {
  const _QuestionGrid({required this.session, required this.onSelect});

  final ExamSession session;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final s = session;
    final small = theme.textTheme.bodySmall?.copyWith(color: colors.mutedText);

    Widget legend(Widget mark, String text) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        Gaps.w4,
        Text(text, style: small),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Questions', style: theme.textTheme.titleSmall),
        Gaps.h12,
        Wrap(
          spacing: Insets.sm,
          runSpacing: Insets.sm,
          children: [
            for (var i = 0; i < s.length; i++)
              _GridCell(
                key: Key('exam-cell-$i'),
                number: i + 1,
                current: i == s.index,
                answered: s.isAnswered(s.items[i].id),
                flagged: s.isFlagged(s.items[i].id),
                onTap: () => onSelect(i),
              ),
          ],
        ),
        Gaps.h16,
        Wrap(
          spacing: Insets.md,
          runSpacing: Insets.xs,
          children: [
            legend(
              _Swatch(color: colors.pressed),
              'Answered ${s.answeredCount}',
            ),
            legend(
              Icon(Icons.flag, size: 12, color: colors.warning),
              'Flagged ${s.flaggedCount}',
            ),
            legend(
              _Swatch(color: colors.card, border: colors.border),
              'Unanswered ${s.unansweredCount}',
            ),
          ],
        ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, this.border});

  final Color color;
  final Color? border;

  @override
  Widget build(BuildContext context) => Container(
    width: 12,
    height: 12,
    decoration: BoxDecoration(
      color: color,
      borderRadius: Radii.xsAll,
      border: border == null ? null : Border.all(color: border!),
    ),
  );
}

class _GridCell extends StatelessWidget {
  const _GridCell({
    super.key,
    required this.number,
    required this.current,
    required this.answered,
    required this.flagged,
    required this.onTap,
  });

  final int number;
  final bool current;
  final bool answered;
  final bool flagged;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final state = [
      answered ? 'answered' : 'unanswered',
      if (flagged) 'flagged',
      if (current) 'current',
    ].join(', ');
    return Semantics(
      button: true,
      label: 'Question $number, $state',
      excludeSemantics: true,
      child: Material(
        color: answered ? colors.pressed : colors.card,
        shape: RoundedRectangleBorder(
          borderRadius: Radii.mdAll,
          side: BorderSide(
            color: current ? theme.colorScheme.onSurface : colors.border,
            width: current ? 1.5 : 1,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: Radii.mdAll,
          child: SizedBox.square(
            dimension: 40,
            child: Stack(
              children: [
                Center(
                  child: Text(
                    '$number',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                if (flagged)
                  Positioned(
                    top: 2,
                    right: 2,
                    child: Icon(Icons.flag, size: 11, color: colors.warning),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
