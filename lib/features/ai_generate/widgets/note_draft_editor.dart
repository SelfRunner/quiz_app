import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../quizzes/widgets/quiz_format.dart';

enum _NoteView { write, preview }

/// Title + Markdown body editor with live preview (side by side on wide
/// screens, toggled on phones).
class NoteDraftEditor extends StatefulWidget {
  const NoteDraftEditor({
    super.key,
    required this.title,
    required this.body,
    required this.onChanged,
    this.titleError,
    this.header,
  });

  final TextEditingController title;
  final TextEditingController body;
  final VoidCallback onChanged;
  final String? titleError;
  final Widget? header;

  @override
  State<NoteDraftEditor> createState() => _NoteDraftEditorState();
}

class _NoteDraftEditorState extends State<NoteDraftEditor> {
  _NoteView _view = _NoteView.write;

  @override
  void initState() {
    super.initState();
    widget.body.addListener(_rebuild);
  }

  @override
  void didUpdateWidget(NoteDraftEditor old) {
    super.didUpdateWidget(old);
    if (old.body != widget.body) {
      old.body.removeListener(_rebuild);
      widget.body.addListener(_rebuild);
    }
  }

  @override
  void dispose() {
    widget.body.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleField = TextField(
      key: const Key('note-title'),
      controller: widget.title,
      style: theme.textTheme.titleLarge,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(
        labelText: 'Title',
        errorText: widget.titleError,
      ),
      onChanged: (_) => widget.onChanged(),
    );
    final editor = TextField(
      key: const Key('note-body'),
      controller: widget.body,
      expands: true,
      maxLines: null,
      minLines: null,
      textAlignVertical: TextAlignVertical.top,
      style: const TextStyle(fontFamily: 'monospace', height: 1.4),
      decoration: const InputDecoration(
        labelText: 'Markdown',
        alignLabelWithHint: true,
      ),
      onChanged: (_) => widget.onChanged(),
    );
    final preview = DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(4),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: MarkdownBody(data: widget.body.text, selectable: true),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= wideBreakpoint;
        // Short viewports (phones, open keyboard): scroll the whole form and
        // give the editor a fixed height instead of filling the rest.
        final short = constraints.maxHeight < 640;
        final body = wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: editor),
                  const SizedBox(width: 16),
                  Expanded(child: preview),
                ],
              )
            : (_view == _NoteView.write ? editor : preview);
        final children = <Widget>[
          ?widget.header,
          titleField,
          const SizedBox(height: 12),
          if (!wide) ...[
            SegmentedButton<_NoteView>(
              segments: const [
                ButtonSegment(
                  value: _NoteView.write,
                  icon: Icon(Icons.edit_outlined),
                  label: Text('Write'),
                ),
                ButtonSegment(
                  value: _NoteView.preview,
                  icon: Icon(Icons.visibility_outlined),
                  label: Text('Preview'),
                ),
              ],
              selected: {_view},
              onSelectionChanged: (s) => setState(() => _view = s.first),
            ),
            const SizedBox(height: 12),
          ],
        ];
        if (short) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ...children,
              SizedBox(
                height: (constraints.maxHeight * 0.8).clamp(320, 640),
                child: body,
              ),
            ],
          );
        }
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...children,
              Expanded(child: body),
            ],
          ),
        );
      },
    );
  }
}
