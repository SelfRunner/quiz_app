import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/widgets/design_system.dart';
import '../../application/markdown_editing.dart';
import 'note_code_block.dart';

/// "Ctrl+B" / "⌘B" for tooltips.
String shortcutLabel(String key, {bool shift = false}) {
  final apple =
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.iOS;
  if (apple) return '${shift ? '⇧' : ''}⌘$key';
  return 'Ctrl+${shift ? 'Shift+' : ''}$key';
}

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
    this.trailing = const [],
  });

  final TextEditingController controller;
  final VoidCallback onInsertLink;
  final VoidCallback? onInsertImage;
  final FocusNode? focusNode;
  final bool imageBusy;

  /// Extra widgets at the end (e.g. the focus-mode toggle).
  final List<Widget> trailing;

  void _apply(TextEditingValue Function(TextEditingValue) edit) {
    controller.value = edit(controller.value);
    focusNode?.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final buttonStyle = IconButton.styleFrom(
      minimumSize: const Size.square(34),
      shape: const RoundedRectangleBorder(borderRadius: Radii.smAll),
    );
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
      style: buttonStyle,
    );

    Widget menu<T>(
      String key,
      IconData icon,
      String tooltip,
      List<PopupMenuEntry<T>> items,
      ValueChanged<T> onSelected,
    ) => PopupMenuButton<T>(
      key: Key('md-$key'),
      tooltip: tooltip,
      icon: Icon(icon, size: 18, color: colors.mutedText),
      style: buttonStyle,
      onSelected: onSelected,
      itemBuilder: (_) => items,
    );

    PopupMenuItem<T> item<T>(T value, String label, {IconData? icon}) =>
        PopupMenuItem<T>(
          value: value,
          height: 40,
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: colors.mutedText),
                Gaps.w12,
              ],
              Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
            ],
          ),
        );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(vertical: Insets.xs),
      child: Row(
        children: [
          menu<int>(
            'heading',
            Icons.title,
            'Heading',
            [
              for (var level = 1; level <= 3; level++)
                PopupMenuItem(
                  key: Key('md-heading-$level'),
                  value: level,
                  height: 40,
                  child: Text(
                    'Heading $level',
                    style: switch (level) {
                      1 => theme.textTheme.titleLarge,
                      2 => theme.textTheme.titleMedium,
                      _ => theme.textTheme.titleSmall,
                    },
                  ),
                ),
              const PopupMenuItem(
                key: Key('md-heading-0'),
                value: 0,
                height: 40,
                child: Text('Normal text'),
              ),
            ],
            (level) => _apply(
              (v) => level == 0
                  ? _stripHeading(v)
                  : MarkdownEditing.prefixLines(v, '${'#' * level} '),
            ),
          ),
          button(
            'bold',
            Icons.format_bold,
            'Bold (${shortcutLabel('B')})',
            () => _apply(
              (v) => MarkdownEditing.wrap(v, '**', '**', placeholder: 'bold'),
            ),
          ),
          button(
            'italic',
            Icons.format_italic,
            'Italic (${shortcutLabel('I')})',
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
          button(
            'code',
            Icons.code,
            'Inline code (${shortcutLabel('E')})',
            () => _apply(
              (v) => MarkdownEditing.wrap(v, '`', '`', placeholder: 'code'),
            ),
          ),
          const _ToolbarDivider(),
          button(
            'bullets',
            Icons.format_list_bulleted,
            'Bulleted list (${shortcutLabel('8', shift: true)})',
            () => _apply((v) => MarkdownEditing.toggleList(v, ListKind.bullet)),
          ),
          button(
            'numbers',
            Icons.format_list_numbered,
            'Numbered list (${shortcutLabel('7', shift: true)})',
            () =>
                _apply((v) => MarkdownEditing.toggleList(v, ListKind.numbered)),
          ),
          button(
            'checklist',
            Icons.checklist,
            'Checklist (${shortcutLabel('9', shift: true)})',
            () => _apply((v) => MarkdownEditing.toggleList(v, ListKind.task)),
          ),
          menu<String>(
            'quote',
            Icons.format_quote,
            'Quote or callout',
            [
              item('quote', 'Quote', icon: Icons.format_quote),
              item('NOTE', 'Note callout', icon: Icons.info_outline),
              item('TIP', 'Tip callout', icon: Icons.lightbulb_outline),
              item('IMPORTANT', 'Important callout', icon: Icons.priority_high),
              item(
                'WARNING',
                'Warning callout',
                icon: Icons.warning_amber_outlined,
              ),
              item('CAUTION', 'Caution callout', icon: Icons.report_outlined),
            ],
            (type) => _apply(
              (v) => type == 'quote'
                  ? MarkdownEditing.toggleList(v, ListKind.quote)
                  : MarkdownEditing.callout(v, type),
            ),
          ),
          const _ToolbarDivider(),
          button(
            'link',
            Icons.link,
            'Insert link (${shortcutLabel('K')})',
            onInsertLink,
          ),
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
          menu<(int, int)>(
            'table',
            Icons.table_chart_outlined,
            'Insert table',
            [
              item((2, 2), '2 × 2 table'),
              item((2, 3), '3 columns × 2 rows'),
              item((3, 4), '4 columns × 3 rows'),
            ],
            (size) => _apply(
              (v) => MarkdownEditing.table(v, rows: size.$1, columns: size.$2),
            ),
          ),
          menu<String>(
            'codeblock',
            Icons.data_object,
            'Code block',
            [
              item('', 'Plain text'),
              const PopupMenuDivider(),
              for (final entry in kCodeLanguages.entries)
                item(entry.key, entry.value),
            ],
            (language) =>
                _apply((v) => MarkdownEditing.codeBlock(v, language: language)),
          ),
          menu<bool>(
            'math',
            Icons.functions,
            'Math (LaTeX)',
            [
              item(false, r'Inline math  $x^2$'),
              item(true, r'Math block  $$ … $$'),
            ],
            (block) => _apply(
              (v) => block
                  ? MarkdownEditing.mathBlock(v)
                  : MarkdownEditing.mathInline(v),
            ),
          ),
          ...trailing,
        ],
      ),
    );
  }

  static TextEditingValue _stripHeading(TextEditingValue v) {
    final text = v.text;
    final sel = v.selection.isValid
        ? v.selection
        : TextSelection.collapsed(offset: text.length);
    final start = sel.start == 0
        ? 0
        : text.lastIndexOf('\n', sel.start - 1) + 1;
    final match = RegExp(r'^#{1,6} ').matchAsPrefix(text, start);
    if (match == null) return v;
    final removed = match.end - start;
    return TextEditingValue(
      text: text.replaceRange(start, match.end, ''),
      selection: TextSelection(
        baseOffset: (sel.baseOffset - removed).clamp(start, text.length),
        extentOffset: (sel.extentOffset - removed).clamp(start, text.length),
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
    if (!url.contains('://') &&
        !url.startsWith('mailto:') &&
        !url.startsWith('#')) {
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
                hintText: 'https://example.com or #heading',
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
