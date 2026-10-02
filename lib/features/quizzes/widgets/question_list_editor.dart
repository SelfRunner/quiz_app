import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ai/ai_providers.dart';
import '../../../core/utils/clock.dart';
import '../../../core/widgets/design_system.dart' hide MaxWidth;
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

  /// When set, each question gets a "Regenerate" action. It is AI-gated:
  /// while AI is not configured the action shows a lock and opens the
  /// "Set up AI" sheet instead.
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
        padding: const EdgeInsets.only(top: Insets.xs),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            key: const Key('add-question'),
            onPressed: () => _add(context),
            icon: const Icon(Icons.add, size: 18),
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
          padding: const EdgeInsets.only(bottom: Insets.sm),
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

  /// AI action; gated on AI readiness (needs a ProviderScope when set).
  final VoidCallback? onRegenerate;

  void _regenerate(BuildContext context, bool aiReady, String? reason) {
    if (aiReady) {
      onRegenerate?.call();
    } else {
      showAiSetupSheet(context, reason: reason);
    }
  }

  Widget _menu(BuildContext context, {required bool aiReady, String? reason}) {
    final colors = AppColors.of(context);
    return PopupMenuButton<_CardAction>(
      tooltip: 'More actions',
      enabled: !busy,
      icon: const Icon(Icons.more_horiz),
      onSelected: (a) => switch (a) {
        _CardAction.duplicate => onDuplicate(),
        _CardAction.regenerate => _regenerate(context, aiReady, reason),
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
          PopupMenuItem(
            key: const Key('question-regenerate'),
            value: _CardAction.regenerate,
            child: ListTile(
              leading: const Icon(Icons.autorenew),
              title: const Text('Regenerate'),
              trailing: aiReady
                  ? null
                  : Tooltip(
                      message: 'Set up AI in Settings to use this',
                      child: Icon(
                        LockedFeature.lockIcon,
                        key: LockedFeature.badgeKey,
                        size: 16,
                        color: colors.mutedText,
                      ),
                    ),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final q = question;
    final hasIssues = issues.isNotEmpty;
    final emptyPrompt = q.prompt.trim().isEmpty;
    final menu = onRegenerate == null
        ? _menu(context, aiReady: false)
        : Consumer(
            builder: (context, ref, _) {
              final r = ref.watch(aiReadinessProvider).value;
              return _menu(
                context,
                aiReady: r?.isConfigured ?? false,
                reason: r?.reason,
              );
            },
          );
    return Material(
      color: colors.card,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: Radii.lgAll,
        side: BorderSide(
          color: hasIssues ? colors.danger : colors.hairline,
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
              padding: const EdgeInsets.fromLTRB(
                Insets.sm,
                Insets.xs,
                Insets.xs,
                Insets.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ReorderableDragStartListener(
                        index: index,
                        child: Padding(
                          padding: const EdgeInsets.all(Insets.xs),
                          child: MouseRegion(
                            cursor: SystemMouseCursors.grab,
                            child: Icon(
                              Icons.drag_indicator,
                              size: 18,
                              color: colors.faintText,
                            ),
                          ),
                        ),
                      ),
                      Gaps.w4,
                      Text(
                        'Q${index + 1}',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: colors.mutedText,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      Gaps.w12,
                      Icon(
                        questionTypeIcon(q.type),
                        size: 14,
                        color: colors.faintText,
                      ),
                      Gaps.w4,
                      Expanded(
                        child: Text(
                          questionTypeLabel(q.type),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: colors.faintText,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Edit question',
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        onPressed: busy ? null : onEdit,
                      ),
                      menu,
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Insets.sm,
                      Insets.xxs,
                      Insets.sm,
                      0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          emptyPrompt ? 'No question text yet' : q.prompt,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontStyle: emptyPrompt ? FontStyle.italic : null,
                            color: emptyPrompt ? colors.faintText : null,
                          ),
                        ),
                        Gaps.h8,
                        ..._answerPreview(theme, colors),
                        if (q.explanation != null &&
                            q.explanation!.trim().isNotEmpty) ...[
                          Gaps.h4,
                          Text(
                            q.explanation!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.mutedText,
                            ),
                          ),
                        ],
                        if (hasIssues) ...[
                          Gaps.h8,
                          for (final m in issues.messages)
                            Row(
                              children: [
                                Icon(
                                  Icons.error_outline,
                                  size: 16,
                                  color: colors.danger,
                                ),
                                Gaps.w8,
                                Expanded(
                                  child: Text(
                                    m,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colors.danger,
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

  List<Widget> _answerPreview(ThemeData theme, AppColors colors) {
    final q = question;
    if (q.type == QuestionType.shortAnswer) {
      final answer = q.answerText?.trim() ?? '';
      return [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: 'Answer: ',
                style: TextStyle(color: colors.mutedText),
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
          padding: const EdgeInsets.symmetric(vertical: Insets.xxs),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Icon(
                  q.correctIndices.contains(i)
                      ? Icons.check_circle
                      : Icons.circle_outlined,
                  size: 16,
                  color: q.correctIndices.contains(i)
                      ? colors.success
                      : colors.faintText,
                ),
              ),
              Gaps.w8,
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
