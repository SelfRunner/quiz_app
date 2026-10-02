import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/data_providers.dart';
import '../../../data/models/models.dart';
import '../sharing_ui.dart';

/// Result of [showCopyTargetPicker]: copy into [subjectId] (an existing owned
/// subject), or create a new subject titled [newSubjectTitle] first.
typedef CopyTarget = ({String? subjectId, String? newSubjectTitle});

/// Asks which of the user's own subjects a shared note/quiz should be copied
/// into (or to create a new one). Returns null when cancelled.
Future<CopyTarget?> showCopyTargetPicker(
  BuildContext context, {
  required ShareResourceType type,
  String? suggestedTitle,
}) {
  return showDialog<CopyTarget>(
    context: context,
    builder: (context) =>
        _CopyTargetDialog(type: type, suggestedTitle: suggestedTitle),
  );
}

class _CopyTargetDialog extends ConsumerStatefulWidget {
  const _CopyTargetDialog({required this.type, this.suggestedTitle});

  final ShareResourceType type;
  final String? suggestedTitle;

  @override
  ConsumerState<_CopyTargetDialog> createState() => _CopyTargetDialogState();
}

/// Sentinel id for the "New subject" choice.
const _newSubject = '__new__';

class _CopyTargetDialogState extends ConsumerState<_CopyTargetDialog> {
  String? _selected;
  late final TextEditingController _newTitle = TextEditingController(
    text: widget.suggestedTitle ?? '',
  );
  String? _titleError;

  @override
  void dispose() {
    _newTitle.dispose();
    super.dispose();
  }

  void _submit() {
    final selected = _selected;
    if (selected == null) return;
    if (selected == _newSubject) {
      final title = _newTitle.text.trim();
      if (title.isEmpty) {
        setState(() => _titleError = 'Give the new subject a name.');
        return;
      }
      Navigator.of(context)
          .pop<CopyTarget>((subjectId: null, newSubjectTitle: title));
    } else {
      Navigator.of(context)
          .pop<CopyTarget>((subjectId: selected, newSubjectTitle: null));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subjects = ref.watch(subjectsProvider);
    final userId = ref.watch(currentUserIdProvider);

    final Widget body = switch (subjects) {
      AsyncValue(:final value?, hasValue: true) => _buildChoices(
        value.where((s) => s.isOwnedBy(userId) && !s.isDeleted).toList(),
      ),
      AsyncValue(:final error?) => Text(friendlyError(error)),
      _ => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      ),
    };

    return AlertDialog(
      icon: const Icon(Icons.drive_file_move_outlined),
      title: Text('Copy ${widget.type.noun} to…'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.type == ShareResourceType.note
                  ? 'Choose one of your subjects. The note and its quizzes '
                        'will be copied there, including images.'
                  : 'Choose one of your subjects to copy the quiz into.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Flexible(child: body),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('copy-target-confirm'),
          onPressed: _selected == null ? null : _submit,
          child: const Text('Copy here'),
        ),
      ],
    );
  }

  Widget _buildChoices(List<Subject> owned) {
    final scheme = Theme.of(context).colorScheme;
    return RadioGroup<String>(
      groupValue: _selected,
      onChanged: (v) => setState(() {
        _selected = v;
        _titleError = null;
      }),
      child: ListView(
        shrinkWrap: true,
        children: [
          for (final s in owned)
            RadioListTile<String>(
              key: ValueKey('copy-target-${s.id}'),
              value: s.id,
              contentPadding: EdgeInsets.zero,
              secondary: CircleAvatar(
                radius: 10,
                backgroundColor: s.color != null
                    ? Color(s.color!)
                    : scheme.primaryContainer,
              ),
              title: Text(
                s.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          RadioListTile<String>(
            key: const ValueKey('copy-target-new'),
            value: _newSubject,
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.add),
            title: const Text('New subject'),
            subtitle: owned.isEmpty
                ? const Text("You don't have any subjects yet.")
                : null,
          ),
          if (_selected == _newSubject)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: TextField(
                key: const ValueKey('copy-target-new-title'),
                controller: _newTitle,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: 'Subject name',
                  border: const OutlineInputBorder(),
                  errorText: _titleError,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
