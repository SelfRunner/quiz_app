import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ai/ai_providers.dart';
import '../../../ai/ai_tools_service.dart';
import '../../../core/providers.dart';
import '../../../core/widgets/design_system.dart' hide MaxWidth;
import '../../../data/models/question.dart';
import '../../../data/models/quiz.dart';
import '../application/ai_grading.dart';
import '../domain/quiz_session.dart';
import 'ai_grading_widgets.dart';
import 'practice_question_view.dart';
import 'quiz_format.dart';
import 'quiz_results_view.dart';

/// Persists a finished run (throws to report a failed save).
typedef PracticeRunSaver = Future<void> Function(
  QuizSession session,
  DateTime completedAt,
);

enum _Phase { setup, playing, results }

/// A practice run with per-question feedback: options → one question per
/// page → results. Used for regular play, a quiz's mistakes and the
/// combined mistakes session. Owns its scaffold (close button, quit
/// confirmation).
class PracticePlayer extends ConsumerStatefulWidget {
  const PracticePlayer({
    super.key,
    required this.title,
    required this.heading,
    required this.questions,
    required this.onSave,
    required this.onPracticeRound,
    required this.onClose,
    this.subheading,
    this.icon = Icons.quiz_outlined,
    this.emptyMessage = 'This quiz has no questions yet.',
    this.quizFor,
  });

  /// App bar title.
  final String title;

  /// Setup page heading and optional line under the question count.
  final String heading;
  final String? subheading;
  final IconData icon;

  /// Questions to play (a later change is used by the next "Retry").
  final List<Question> questions;

  /// Saves a completed run to the attempt history.
  final PracticeRunSaver onSave;

  /// Records a "retry missed" round (not added to the history).
  final PracticeRunSaver onPracticeRound;
  final VoidCallback onClose;
  final String emptyMessage;

  /// The quiz a question belongs to ("Explain" uses its notes as context).
  final Quiz? Function(Question question)? quizFor;

  @override
  ConsumerState<PracticePlayer> createState() => _PracticePlayerState();
}

class _PracticePlayerState extends ConsumerState<PracticePlayer> {
  _Phase _phase = _Phase.setup;
  bool _shuffleQuestions = false;
  bool _shuffleOptions = false;
  QuizSession? _session;
  List<Question> _lastQuestions = const [];
  DateTime? _completedAt;
  SaveStatus _saveStatus = SaveStatus.idle;
  String? _saveError;
  final _answer = TextEditingController();
  final _focus = FocusNode(debugLabel: 'quiz-play');

  /// AI grades of short answers in the current run, by question id.
  final Map<String, AiGradeState> _aiGrades = {};

  @override
  void dispose() {
    _answer.dispose();
    _focus.dispose();
    super.dispose();
  }

  DateTime _now() => ref.read(clockProvider)();

  void _start(List<Question> questions, {bool practice = false}) {
    if (questions.isEmpty) return;
    if (!practice) _lastQuestions = questions;
    setState(() {
      _session = QuizSession(
        questions: questions,
        startedAt: _now(),
        shuffleQuestions: _shuffleQuestions,
        shuffleOptions: _shuffleOptions,
        isPractice: practice,
      );
      _answer.clear();
      _aiGrades.clear();
      _completedAt = null;
      _saveStatus = SaveStatus.idle;
      _saveError = null;
      _phase = _Phase.playing;
    });
    _focus.requestFocus();
  }

  void _update(void Function(QuizSession s) change) {
    final s = _session;
    if (s == null) return;
    setState(() => change(s));
  }

  void _primaryAction() {
    final s = _session;
    if (s == null || _phase != _Phase.playing) return;
    final item = s.current;
    if (!s.isChecked(item.id)) {
      if (item.question.type.hasOptions) {
        if (s.canCheck) _update((s) => s.check());
      } else if (!s.isRevealed(item.id)) {
        final text = s.textFor(item.id);
        final useAi =
            ref.read(aiGradingActiveProvider) &&
            canAiGrade(item.question, text);
        _update((s) => s.reveal());
        if (useAi) _gradeWithAi(s, item.question, text);
      } else if (_aiGrades[item.id]?.hasVerdict ?? false) {
        _acceptAiGrade();
      }
      return;
    }
    if (s.isLast) {
      _finish();
    } else {
      _update((s) => s.next());
      _answer.text = s.textFor(s.current.id);
      _focus.requestFocus();
    }
  }

  void _selfGrade(bool correct) {
    final s = _session;
    if (s == null) return;
    final id = s.current.id;
    final ai = _aiGrades[id];
    if (ai != null && ai.hasVerdict) {
      _aiGrades[id] = ai.decide(
        correct ? AiGradeDecision.markedRight : AiGradeDecision.markedWrong,
      );
    }
    _update((s) => s.selfGrade(correct: correct));
    _focus.requestFocus();
  }

  Future<void> _gradeWithAi(
    QuizSession session,
    Question question,
    String text,
  ) async {
    setState(() => _aiGrades[question.id] = const AiGradeState.loading());
    final result = await gradeShortAnswerSafely(
      ref.read(aiToolsServiceProvider),
      question,
      text,
    );
    if (!mounted || !identical(_session, session)) return;
    final current = _aiGrades[question.id];
    if (current == null || !current.loading) return; // skipped meanwhile
    setState(() => _aiGrades[question.id] = result);
  }

  void _acceptAiGrade() {
    final s = _session;
    if (s == null) return;
    final id = s.current.id;
    final grade = _aiGrades[id]?.grade;
    if (grade == null || s.isChecked(id)) return;
    _aiGrades[id] = _aiGrades[id]!.decide(AiGradeDecision.accepted);
    _update(
      (s) => s.selfGrade(
        correct: grade.verdict == GradeVerdict.correct,
        partial: grade.verdict == GradeVerdict.partial,
      ),
    );
    _focus.requestFocus();
  }

  void _skipAiGrade() {
    final s = _session;
    if (s == null) return;
    setState(() => _aiGrades[s.current.id] = const AiGradeState.skipped());
    _focus.requestFocus();
  }

  Future<void> _finish() async {
    setState(() {
      _completedAt = _now();
      _phase = _Phase.results;
    });
    await _saveAttempt();
  }

  Future<void> _saveAttempt() async {
    final s = _session;
    final completedAt = _completedAt;
    if (s == null || completedAt == null) return;
    if (s.isPractice) {
      setState(() => _saveStatus = SaveStatus.practice);
      await widget.onPracticeRound(s, completedAt);
      return;
    }
    setState(() {
      _saveStatus = SaveStatus.saving;
      _saveError = null;
    });
    try {
      await widget.onSave(s, completedAt);
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

  Future<void> _confirmQuit() async {
    final quit = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Quit this quiz?'),
        content: const Text('Your answers in this run will not be saved.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep playing'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Quit'),
          ),
        ],
      ),
    );
    if (quit != true || !mounted) return;
    setState(() => _phase = _Phase.setup);
    widget.onClose();
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
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (inText) return KeyEventResult.ignored;
      _primaryAction();
      return KeyEventResult.handled;
    }
    if (inText) return KeyEventResult.ignored;
    final item = s.current;
    if (item.question.type.hasOptions) {
      final digit = digitOfKey(key);
      if (digit != null && digit >= 1 && digit <= item.optionOrder.length) {
        _update((s) => s.toggleOption(digit - 1));
        return KeyEventResult.handled;
      }
    } else if (s.isRevealed(item.id) &&
        !s.isChecked(item.id) &&
        !(_aiGrades[item.id]?.loading ?? false)) {
      if (key == LogicalKeyboardKey.keyY) {
        _selfGrade(true);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyN) {
        _selfGrade(false);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final playing =
        _phase == _Phase.playing && (_session?.answeredCount ?? 0) > 0;
    final session = _session;
    final Widget body = switch (_phase) {
      _Phase.setup => _SetupView(
        heading: widget.heading,
        subheading: widget.subheading,
        icon: widget.icon,
        count: widget.questions.length,
        emptyMessage: widget.emptyMessage,
        shuffleQuestions: _shuffleQuestions,
        shuffleOptions: _shuffleOptions,
        onShuffleQuestions: (v) => setState(() => _shuffleQuestions = v),
        onShuffleOptions: (v) => setState(() => _shuffleOptions = v),
        onStart: () => _start(widget.questions),
      ),
      _Phase.playing => Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: PracticeQuestionView(
          session: session!,
          answer: _answer,
          onToggle: (i) => _update((s) => s.toggleOption(i)),
          onTextChanged: session.setText,
          onPrimary: _primaryAction,
          onSelfGrade: _selfGrade,
          aiGrade: _aiGrades[session.current.id],
          onAcceptAiGrade: _acceptAiGrade,
          onSkipAiGrade: _skipAiGrade,
          quiz: widget.quizFor?.call(session.current.question),
        ),
      ),
      _Phase.results => QuizResultsView(
        session: session!,
        duration: _completedAt!.difference(session.startedAt),
        saveStatus: _saveStatus,
        saveError: _saveError,
        onRetrySave: _saveAttempt,
        onRetry: () => _start(
          widget.questions.isNotEmpty ? widget.questions : _lastQuestions,
        ),
        onRetryMissed: session.missedQuestions.isEmpty
            ? null
            : () => _start(session.missedQuestions, practice: true),
        onDone: widget.onClose,
        quizFor: widget.quizFor,
      ),
    };

    return PlayScaffold(
      title: widget.title,
      canPop: !playing,
      onClose: () => playing ? _confirmQuit() : widget.onClose(),
      onBlockedPop: _confirmQuit,
      body: body,
    );
  }
}

/// Scaffold of the play screens: close button, muted title, pop guard.
class PlayScaffold extends StatelessWidget {
  const PlayScaffold({
    super.key,
    required this.title,
    required this.body,
    required this.onClose,
    this.canPop = true,
    this.onBlockedPop,
    this.actions = const [],
  });

  final String title;
  final Widget body;
  final VoidCallback onClose;
  final bool canPop;
  final VoidCallback? onBlockedPop;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) onBlockedPop?.call();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close),
            onPressed: onClose,
          ),
          title: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(color: colors.mutedText),
          ),
          actions: actions,
        ),
        body: SafeArea(child: body),
      ),
    );
  }
}

/// 1..9 for the digit / numpad keys, else null.
int? digitOfKey(LogicalKeyboardKey key) {
  const rows = [
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
    LogicalKeyboardKey.digit6,
    LogicalKeyboardKey.digit7,
    LogicalKeyboardKey.digit8,
    LogicalKeyboardKey.digit9,
  ];
  const pad = [
    LogicalKeyboardKey.numpad1,
    LogicalKeyboardKey.numpad2,
    LogicalKeyboardKey.numpad3,
    LogicalKeyboardKey.numpad4,
    LogicalKeyboardKey.numpad5,
    LogicalKeyboardKey.numpad6,
    LogicalKeyboardKey.numpad7,
    LogicalKeyboardKey.numpad8,
    LogicalKeyboardKey.numpad9,
  ];
  final r = rows.indexOf(key);
  if (r >= 0) return r + 1;
  final p = pad.indexOf(key);
  return p >= 0 ? p + 1 : null;
}

class _SetupView extends StatelessWidget {
  const _SetupView({
    required this.heading,
    required this.subheading,
    required this.icon,
    required this.count,
    required this.emptyMessage,
    required this.shuffleQuestions,
    required this.shuffleOptions,
    required this.onShuffleQuestions,
    required this.onShuffleOptions,
    required this.onStart,
  });

  final String heading;
  final String? subheading;
  final IconData icon;
  final int count;
  final String emptyMessage;
  final bool shuffleQuestions;
  final bool shuffleOptions;
  final ValueChanged<bool> onShuffleQuestions;
  final ValueChanged<bool> onShuffleOptions;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final wide = Breakpoints.isMedium(context);
    final muted = theme.textTheme.bodyLarge?.copyWith(color: colors.mutedText);
    return SingleChildScrollView(
      child: ContentContainer(
        maxWidth: ContentWidth.form,
        padding: wide ? Insets.pageWide : Insets.page,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Gaps.h24,
            Icon(icon, size: 32, color: colors.faintText),
            Gaps.h16,
            Text(
              heading,
              style: theme.textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
            Gaps.h4,
            Text(
              plural(count, 'question'),
              style: muted,
              textAlign: TextAlign.center,
            ),
            if (subheading != null) ...[
              Gaps.h4,
              Text(
                subheading!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.faintText,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            Gaps.h32,
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: Insets.xs),
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('Shuffle questions'),
                    value: shuffleQuestions,
                    onChanged: onShuffleQuestions,
                  ),
                  Divider(height: 1, color: colors.hairline),
                  SwitchListTile(
                    title: const Text('Shuffle answer options'),
                    value: shuffleOptions,
                    onChanged: onShuffleOptions,
                  ),
                  Divider(height: 1, color: colors.hairline),
                  const AiGradingSwitch(),
                ],
              ),
            ),
            Gaps.h24,
            FilledButton.icon(
              key: const Key('start-quiz'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: count == 0 ? null : onStart,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Start'),
            ),
            if (count == 0) ...[
              Gaps.h12,
              Text(
                emptyMessage,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.mutedText,
                ),
              ),
            ],
            if (wide) ...[
              Gaps.h24,
              const Wrap(
                alignment: WrapAlignment.center,
                spacing: Insets.lg,
                runSpacing: Insets.sm,
                children: [
                  KeyboardShortcutHint(keys: ['1–9'], label: 'Pick'),
                  KeyboardShortcutHint(keys: ['Enter'], label: 'Check / next'),
                  KeyboardShortcutHint(keys: ['Y', 'N'], label: 'Grade'),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
