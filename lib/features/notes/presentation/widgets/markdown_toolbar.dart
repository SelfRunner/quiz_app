import 'package:flutter/material.dart';

import '../../../../core/widgets/design_system.dart';
import '../../application/markdown_editing.dart';

/// Formatting toolbar for a Markdown [TextEditingController]. Image and link
/// insertion are delegated (they need dialogs / pickers).
class MarkdownToolbar extends StatelessWidget {
  const MarkdownToolbar({
    super.key,
    required this.controller,
    required this.onInsertLink,
    required this.onInsertImage,
    this.focusNode,
    this.imageBusy = false,
  });

  final TextEditingController controller;
  final VoidCallback onInsertLink;
  final VoidCallback? onInsertImage;
  final FocusNode? focusNode;
  final bool imageBusy;

  void _apply(TextEditingValue Function(TextEditingValue) edit) {
    controller.value = edit(controller.value);
    focusNode?.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    Widget button(
      String key,
      IconData icon,
      String tooltip,
      VoidCallback? onPressed,
    ) => IconButton(
      key: Key('md-$key'),
      tooltip: tooltip,
      icon: Icon(icon),
      iconSize: 18,
      color: colors.mutedText,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      style: IconButton.styleFrom(
        minimumSize: const Size.square(34),
        shape: const RoundedRectangleBorder(borderRadius: Radii.smAll),
      ),
    );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(vertical: Insets.xs),
      child: Row(
        children: [
          button(
            'bold',
            Icons.format_bold,
            'Bold (Ctrl+B)',
            () => _apply(
              (v) => MarkdownEditing.wrap(v, '**', '**', placeholder: 'bold'),
            ),
          ),
          button(
            'italic',
            Icons.format_italic,
            'Italic (Ctrl+I)',
            () => _apply(
              (v) => MarkdownEditing.wrap(v, '_', '_', placeholder: 'italic'),
            ),
          ),
          button(
            'strike',
            Icons.format_strikethrough,
            'Strikethrough',
            () => _apply(
              (v) => MarkdownEditing.wrap(v, '~~', '~~', placeholder: 'text'),
            ),
          ),
          PopupMenuButton<int>(
            key: const Key('md-heading'),
            tooltip: 'Heading',
            icon: Icon(Icons.title, size: 18, color: colors.mutedText),
            onSelected: (level) => _apply(
              (v) => MarkdownEditing.prefixLines(v, '${'#' * level} '),
            ),
            itemBuilder: (_) => [
              for (var level = 1; level <= 3; level++)
                PopupMenuItem(
                  value: level,
                  child: Text(
                    'Heading $level',
                    style: switch (level) {
                      1 => Theme.of(context).textTheme.titleLarge,
                      2 => Theme.of(context).textTheme.titleMedium,
                      _ => Theme.of(context).textTheme.titleSmall,
                    },
                  ),
                ),
            ],
          ),
          const _ToolbarDivider(),
          button(
            'bullets',
            Icons.format_list_bulleted,
            'Bulleted list',
            () => _apply((v) => MarkdownEditing.prefixLines(v, '- ')),
          ),
          button(
            'numbers',
            Icons.format_list_numbered,
            'Numbered list',
            () => _apply(
              (v) => MarkdownEditing.prefixLines(v, '1. ', numbered: true),
            ),
          ),
          button(
            'checklist',
            Icons.checklist,
            'Checklist',
            () => _apply((v) => MarkdownEditing.prefixLines(v, '- [ ] ')),
          ),
          button(
            'quote',
            Icons.format_quote,
            'Quote',
            () => _apply((v) => MarkdownEditing.prefixLines(v, '> ')),
          ),
          const _ToolbarDivider(),
          button(
            'code',
            Icons.code,
            'Inline code',
            () => _apply(
              (v) => MarkdownEditing.wrap(v, '`', '`', placeholder: 'code'),
            ),
          ),
          button(
            'codeblock',
            Icons.data_object,
            'Code block',
            () => _apply(MarkdownEditing.codeBlock),
          ),
          button('link', Icons.link, 'Insert link (Ctrl+K)', onInsertLink),
          if (imageBusy)
            const Padding(
              padding: EdgeInsets.all(Insets.sm),
              child: SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            button(
              'image',
              Icons.add_photo_alternate_outlined,
              'Insert image',
              onInsertImage,
            ),
        ],
      ),
    );
  }
}

class _ToolbarDivider extends StatelessWidget {
  const _ToolbarDivider();

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 18,
    child: VerticalDivider(
      width: Insets.md,
      color: AppColors.of(context).border,
    ),
  );
}

/// Asks for a link URL and optional label.
Future<({String url, String label})?> showInsertLinkDialog(
  BuildContext context, {
  String initialLabel = '',
}) => showDialog<({String url, String label})>(
  context: context,
  builder: (_) => _LinkDialog(initialLabel: initialLabel),
);

class _LinkDialog extends StatefulWidget {
  const _LinkDialog({required this.initialLabel});

  final String initialLabel;

  @override
  State<_LinkDialog> createState() => _LinkDialogState();
}

class _LinkDialogState extends State<_LinkDialog> {
  final _formKey = GlobalKey<FormState>();
  final _url = TextEditingController();
  late final _label = TextEditingController(text: widget.initialLabel);

  @override
  void dispose() {
    _url.dispose();
    _label.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    var url = _url.text.trim();
    if (!url.contains('://') && !url.startsWith('mailto:')) {
      url = 'https://$url';
    }
    Navigator.of(context).pop((url: url, label: _label.text.trim()));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Insert link'),
    content: SizedBox(
      width: 400,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              key: const Key('link-url'),
              controller: _url,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'URL',
                hintText: 'https://example.com',
              ),
              validator: (v) {
                final s = v?.trim() ?? '';
                if (s.isEmpty) return 'Enter a URL';
                if (s.contains(' ')) return 'URLs cannot contain spaces';
                return null;
              },
              onFieldSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('link-label'),
              controller: _label,
              decoration: const InputDecoration(labelText: 'Text (optional)'),
              onFieldSubmitted: (_) => _submit(),
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
      FilledButton(onPressed: _submit, child: const Text('Insert')),
    ],
  );
}
