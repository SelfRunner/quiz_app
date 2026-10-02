import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/router/routes.dart';
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
      body = const MessageView(icon: Icons.search_off, title: 'Quiz not found');
    } else if (quizAsync.hasError) {
      body = MessageView(
        icon: Icons.error_outline,
        title: 'Could not load the quiz',
        message: errorText(quizAsync.error!),
      );
    } else {
      body = const Center(child: CircularProgressIndicator());
    }

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
          title: Text(quiz?.title ?? 'Play quiz'),
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
    final count = quiz.questions.length;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: MaxWidth(
        maxWidth: 560,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.quiz_outlined,
                  size: 48,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 12),
                Text(
                  quiz.title,
                  style: theme.textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  plural(count, 'question'),
                  style: theme.textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text('Shuffle questions'),
                  value: shuffleQuestions,
                  onChanged: onShuffleQuestions,
                ),
                SwitchListTile(
                  title: const Text('Shuffle answer options'),
                  value: shuffleOptions,
                  onChanged: onShuffleOptions,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  key: const Key('start-quiz'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  onPressed: count == 0 ? null : onStart,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Start'),
                ),
                if (count == 0) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'This quiz has no questions yet.',
                    textAlign: TextAlign.center,
                  ),
                ],
                if (isWide(context)) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Keyboard: 1–9 pick an option · Enter checks / continues · '
                    'Y / N grade short answers',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
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
    final s = session;
    final item = s.current;
    final q = item.question;
    final checked = s.isChecked(item.id);
    final revealed = s.isRevealed(item.id);
    final grade = s.gradeFor(item.id);

    final content = <Widget>[
      Row(
        children: [
          Text(
            'Question ${s.index + 1} of ${s.length}',
            style: theme.textTheme.labelLarge,
          ),
          const Spacer(),
          Icon(Icons.check_circle, size: 16, color: Colors.green.shade600),
          const SizedBox(width: 4),
          Text('${s.correctCount} / ${s.answeredCount}'),
        ],
      ),
      const SizedBox(height: 8),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: (s.answeredCount) / s.length,
          minHeight: 6,
        ),
      ),
      const SizedBox(height: 24),
      Text(
        _hint(q.type),
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
      const SizedBox(height: 8),
      Text(q.prompt, style: theme.textTheme.headlineSmall),
      const SizedBox(height: 20),
    ];

    if (q.type.hasOptions) {
      final selected = s.selectedFor(item.id);
      for (var d = 0; d < item.optionOrder.length; d++) {
        final original = item.optionOrder[d];
        content.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _OptionTile(
              key: Key('option-$d'),
              number: d + 1,
              text: q.options[original],
              multi: q.type == QuestionType.mcqMulti,
              selected: selected.contains(original),
              checked: checked,
              correct: q.correctIndices.contains(original),
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
          minLines: 1,
          maxLines: 4,
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
          const SizedBox(height: 16),
          _RevealCard(
            title: 'Model answer',
            text: q.answerText ?? '—',
            color: theme.colorScheme.secondaryContainer,
            onColor: theme.colorScheme.onSecondaryContainer,
            icon: Icons.lightbulb_outline,
          ),
        ]);
      }
    }

    if (checked) {
      content.addAll([
        const SizedBox(height: 16),
        _FeedbackBanner(correct: grade ?? false, explanation: q.explanation),
      ]);
    } else if (revealed && q.explanation != null) {
      content.addAll([
        const SizedBox(height: 12),
        Text(q.explanation!, style: theme.textTheme.bodyMedium),
      ]);
    }

    final Widget actions;
    if (!q.type.hasOptions && revealed && !checked) {
      actions = Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                foregroundColor: theme.colorScheme.error,
              ),
              onPressed: () => onSelfGrade(false),
              icon: const Icon(Icons.close),
              label: const Text('I missed it'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                backgroundColor: Colors.green.shade700,
                foregroundColor: Colors.white,
              ),
              onPressed: () => onSelfGrade(true),
              icon: const Icon(Icons.check),
              label: const Text('I got it'),
            ),
          ),
        ],
      );
    } else {
      final label = checked
          ? (s.isLast ? 'See results' : 'Next')
          : (q.type.hasOptions ? 'Check' : 'Show answer');
      actions = FilledButton(
        key: const Key('primary-action'),
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        onPressed: checked || s.canCheck ? onPrimary : null,
        child: Text(label),
      );
    }

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: MaxWidth(
              maxWidth: 720,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: content,
              ),
            ),
          ),
        ),
        Material(
          elevation: 3,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: MaxWidth(maxWidth: 720, child: actions),
          ),
        ),
      ],
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    super.key,
    required this.number,
    required this.text,
    required this.multi,
    required this.selected,
    required this.checked,
    required this.correct,
    required this.onTap,
  });

  final int number;
  final String text;
  final bool multi;
  final bool selected;
  final bool checked;
  final bool correct;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final green = Colors.green.shade600;
    Color border = scheme.outlineVariant;
    Color? fill;
    IconData icon = multi
        ? (selected ? Icons.check_box : Icons.check_box_outline_blank)
        : (selected ? Icons.radio_button_checked : Icons.radio_button_off);
    Color iconColor = selected ? scheme.primary : scheme.outline;
    if (!checked && selected) {
      border = scheme.primary;
      fill = scheme.primaryContainer.withValues(alpha: 0.5);
    }
    if (checked) {
      if (correct) {
        border = green;
        fill = green.withValues(alpha: 0.12);
        icon = Icons.check_circle;
        iconColor = green;
      } else if (selected) {
        border = scheme.error;
        fill = scheme.errorContainer.withValues(alpha: 0.5);
        icon = Icons.cancel;
        iconColor = scheme.error;
      }
    }
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: fill ?? Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: border, width: selected || checked ? 2 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                Icon(icon, color: iconColor),
                const SizedBox(width: 12),
                Expanded(child: Text(text, style: theme.textTheme.bodyLarge)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Text('$number', style: theme.textTheme.labelSmall),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FeedbackBanner extends StatelessWidget {
  const _FeedbackBanner({required this.correct, this.explanation});

  final bool correct;
  final String? explanation;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final green = Colors.green.shade700;
    return _RevealCard(
      title: correct ? 'Correct!' : 'Not quite',
      text: explanation,
      icon: correct ? Icons.check_circle : Icons.cancel,
      color: correct
          ? green.withValues(alpha: 0.12)
          : scheme.errorContainer.withValues(alpha: 0.6),
      onColor: correct ? green : scheme.onErrorContainer,
    );
  }
}

class _RevealCard extends StatelessWidget {
  const _RevealCard({
    required this.title,
    required this.text,
    required this.icon,
    required this.color,
    required this.onColor,
  });

  final String title;
  final String? text;
  final IconData icon;
  final Color color;
  final Color onColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: onColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(color: onColor),
                ),
                if (text != null && text!.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(text!, style: theme.textTheme.bodyMedium),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
