import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/widgets/design_system.dart' hide MaxWidth;
import '../domain/exam_session.dart';
import 'ai_grading_widgets.dart';

/// Preset time limits in minutes (null = off).
const List<int?> examTimePresets = [null, 5, 10, 15, 30];

/// Longest custom time limit, in minutes.
const int maxExamMinutes = 600;

/// Exam options: random pool size, time limit, shuffled options. Reports
/// the config on every change (null while an input is invalid).
class ExamSetupForm extends StatefulWidget {
  const ExamSetupForm({
    super.key,
    required this.total,
    required this.onChanged,
    this.initial = const ExamConfig(),
  });

  /// Questions in the quiz (the pool).
  final int total;
  final ExamConfig initial;
  final ValueChanged<ExamConfig?> onChanged;

  @override
  State<ExamSetupForm> createState() => _ExamSetupFormState();
}

class _ExamSetupFormState extends State<ExamSetupForm> {
  late final TextEditingController _count;
  late final TextEditingController _custom;
  int? _preset; // minutes; null = off
  bool _customLimit = false;
  late bool _shuffleOptions;

  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    final count = init.questionCount;
    _count = TextEditingController(
      text: '${count == null ? widget.total : count.clamp(1, widget.total)}',
    );
    final minutes = init.timeLimitMinutes;
    _customLimit = minutes != null && !examTimePresets.contains(minutes);
    _preset = _customLimit ? null : minutes;
    _custom = TextEditingController(text: _customLimit ? '$minutes' : '');
    _shuffleOptions = init.shuffleOptions;
  }

  @override
  void dispose() {
    _count.dispose();
    _custom.dispose();
    super.dispose();
  }

  int? get _countValue {
    final n = int.tryParse(_count.text.trim());
    if (n == null || n < 1 || n > widget.total) return null;
    return n;
  }

  int? get _customValue {
    final n = int.tryParse(_custom.text.trim());
    if (n == null || n < 1 || n > maxExamMinutes) return null;
    return n;
  }

  void _emit() {
    final count = _countValue;
    final custom = _customValue;
    if (count == null || (_customLimit && custom == null)) {
      widget.onChanged(null);
      return;
    }
    widget.onChanged(
      ExamConfig(
        questionCount: count >= widget.total ? null : count,
        timeLimitMinutes: _customLimit ? custom : _preset,
        shuffleOptions: _shuffleOptions,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final label = theme.textTheme.labelLarge;
    final helper = theme.textTheme.bodySmall?.copyWith(color: colors.mutedText);
    final countError = _countValue == null
        ? 'Enter a number from 1 to ${widget.total}'
        : null;
    final customError = _customLimit && _customValue == null
        ? 'Enter 1 to $maxExamMinutes minutes'
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Questions', style: label),
        Gaps.h8,
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 120,
              child: TextField(
                key: const Key('exam-count'),
                controller: _count,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  isDense: true,
                  suffixText: 'of ${widget.total}',
                ),
                onChanged: (_) => setState(_emit),
              ),
            ),
            Gaps.w8,
            Padding(
              padding: const EdgeInsets.only(top: Insets.xxs),
              child: TextButton(
                onPressed: () {
                  _count.text = '${widget.total}';
                  setState(_emit);
                },
                child: const Text('All'),
              ),
            ),
          ],
        ),
        Gaps.h4,
        Text(
          countError ??
              (_countValue! >= widget.total
                  ? 'Every question, in random order.'
                  : 'A random selection from the ${widget.total} questions.'),
          style: countError == null
              ? helper
              : helper?.copyWith(color: colors.danger),
        ),
        Gaps.h24,
        Text('Time limit', style: label),
        Gaps.h8,
        Wrap(
          spacing: Insets.sm,
          runSpacing: Insets.sm,
          children: [
            for (final m in examTimePresets)
              ChoiceChip(
                key: Key('limit-${m ?? 'off'}'),
                label: Text(m == null ? 'Off' : '$m min'),
                selected: !_customLimit && _preset == m,
                onSelected: (_) => setState(() {
                  _customLimit = false;
                  _preset = m;
                  _emit();
                }),
              ),
            ChoiceChip(
              key: const Key('limit-custom'),
              label: const Text('Custom'),
              selected: _customLimit,
              onSelected: (_) => setState(() {
                _customLimit = true;
                _emit();
              }),
            ),
          ],
        ),
        if (_customLimit) ...[
          Gaps.h12,
          SizedBox(
            width: 160,
            child: TextField(
              key: const Key('exam-custom-minutes'),
              controller: _custom,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                isDense: true,
                suffixText: 'min',
                errorText: customError,
              ),
              onChanged: (_) => setState(_emit),
            ),
          ),
        ],
        Gaps.h16,
        SwitchListTile(
          key: const Key('exam-shuffle-options'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Shuffle answer options'),
          value: _shuffleOptions,
          onChanged: (v) => setState(() {
            _shuffleOptions = v;
            _emit();
          }),
        ),
        const AiGradingSwitch(contentPadding: EdgeInsets.zero),
        Text(
          'No feedback until you submit. You can move between questions and '
          'flag them for review.',
          style: helper,
        ),
      ],
    );
  }
}

/// Exam setup dialog; returns the chosen config (null = cancelled).
Future<ExamConfig?> showExamSetupDialog(
  BuildContext context, {
  required int total,
  ExamConfig initial = const ExamConfig(),
}) {
  return showDialog<ExamConfig>(
    context: context,
    builder: (context) {
      ExamConfig? config = initial;
      return StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Exam mode'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: ExamSetupForm(
                total: total,
                initial: initial,
                onChanged: (c) => setState(() => config = c),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('start-exam'),
              onPressed: config == null
                  ? null
                  : () => Navigator.of(context).pop(config),
              child: const Text('Start exam'),
            ),
          ],
        ),
      );
    },
  );
}
