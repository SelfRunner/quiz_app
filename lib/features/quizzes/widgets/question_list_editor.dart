import 'package:flutter/material.dart';

import '../../../core/utils/clock.dart';
import '../../../data/models/question.dart';
import '../domain/question_rules.dart';
import 'question_editor.dart';
import 'quiz_format.dart';

/// Reorderable, editable list of questions. Used by the quiz editor and the
/// AI preview. It is a scrollable (a [ReorderableListView]); put the rest of
/// the form in [header].
class QuestionListEditor extends StatelessWidget {
  const QuestionListEditor({
    super.key,
    required this.questions,
    required this.onChanged,
    required this.newId,
    this.header,
    this.showIssues = false,
    this.onRegenerate,
    this.busyIds = const {},
    this.padding = const EdgeInsets.fromLTRB(16, 16, 16, 96),
  });

  final List<Question> questions;
  final ValueChanged<List<Question>> onChanged;
  final IdGenerator newId;
  final Widget? header;

  /// Highlight invalid questions (e.g. after a failed save, or AI drafts).
  final bool showIssues;

  /// When set, each question gets a "Regenerate" action.
  final void Function(Question question)? onRegenerate;

  /// Questions currently being regenerated.
  final Set<String> busyIds;
  final EdgeInsets padding;

  Future<void> _edit(BuildContext context, int index) async {
    final edited = await showQuestionEditor(context, initial: questions[index]);
    if (edited == null) return;
    onChanged([...questions]..[index] = edited);
  }

  Future<void> _add(BuildContext context) async {
    final last = questions.isEmpty ? null : questions.last.type;
    final created = await showQuestionEditor(
      context,
      initial: blankQuestion(newId(), type: last ?? QuestionType.mcqSingle),
      isNew: true,
    );
    if (created == null) return;
    onChanged([...questions, created]);
  }

  void _duplicate(int index) {
    final copy = questions[index].copyWith(id: newId());
    onChanged([...questions]..insert(index + 1, copy));
  }

  void _delete(BuildContext context, int index) {
    final removed = questions[index];
    final before = [...questions];
    onChanged([...questions]..removeAt(index));
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            'Deleted "${_shorten(removed.prompt, 40)}"',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => onChanged(before),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return ReorderableListView.builder(
      padding: padding,
      buildDefaultDragHandles: false,
      header: header,
      footer: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Center(
          child: OutlinedButton.icon(
            key: const Key('add-question'),
            onPressed: () => _add(context),
            icon: const Icon(Icons.add),
            label: const Text('Add question'),
          ),
        ),
      ),
      itemCount: questions.length,
      onReorderItem: (oldIndex, newIndex) {
        final list = [...questions];
        final item = list.removeAt(oldIndex);
        list.insert(newIndex, item);
        onChanged(list);
      },
      itemBuilder: (context, index) {
        final q = questions[index];
        return Padding(
          key: ValueKey(q.id),
          padding: const EdgeInsets.only(bottom: 12),
          child: QuestionCard(
            index: index,
            question: q,
            issues: showIssues ? validateQuestion(q) : QuestionIssues.none,
            busy: busyIds.contains(q.id),
            onEdit: () => _edit(context, index),
            onDuplicate: () => _duplicate(index),
            onDelete: () => _delete(context, index),
            onRegenerate: onRegenerate == null ? null : () => onRegenerate!(q),
          ),
        );
      },
    );
  }
}

String _shorten(String s, int max) {
  final t = s.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (t.isEmpty) return 'question';
  return t.length <= max ? t : '${t.substring(0, max - 1)}…';
}

enum _CardAction { duplicate, regenerate, delete }

/// Read-only summary of a question with edit actions and a drag handle.
class QuestionCard extends StatelessWidget {
  const QuestionCard({
    super.key,
    required this.index,
    required this.question,
    required this.onEdit,
    required this.onDuplicate,
    required this.onDelete,
    this.onRegenerate,
    this.issues = QuestionIssues.none,
    this.busy = false,
  });

  final int index;
  final Question question;
  final QuestionIssues issues;
  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;
  final VoidCallback? onRegenerate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final q = question;
    final hasIssues = issues.isNotEmpty;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: hasIssues ? scheme.error : scheme.outlineVariant,
          width: hasIssues ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        onTap: busy ? null : onEdit,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (busy) const LinearProgressIndicator(minHeight: 2),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ReorderableDragStartListener(
                        index: index,
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: MouseRegion(
                            cursor: SystemMouseCursors.grab,
                            child: Icon(Icons.drag_indicator, size: 20),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Q${index + 1}',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: scheme.primary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Chip(
                            avatar: Icon(questionTypeIcon(q.type), size: 16),
                            label: Text(
                              questionTypeLabel(q.type),
                              overflow: TextOverflow.ellipsis,
                            ),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Edit question',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: busy ? null : onEdit,
                      ),
                      PopupMenuButton<_CardAction>(
                        tooltip: 'More actions',
                        enabled: !busy,
                        onSelected: (a) => switch (a) {
                          _CardAction.duplicate => onDuplicate(),
                          _CardAction.regenerate => onRegenerate?.call(),
                          _CardAction.delete => onDelete(),
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: _CardAction.duplicate,
                            child: ListTile(
                              leading: Icon(Icons.copy_outlined),
                              title: Text('Duplicate'),
                            ),
                          ),
                          if (onRegenerate != null)
                            const PopupMenuItem(
                              value: _CardAction.regenerate,
                              child: ListTile(
                                leading: Icon(Icons.autorenew),
                                title: Text('Regenerate'),
                              ),
                            ),
                          const PopupMenuItem(
                            value: _CardAction.delete,
                            child: ListTile(
                              leading: Icon(Icons.delete_outline),
                              title: Text('Delete'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          q.prompt.trim().isEmpty
                              ? 'No question text yet'
                              : q.prompt,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontStyle: q.prompt.trim().isEmpty
                                ? FontStyle.italic
                                : null,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ..._answerPreview(theme),
                        if (q.explanation != null &&
                            q.explanation!.trim().isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            q.explanation!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                        if (hasIssues) ...[
                          const SizedBox(height: 8),
                          for (final m in issues.messages)
                            Row(
                              children: [
                                Icon(
                                  Icons.error_outline,
                                  size: 16,
                                  color: scheme.error,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    m,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: scheme.error,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _answerPreview(ThemeData theme) {
    final q = question;
    final scheme = theme.colorScheme;
    if (q.type == QuestionType.shortAnswer) {
      final answer = q.answerText?.trim() ?? '';
      return [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: 'Answer: ',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              TextSpan(
                text: answer.isEmpty ? '—' : answer,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ];
    }
    return [
      for (var i = 0; i < q.options.length; i++)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                q.correctIndices.contains(i)
                    ? Icons.check_circle
                    : Icons.circle_outlined,
                size: 18,
                color: q.correctIndices.contains(i)
                    ? Colors.green.shade600
                    : scheme.outline,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  q.options[i].trim().isEmpty ? '(empty)' : q.options[i],
                  style: q.correctIndices.contains(i)
                      ? const TextStyle(fontWeight: FontWeight.w600)
                      : null,
                ),
              ),
            ],
          ),
        ),
    ];
  }
}
