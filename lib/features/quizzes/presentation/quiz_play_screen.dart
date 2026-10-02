import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/router/routes.dart';
import '../../../core/widgets/design_system.dart' hide MaxWidth;
import '../../../data/data_providers.dart';
import '../../../data/models/question.dart';
import '../../../data/models/quiz.dart';
import '../domain/quiz_session.dart';
import '../widgets/quiz_format.dart';
import '../widgets/quiz_results_view.dart';

enum _Phase { setup, playing, results }

/// Plays a quiz: options → one question per page → results. Saves a
/// `QuizAttempt` owned by the player (also for shared quizzes).
class QuizPlayScreen extends ConsumerStatefulWidget {
  const QuizPlayScreen({super.key, required this.quizId});

  final String quizId;

  @override
  ConsumerState<QuizPlayScreen> createState() => _QuizPlayScreenState();
}

class _QuizPlayScreenState extends ConsumerState<QuizPlayScreen> {
  _Phase _phase = _Phase.setup;
  bool _shuffleQuestions = false;
  bool _shuffleOptions = false;
  QuizSession? _session;
  DateTime? _completedAt;
  SaveStatus _saveStatus = SaveStatus.idle;
  String? _saveError;
  final _answer = TextEditingController();
  final _focus = FocusNode(debugLabel: 'quiz-play');

  @override
  void dispose() {
    _answer.dispose();
    _focus.dispose();
    super.dispose();
  }

  DateTime _now() => ref.read(clockProvider)();

  void _start(List<Question> questions, {bool practice = false}) {
    setState(() {
      _session = QuizSession(
        questions: questions,
        startedAt: _now(),
        shuffleQuestions: _shuffleQuestions,
        shuffleOptions: _shuffleOptions,
        isPractice: practice,
      );
      _answer.clear();
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
        _update((s) => s.reveal());
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
    _update((s) => s.selfGrade(correct: correct));
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
      return;
    }
    setState(() {
      _saveStatus = SaveStatus.saving;
      _saveError = null;
    });
    try {
      final repo = ref.read(attemptRepositoryProvider);
      final started = await repo.start(quizId: widget.quizId, total: s.length);
      await repo.save(s.toAttempt(started, completedAt: completedAt));
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
    _close();
  }

  void _close() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.quiz(widget.quizId));
    }
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
      final digit = _digit(key);
      if (digit != null && digit >= 1 && digit <= item.optionOrder.length) {
        _update((s) => s.toggleOption(digit - 1));
        return KeyEventResult.handled;
      }
    } else if (s.isRevealed(item.id) && !s.isChecked(item.id)) {
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

  static int? _digit(LogicalKeyboardKey key) {
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

  @override
  Widget build(BuildContext context) {
    final quizAsync = ref.watch(quizProvider(widget.quizId));
    final quiz = quizAsync.value;
    final playing =
        _phase == _Phase.playing && (_session?.answeredCount ?? 0) > 0;

    final Widget body;
    if (quiz != null) {
      body = switch (_phase) {
        _Phase.setup => _SetupView(
          quiz: quiz,
          shuffleQuestions: _shuffleQuestions,
          shuffleOptions: _shuffleOptions,
          onShuffleQuestions: (v) => setState(() => _shuffleQuestions = v),
          onShuffleOptions: (v) => setState(() => _shuffleOptions = v),
          onStart: () => _start(quiz.questions),
        ),
        _Phase.playing => Focus(
          focusNode: _focus,
          autofocus: true,
          onKeyEvent: _onKey,
          child: _QuestionView(
            session: _session!,
            answer: _answer,
            onToggle: (i) => _update((s) => s.toggleOption(i)),
            onTextChanged: (t) => _session!.setText(t),
            onPrimary: _primaryAction,
            onSelfGrade: _selfGrade,
          ),
        ),
        _Phase.results => QuizResultsView(
          session: _session!,
          duration: _completedAt!.difference(_session!.startedAt),
          saveStatus: _saveStatus,
          saveError: _saveError,
          onRetrySave: _saveAttempt,
          onRetry: () => _start(quiz.questions),
          onRetryMissed: _session!.missedQuestions.isEmpty
              ? null
              : () => _start(_session!.missedQuestions, practice: true),
          onDone: _close,
        ),
      };
    } else if (quizAsync.hasValue) {
      body = const NotFoundView(what: 'Quiz');
    } else if (quizAsync.hasError) {
      body = EmptyState(
        icon: Icons.error_outline,
        title: 'Could not load the quiz',
        message: errorText(quizAsync.error!),
      );
    } else {
      body = const ContentContainer(
        maxWidth: ContentWidth.form,
        child: Padding(
          padding: EdgeInsets.only(top: Insets.xl),
          child: LoadingSkeleton(rows: 3, leading: false),
        ),
      );
    }

    final colors = AppColors.of(context);
    return PopScope(
      canPop: !playing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmQuit();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close),
            onPressed: () => playing ? _confirmQuit() : _close(),
          ),
          title: Text(
            quiz?.title ?? 'Play quiz',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(color: colors.mutedText),
          ),
        ),
        body: SafeArea(child: body),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Setup
// ---------------------------------------------------------------------------

class _SetupView extends StatelessWidget {
  const _SetupView({
    required this.quiz,
    required this.shuffleQuestions,
    required this.shuffleOptions,
    required this.onShuffleQuestions,
    required this.onShuffleOptions,
    required this.onStart,
  });

  final Quiz quiz;
  final bool shuffleQuestions;
  final bool shuffleOptions;
  final ValueChanged<bool> onShuffleQuestions;
  final ValueChanged<bool> onShuffleOptions;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final count = quiz.questions.length;
    final wide = Breakpoints.isMedium(context);
    return SingleChildScrollView(
      child: ContentContainer(
        maxWidth: ContentWidth.form,
        padding: wide ? Insets.pageWide : Insets.page,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Gaps.h24,
            Icon(Icons.quiz_outlined, size: 32, color: colors.faintText),
            Gaps.h16,
            Text(
              quiz.title,
              style: theme.textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
            Gaps.h4,
            Text(
              plural(count, 'question'),
              style: theme.textTheme.bodyLarge?.copyWith(
                color: colors.mutedText,
              ),
              textAlign: TextAlign.center,
            ),
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
                'This quiz has no questions yet.',
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

// ---------------------------------------------------------------------------
// Question page
// ---------------------------------------------------------------------------

class _QuestionView extends StatelessWidget {
  const _QuestionView({
    required this.session,
    required this.answer,
    required this.onToggle,
    required this.onTextChanged,
    required this.onPrimary,
    required this.onSelfGrade,
  });

  final QuizSession session;
  final TextEditingController answer;
  final ValueChanged<int> onToggle;
  final ValueChanged<String> onTextChanged;
  final VoidCallback onPrimary;
  final ValueChanged<bool> onSelfGrade;

  static String _hint(QuestionType t) => switch (t) {
    QuestionType.mcqSingle => 'Choose one answer',
    QuestionType.mcqMulti => 'Select all that apply',
    QuestionType.trueFalse => 'True or false?',
    QuestionType.shortAnswer => 'Answer, then compare with the model answer',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final wide = Breakpoints.isMedium(context);
    final s = session;
    final item = s.current;
    final q = item.question;
    final checked = s.isChecked(item.id);
    final revealed = s.isRevealed(item.id);
    final grade = s.gradeFor(item.id);
    final mono = theme.textTheme.labelMedium?.copyWith(
      color: colors.mutedText,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    final content = <Widget>[
      Row(
        children: [
          Text('Question ${s.index + 1} of ${s.length}', style: mono),
          const Spacer(),
          Tooltip(
            message: 'Correct so far',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check, size: 14, color: colors.success),
                Gaps.w4,
                Text('${s.correctCount} / ${s.answeredCount}', style: mono),
              ],
            ),
          ),
        ],
      ),
      SizedBox(height: wide ? Insets.xxl : Insets.xl),
      Text(
        _hint(q.type),
        style: theme.textTheme.labelMedium?.copyWith(color: colors.faintText),
      ),
      Gaps.h8,
      Text(
        q.prompt,
        style:
            (wide
                    ? theme.textTheme.headlineMedium
                    : theme.textTheme.headlineSmall)
                ?.copyWith(height: 1.4),
      ),
      Gaps.h24,
    ];

    if (q.type.hasOptions) {
      final selected = s.selectedFor(item.id);
      for (var d = 0; d < item.optionOrder.length; d++) {
        final original = item.optionOrder[d];
        content.add(
          Padding(
            padding: const EdgeInsets.only(bottom: Insets.sm),
            child: _OptionTile(
              key: Key('option-$d'),
              number: d + 1,
              text: q.options[original],
              multi: q.type == QuestionType.mcqMulti,
              selected: selected.contains(original),
              checked: checked,
              correct: q.correctIndices.contains(original),
              showKey: wide,
              onTap: checked ? null : () => onToggle(d),
            ),
          ),
        );
      }
    } else {
      content.add(
        TextField(
          key: const Key('short-answer-input'),
          controller: answer,
          enabled: !revealed,
          minLines: 2,
          maxLines: 6,
          style: theme.textTheme.bodyLarge,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: 'Your answer (optional)',
          ),
          onChanged: onTextChanged,
          onSubmitted: (_) => onPrimary(),
        ),
      );
      if (revealed) {
        content.addAll([
          Gaps.h16,
          InfoBanner(
            icon: Icons.lightbulb_outline,
            title: 'Model answer',
            message: q.answerText ?? '—',
          ),
        ]);
      }
    }

    final explanation = q.explanation?.trim();
    if (checked) {
      final ok = grade ?? false;
      final hasExplanation = explanation != null && explanation.isNotEmpty;
      content.addAll([
        Gaps.h16,
        InfoBanner(
          key: const Key('answer-feedback'),
          kind: ok ? InfoBannerKind.success : InfoBannerKind.error,
          icon: ok ? Icons.check_circle_outline : Icons.highlight_off,
          title: hasExplanation ? (ok ? 'Correct!' : 'Not quite') : null,
          message: hasExplanation
              ? explanation
              : (ok ? 'Correct!' : 'Not quite'),
        ),
      ]);
    } else if (revealed && explanation != null && explanation.isNotEmpty) {
      content.addAll([
        Gaps.h12,
        Text(
          explanation,
          style: theme.textTheme.bodyMedium?.copyWith(color: colors.mutedText),
        ),
      ]);
    }

    final selfGrading = !q.type.hasOptions && revealed && !checked;
    final buttonSize = wide ? const Size(160, 44) : const Size.fromHeight(48);
    final Widget actions;
    if (selfGrading) {
      final missed = OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          minimumSize: buttonSize,
          foregroundColor: colors.danger,
        ),
        onPressed: () => onSelfGrade(false),
        icon: const Icon(Icons.close, size: 18),
        label: const Text('I missed it'),
      );
      final got = FilledButton.icon(
        style: FilledButton.styleFrom(
          minimumSize: buttonSize,
          backgroundColor: colors.success,
          foregroundColor: theme.colorScheme.surface,
        ),
        onPressed: () => onSelfGrade(true),
        icon: const Icon(Icons.check, size: 18),
        label: const Text('I got it'),
      );
      actions = wide
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [missed, Gaps.w8, got],
            )
          : Row(
              children: [
                Expanded(child: missed),
                Gaps.w12,
                Expanded(child: got),
              ],
            );
    } else {
      final label = checked
          ? (s.isLast ? 'See results' : 'Next')
          : (q.type.hasOptions ? 'Check' : 'Show answer');
      actions = FilledButton(
        key: const Key('primary-action'),
        style: FilledButton.styleFrom(minimumSize: buttonSize),
        onPressed: checked || s.canCheck ? onPrimary : null,
        child: Text(label),
      );
    }

    final Widget bar;
    if (wide) {
      final hints = <Widget>[
        if (q.type.hasOptions && !checked)
          KeyboardShortcutHint(
            keys: [
              item.optionOrder.length > 1
                  ? '1–${item.optionOrder.length.clamp(1, 9)}'
                  : '1',
            ],
            label: 'Pick',
          ),
        if (selfGrading)
          const KeyboardShortcutHint(keys: ['Y', 'N'], label: 'Got it / missed')
        else
          KeyboardShortcutHint(
            keys: const ['Enter'],
            label: checked
                ? (s.isLast ? 'Results' : 'Next')
                : (q.type.hasOptions ? 'Check' : 'Show answer'),
          ),
      ];
      bar = Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: Insets.lg,
              runSpacing: Insets.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: hints,
            ),
          ),
          Gaps.w16,
          actions,
        ],
      );
    } else {
      bar = SizedBox(width: double.infinity, child: actions);
    }

    return Column(
      children: [
        LinearProgressIndicator(
          key: const Key('quiz-progress'),
          value: s.length == 0 ? 0 : s.answeredCount / s.length,
          minHeight: 2,
          color: theme.colorScheme.primary,
          backgroundColor: colors.hairline,
        ),
        Expanded(
          child: SingleChildScrollView(
            child: ContentContainer(
              padding: EdgeInsets.fromLTRB(
                Breakpoints.gutter(context),
                wide ? Insets.xl : Insets.lg,
                Breakpoints.gutter(context),
                Insets.xl,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: content,
              ),
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(top: BorderSide(color: colors.hairline)),
          ),
          child: ContentContainer(
            padding: EdgeInsets.symmetric(
              horizontal: Breakpoints.gutter(context),
              vertical: Insets.md,
            ),
            child: bar,
          ),
        ),
      ],
    );
  }
}

/// One answer option. Idle rows are hairline-bordered; hover darkens the
/// border, selection uses the text color, and after checking the correct
/// option turns success-green and a wrong pick danger-red.
class _OptionTile extends StatefulWidget {
  const _OptionTile({
    super.key,
    required this.number,
    required this.text,
    required this.multi,
    required this.selected,
    required this.checked,
    required this.correct,
    required this.showKey,
    required this.onTap,
  });

  final int number;
  final String text;
  final bool multi;
  final bool selected;
  final bool checked;
  final bool correct;
  final bool showKey;
  final VoidCallback? onTap;

  @override
  State<_OptionTile> createState() => _OptionTileState();
}

class _OptionTileState extends State<_OptionTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final w = widget;
    var border = colors.hairline;
    var borderWidth = 1.0;
    var fill = colors.card;
    var textColor = theme.colorScheme.onSurface;
    var icon = w.multi
        ? (w.selected ? Icons.check_box : Icons.check_box_outline_blank)
        : (w.selected ? Icons.radio_button_checked : Icons.radio_button_off);
    var iconColor = w.selected ? theme.colorScheme.onSurface : colors.faintText;
    String? status;

    if (!w.checked) {
      if (w.selected) {
        border = theme.colorScheme.onSurface;
        borderWidth = 1.5;
        fill = Color.alphaBlend(colors.hover, colors.card);
      } else if (_hovered) {
        border = colors.border;
        fill = Color.alphaBlend(colors.hover, colors.card);
      }
    } else if (w.correct) {
      border = colors.success;
      borderWidth = 1.5;
      fill = colors.successContainer;
      textColor = colors.onSuccessContainer;
      icon = Icons.check_circle;
      iconColor = colors.success;
      status = 'correct answer';
    } else if (w.selected) {
      border = colors.danger;
      borderWidth = 1.5;
      fill = colors.dangerContainer;
      textColor = colors.onDangerContainer;
      icon = Icons.cancel;
      iconColor = colors.danger;
      status = 'incorrect';
    } else {
      textColor = colors.mutedText;
    }

    return Semantics(
      selected: w.selected,
      button: true,
      value: status,
      child: AnimatedContainer(
        duration: Motion.fast,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: Radii.lgAll,
          border: Border.all(color: border, width: borderWidth),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: w.onTap,
            onHover: (v) => setState(() => _hovered = v),
            borderRadius: Radii.lgAll,
            hoverColor: Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Insets.lg,
                vertical: Insets.md + 2,
              ),
              child: Row(
                children: [
                  Icon(icon, size: 20, color: iconColor),
                  Gaps.w12,
                  Expanded(
                    child: Text(
                      w.text,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: textColor,
                      ),
                    ),
                  ),
                  if (w.showKey) ...[
                    Gaps.w8,
                    KeyboardShortcutHint(keys: ['${w.number}']),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
