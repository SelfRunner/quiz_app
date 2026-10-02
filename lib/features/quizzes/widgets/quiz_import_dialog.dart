import 'package:flutter/material.dart';

import '../../../core/widgets/design_system.dart' hide MaxWidth;
import '../../../data/models/question.dart';
import '../../../io/import_report.dart';
import 'quiz_format.dart';

/// Preview of a quiz JSON / CSV import before anything is saved: the
/// questions that will be imported, every skipped row with its line number,
/// warnings, and the new quiz's title. Returns the chosen title when the
/// user confirms, null when cancelled.
Future<String?> showQuizImportPreview(
  BuildContext context, {
  required String fileName,
  required ImportResult<Question> result,
  required String initialTitle,
}) => showDialog<String>(
  context: context,
  builder: (_) => QuizImportPreviewDialog(
    fileName: fileName,
    result: result,
    initialTitle: initialTitle,
  ),
);

class QuizImportPreviewDialog extends StatefulWidget {
  const QuizImportPreviewDialog({
    super.key,
    required this.fileName,
    required this.result,
    required this.initialTitle,
  });

  final String fileName;
  final ImportResult<Question> result;
  final String initialTitle;

  static const Key confirmKey = Key('quiz-import-confirm');
  static const Key titleKey = Key('quiz-import-title');
  static const Key summaryKey = Key('quiz-import-summary');
  static const Key errorsKey = Key('quiz-import-errors');
  static const Key warningsKey = Key('quiz-import-warnings');

  /// `Line 4, correct: Missing correct answer.`
  static String issueText(ImportIssue issue) {
    final where = [
      if (issue.line != null) 'Line ${issue.line}',
      ?issue.field,
    ].join(', ');
    return where.isEmpty ? issue.message : '$where: ${issue.message}';
  }

  /// Short answer summary of [q] ("Answer: Jupiter").
  static String answerSummary(Question q) {
    if (q.type == QuestionType.shortAnswer) {
      final a = q.answerText?.trim() ?? '';
      return a.isEmpty ? '' : 'Answer: $a';
    }
    final correct = [
      for (final i in q.correctIndices)
        if (i >= 0 && i < q.options.length) q.options[i],
    ];
    if (correct.isEmpty) return '';
    return '${correct.length > 1 ? 'Answers' : 'Answer'}: '
        '${correct.join(', ')}';
  }

  @override
  State<QuizImportPreviewDialog> createState() =>
      _QuizImportPreviewDialogState();
}

class _QuizImportPreviewDialogState extends State<QuizImportPreviewDialog> {
  late final _title = TextEditingController(text: widget.initialTitle);

  @override
  void initState() {
    super.initState();
    _title.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  bool get _canImport =>
      widget.result.items.isNotEmpty && _title.text.trim().isNotEmpty;

  void _confirm() {
    if (_canImport) Navigator.of(context).pop(_title.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final result = widget.result;
    final questions = result.items;
    final n = questions.length;
    final skipped = result.errors.length;
    final muted = theme.textTheme.bodySmall?.copyWith(color: colors.mutedText);

    Widget issues(List<ImportIssue> list, Color color, Key key) => Container(
      key: key,
      constraints: const BoxConstraints(maxHeight: 140),
      padding: const EdgeInsets.symmetric(
        horizontal: Insets.md,
        vertical: Insets.sm,
      ),
      decoration: BoxDecoration(
        borderRadius: Radii.mdAll,
        border: Border.all(color: colors.hairline),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final issue in list)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Insets.xxs),
                child: Text(
                  QuizImportPreviewDialog.issueText(issue),
                  style: theme.textTheme.bodySmall?.copyWith(color: color),
                ),
              ),
          ],
        ),
      ),
    );

    return AlertDialog(
      title: const Text('Import quiz'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.fileName,
                style: muted,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Gaps.h8,
              Text(
                [
                  '${plural(n, 'question')} ready',
                  if (skipped > 0) '${plural(skipped, 'problem')} skipped',
                ].join(' · '),
                key: QuizImportPreviewDialog.summaryKey,
                style: theme.textTheme.titleSmall,
              ),
              Gaps.h12,
              TextField(
                key: QuizImportPreviewDialog.titleKey,
                controller: _title,
                decoration: const InputDecoration(labelText: 'Quiz title'),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _confirm(),
              ),
              if (result.errors.isNotEmpty) ...[
                Gaps.h12,
                Text('Skipped', style: theme.textTheme.labelLarge),
                Gaps.h4,
                issues(
                  result.errors,
                  colors.danger,
                  QuizImportPreviewDialog.errorsKey,
                ),
              ],
              if (result.warnings.isNotEmpty) ...[
                Gaps.h12,
                Text('Warnings', style: theme.textTheme.labelLarge),
                Gaps.h4,
                issues(
                  result.warnings,
                  colors.warning,
                  QuizImportPreviewDialog.warningsKey,
                ),
              ],
              if (n > 0) ...[
                Gaps.h12,
                Text('Questions', style: theme.textTheme.labelLarge),
                Gaps.h4,
                Container(
                  constraints: const BoxConstraints(maxHeight: 280),
                  decoration: BoxDecoration(
                    borderRadius: Radii.mdAll,
                    border: Border.all(color: colors.hairline),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(vertical: Insets.xs),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final (i, q) in questions.indexed)
                          _QuestionRow(index: i, question: q),
                      ],
                    ),
                  ),
                ),
              ] else ...[
                Gaps.h12,
                Text(
                  'No questions could be read from this file.',
                  style: muted,
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: QuizImportPreviewDialog.confirmKey,
          onPressed: _canImport ? _confirm : null,
          child: Text(n == 0 ? 'Import' : 'Import ${plural(n, 'question')}'),
        ),
      ],
    );
  }
}

class _QuestionRow extends StatelessWidget {
  const _QuestionRow({required this.index, required this.question});

  final int index;
  final Question question;

  @override
  Widget build(BuildContext context) {
    final q = question;
    final answer = QuizImportPreviewDialog.answerSummary(q);
    return ListRowTile(
      key: ValueKey('quiz-import-question-$index'),
      dense: true,
      leading: Tooltip(
        message: questionTypeLabel(q.type),
        child: Icon(questionTypeIcon(q.type), size: 18),
      ),
      title: Text(
        '${index + 1}. ${q.prompt}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: answer.isEmpty
          ? null
          : Text(answer, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}
