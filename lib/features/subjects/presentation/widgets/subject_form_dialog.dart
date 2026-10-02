import 'package:flutter/material.dart';

import '../../../../data/models/subject.dart';
import 'subject_visuals.dart';

/// Values entered in [SubjectFormDialog].
class SubjectFormResult {
  const SubjectFormResult({required this.title, this.description, this.color});

  final String title;
  final String? description;
  final int? color;
}

/// Create (subject == null) or edit a subject. Returns null when cancelled.
Future<SubjectFormResult?> showSubjectFormDialog(
  BuildContext context, {
  Subject? subject,
}) => showDialog<SubjectFormResult>(
  context: context,
  builder: (_) => SubjectFormDialog(subject: subject),
);

class SubjectFormDialog extends StatefulWidget {
  const SubjectFormDialog({super.key, this.subject});

  final Subject? subject;

  @override
  State<SubjectFormDialog> createState() => _SubjectFormDialogState();
}

class _SubjectFormDialogState extends State<SubjectFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.subject?.title);
  late final _description = TextEditingController(
    text: widget.subject?.description,
  );
  late int? _color = widget.subject == null
      ? subjectPalette.first
      : widget.subject!.color;

  bool get _isEdit => widget.subject != null;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final description = _description.text.trim();
    Navigator.of(context).pop(
      SubjectFormResult(
        title: _title.text.trim(),
        description: description.isEmpty ? null : description,
        color: _color,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEdit ? 'Edit subject' : 'New subject'),
      scrollable: true,
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                key: const Key('subject-title'),
                controller: _title,
                autofocus: !_isEdit,
                maxLength: 100,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Enter a title' : null,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  hintText: 'e.g. Biology',
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                key: const Key('subject-description'),
                controller: _description,
                minLines: 2,
                maxLines: 4,
                maxLength: 500,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                ),
              ),
              const SizedBox(height: 8),
              Text('Color', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              SubjectColorPicker(
                selected: _color,
                onChanged: (c) => setState(() => _color = c),
              ),
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
          key: const Key('subject-submit'),
          onPressed: _submit,
          child: Text(_isEdit ? 'Save' : 'Create'),
        ),
      ],
    );
  }
}
