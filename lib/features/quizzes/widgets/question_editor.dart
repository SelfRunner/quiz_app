import 'package:flutter/material.dart';

import '../../../core/widgets/adaptive_panel.dart';
import '../../../core/widgets/responsive.dart';
import '../../../data/models/question.dart';
import '../domain/question_rules.dart';
import 'quiz_format.dart';

/// Opens the question editor: full screen on phones, a dialog sized to the
/// form (capped at 720 wide and 85% of the screen height, scrolling inside)
/// on wider screens. Resolves to the edited, normalized question, or null
/// when cancelled.
Future<Question?> showQuestionEditor(
  BuildContext context, {
  required Question initial,
  bool isNew = false,
}) {
  final dialog = Breakpoints.isMedium(context);
  return showAdaptiveEditor<Question>(
    context,
    builder: (_) =>
        QuestionEditor(initial: initial, isNew: isNew, dialog: dialog),
  );
}

/// Per-type question form with inline validation. Pops the route with the
/// normalized [Question] on save.
class QuestionEditor extends StatefulWidget {
  const QuestionEditor({
    super.key,
    required this.initial,
    this.isNew = false,
    this.dialog = false,
  });

  final Question initial;
  final bool isNew;

  /// Inside a dialog: no scaffold; the form shrink-wraps (scrolling when
  /// taller than the dialog) under a header with Cancel / Done.
  final bool dialog;

  @override
  State<QuestionEditor> createState() => _QuestionEditorState();
}

class _QuestionEditorState extends State<QuestionEditor> {
  late QuestionType _type;
  late final TextEditingController _prompt;
  late final TextEditingController _answer;
  late final TextEditingController _explanation;
  final List<TextEditingController> _options = [];
  final List<Key> _optionKeys = [];
  int _keySeq = 0;
  Set<int> _correct = {};

  /// Option texts of the last choice-type state, restored when switching
  /// back from True/False or short answer.
  List<String>? _choiceStash;
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    final q = widget.initial;
    _type = q.type;
    _prompt = TextEditingController(text: q.prompt);
    _answer = TextEditingController(text: q.answerText ?? '');
    _explanation = TextEditingController(text: q.explanation ?? '');
    _correct = q.correctIndices.toSet();
    if (_isChoice(_type)) {
      _setOptions(q.options.isEmpty ? const ['', ''] : q.options);
    }
  }

  @override
  void dispose() {
    _prompt.dispose();
    _answer.dispose();
    _explanation.dispose();
    for (final c in _options) {
      c.dispose();
    }
    super.dispose();
  }

  static bool _isChoice(QuestionType t) =>
      t == QuestionType.mcqSingle || t == QuestionType.mcqMulti;

  void _setOptions(List<String> texts) {
    for (final c in _options) {
      c.dispose();
    }
    _options
      ..clear()
      ..addAll([for (final t in texts) TextEditingController(text: t)]);
    _optionKeys
      ..clear()
      ..addAll([for (final _ in texts) ValueKey(_keySeq++)]);
  }

  Question _current() => Question(
    id: widget.initial.id,
    type: _type,
    prompt: _prompt.text,
    options: switch (_type) {
      QuestionType.trueFalse => trueFalseOptions,
      QuestionType.shortAnswer => const [],
      _ => [for (final c in _options) c.text],
    },
    correctIndices: _type == QuestionType.shortAnswer
        ? const []
        : (_correct.toList()..sort()),
    answerText: _answer.text,
    explanation: _explanation.text,
  );

  void _changeType(QuestionType next) {
    if (next == _type) return;
    setState(() {
      final from = _type;
      if (_isChoice(from)) {
        _choiceStash = [for (final c in _options) c.text];
      }
      if (_isChoice(next)) {
        if (!_isChoice(from)) {
          _setOptions(_choiceStash ?? const ['', '', '', '']);
          _correct = {};
        } else if (next == QuestionType.mcqSingle && _correct.length > 1) {
          _correct = {(_correct.toList()..sort()).first};
        }
      } else if (next == QuestionType.trueFalse) {
        _correct = {0};
      } else {
        _correct = {};
      }
      _type = next;
    });
  }

  void _revalidate(String _) {
    if (_submitted) setState(() {});
  }

  void _addOption() {
    if (_options.length >= maxOptions) return;
    setState(() {
      _options.add(TextEditingController());
      _optionKeys.add(ValueKey(_keySeq++));
    });
  }

  void _removeOption(int index) {
    if (_options.length <= minOptions) return;
    setState(() {
      _options.removeAt(index).dispose();
      _optionKeys.removeAt(index);
      _correct = {
        for (final i in _correct)
          if (i < index) i else if (i > index) i - 1,
      };
    });
  }

  void _toggleCorrect(int index) {
    setState(() {
      if (_type == QuestionType.mcqMulti) {
        if (!_correct.remove(index)) _correct.add(index);
      } else {
        _correct = {index};
      }
    });
  }

  void _save() {
    final q = _current();
    final issues = validateQuestion(q);
    if (issues.isNotEmpty) {
      setState(() => _submitted = true);
      return;
    }
    Navigator.of(context).pop(normalizeQuestion(q));
  }

  Future<void> _cancel() async {
    final changed =
        normalizeQuestion(_current()) != normalizeQuestion(widget.initial);
    if (changed) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Discard changes?'),
          content: const Text('Your edits to this question will be lost.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Keep editing'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Discard'),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final issues = _submitted
        ? validateQuestion(_current())
        : QuestionIssues.none;
    final theme = Theme.of(context);
    final title = Text(widget.isNew ? 'New question' : 'Edit question');
    final cancel = IconButton(
      icon: const Icon(Icons.close),
      tooltip: 'Cancel',
      onPressed: _cancel,
    );
    final done = FilledButton(
      key: const Key('question-editor-save'),
      onPressed: _save,
      child: const Text('Done'),
    );
    final fields = <Widget>[
      Text('Type', style: theme.textTheme.labelLarge),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final t in QuestionType.values)
            ChoiceChip(
              avatar: Icon(questionTypeIcon(t), size: 18),
              label: Text(questionTypeLabel(t)),
              selected: _type == t,
              showCheckmark: false,
              onSelected: (_) => _changeType(t),
            ),
        ],
      ),
      const SizedBox(height: 20),
      TextField(
        key: const Key('question-prompt'),
        controller: _prompt,
        autofocus: widget.isNew,
        minLines: 2,
        maxLines: 6,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          labelText: _type == QuestionType.trueFalse ? 'Statement' : 'Question',
          errorText: issues.prompt,
        ),
        onChanged: _revalidate,
      ),
      const SizedBox(height: 20),
      ..._typeSection(issues, theme),
      const SizedBox(height: 20),
      TextField(
        key: const Key('question-explanation'),
        controller: _explanation,
        minLines: 1,
        maxLines: 5,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          labelText: 'Explanation (optional)',
          helperText: 'Shown after answering.',
        ),
      ),
    ];

    final Widget body;
    if (widget.dialog) {
      body = Material(
        type: MaterialType.transparency,
        child: Column(
          key: const Key('question-editor-dialog'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
              child: Row(
                children: [
                  cancel,
                  const SizedBox(width: 8),
                  Expanded(
                    child: DefaultTextStyle.merge(
                      style: theme.textTheme.titleLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      child: title,
                    ),
                  ),
                  const SizedBox(width: 8),
                  done,
                ],
              ),
            ),
            Divider(height: 1, color: theme.dividerColor),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: fields,
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      body = Scaffold(
        appBar: AppBar(
          leading: cancel,
          title: title,
          actions: [
            Padding(padding: const EdgeInsets.only(right: 12), child: done),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: fields,
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: body,
    );
  }

  List<Widget> _typeSection(QuestionIssues issues, ThemeData theme) {
    final error = issues.choice == null
        ? null
        : Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              issues.choice!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          );
    switch (_type) {
      case QuestionType.shortAnswer:
        return [
          TextField(
            key: const Key('question-answer'),
            controller: _answer,
            minLines: 1,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Expected answer',
              helperText: 'Players compare their answer and grade themselves.',
              errorText: issues.answer,
            ),
            onChanged: _revalidate,
          ),
        ];
      case QuestionType.trueFalse:
        return [
          Text('Correct answer', style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          RadioGroup<int>(
            groupValue: _correct.length == 1 ? _correct.first : null,
            onChanged: (v) {
              if (v != null) _toggleCorrect(v);
            },
            child: Column(
              children: [
                for (var i = 0; i < trueFalseOptions.length; i++)
                  RadioListTile<int>(
                    value: i,
                    title: Text(trueFalseOptions[i]),
                    contentPadding: EdgeInsets.zero,
                  ),
              ],
            ),
          ),
          ?error,
        ];
      case QuestionType.mcqSingle:
      case QuestionType.mcqMulti:
        final single = _type == QuestionType.mcqSingle;
        final rows = Column(
          children: [
            for (var i = 0; i < _options.length; i++)
              Padding(
                key: _optionKeys[i],
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Tooltip(
                        message: 'Mark as correct',
                        child: single
                            ? Radio<int>(value: i)
                            : Checkbox(
                                value: _correct.contains(i),
                                onChanged: (_) => _toggleCorrect(i),
                              ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: TextField(
                        key: Key('question-option-$i'),
                        controller: _options[i],
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          labelText: 'Option ${i + 1}',
                          errorText: issues.optionErrors[i],
                          isDense: true,
                        ),
                        onChanged: _revalidate,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remove option',
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: _options.length > minOptions
                          ? () => _removeOption(i)
                          : null,
                    ),
                  ],
                ),
              ),
          ],
        );
        return [
          Row(
            children: [
              Text('Options', style: theme.textTheme.labelLarge),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  single
                      ? 'Select the one correct option.'
                      : 'Tick every correct option.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (single)
            RadioGroup<int>(
              groupValue: _correct.length == 1 ? _correct.first : null,
              onChanged: (v) {
                if (v != null) _toggleCorrect(v);
              },
              child: rows,
            )
          else
            rows,
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _options.length < maxOptions ? _addOption : null,
              icon: const Icon(Icons.add),
              label: const Text('Add option'),
            ),
          ),
          ?error,
        ];
    }
  }
}
