import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;

import '../../../../core/widgets/design_system.dart';
import '../../../../core/widgets/error_message.dart';
import '../../../../core/widgets/note_markdown.dart' show NoteMarkdownImage;
import '../../application/note_markdown_syntax.dart';
import 'note_code_block.dart';

/// Stable keys for a note's headings (by index), shared by the renderer and
/// a table of contents so it can scroll to a heading.
class NoteAnchors {
  final Map<int, GlobalKey> _keys = {};

  GlobalKey keyFor(int index) => _keys.putIfAbsent(
    index,
    () => GlobalKey(debugLabel: 'note-heading-$index'),
  );

  /// Scrolls the enclosing scrollable so heading [index] is at the top.
  Future<void> reveal(int index) async {
    final context = _keys[index]?.currentContext;
    if (context == null || !context.mounted) return;
    await Scrollable.ensureVisible(
      context,
      duration: Motion.slow,
      curve: Curves.easeOutCubic,
      alignment: 0.02,
    );
  }
}

/// Renders note Markdown: GitHub flavored Markdown plus LaTeX math
/// (`$...$`, `$$...$$`), highlighted code blocks with copy, styled
/// scrollable tables, task lists (toggleable via [onToggleTask]), callouts
/// (`> [!NOTE]` / `[!TIP]` / `[!IMPORTANT]` / `[!WARNING]` / `[!CAUTION]`),
/// heading anchors (`[link](#slug)` scrolls) and `note-image://` images.
class RichNoteMarkdown extends StatefulWidget {
  const RichNoteMarkdown({
    super.key,
    required this.data,
    this.anchors,
    this.onToggleTask,
    this.selectable = true,
  });

  final String data;

  /// Keys for the headings (pass the same instance to a table of contents).
  final NoteAnchors? anchors;

  /// Called with the task index (document order) and its new state. Null
  /// renders read-only checkboxes.
  final void Function(int index, bool checked)? onToggleTask;

  /// Wraps the content in a [SelectionArea].
  final bool selectable;

  @override
  State<RichNoteMarkdown> createState() => _RichNoteMarkdownState();
}

class _RichNoteMarkdownState extends State<RichNoteMarkdown>
    implements MarkdownBuilderDelegate {
  final List<GestureRecognizer> _recognizers = [];
  late NoteAnchors _anchors = widget.anchors ?? NoteAnchors();
  NoteMarkdownAst? _ast;
  List<Widget> _children = const [];
  MarkdownStyleSheet? _styleSheet;
  int _taskCursor = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _parse();
  }

  @override
  void didUpdateWidget(RichNoteMarkdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.anchors != oldWidget.anchors) {
      _anchors = widget.anchors ?? NoteAnchors();
    }
    if (widget.data != oldWidget.data ||
        widget.anchors != oldWidget.anchors ||
        (widget.onToggleTask == null) != (oldWidget.onToggleTask == null)) {
      _parse();
    }
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  void _parse() {
    _disposeRecognizers();
    _styleSheet = _buildStyleSheet(context);
    final ast = parseNoteMarkdown(widget.data);
    _ast = ast;
    _taskCursor = 0;
    _children = _buildNodes(ast.nodes);
  }

  List<Widget> _buildNodes(List<md.Node> nodes) {
    final builder = MarkdownBuilder(
      delegate: this,
      selectable: false,
      styleSheet: _styleSheet!,
      imageDirectory: null,
      imageBuilder: (uri, title, alt) => NoteMarkdownImage(uri: uri, alt: alt),
      checkboxBuilder: _checkbox,
      bulletBuilder: null,
      builders: {
        NoteTags.heading: _BlockBuilder(_heading),
        NoteTags.callout: _BlockBuilder(_callout),
        NoteTags.code: _BlockBuilder(
          (e) => NoteCodeBlock(
            code: e.attributes['code'] ?? '',
            language: e.attributes['language'] ?? '',
          ),
        ),
        NoteTags.mathBlock: _BlockBuilder(_mathBlock),
        NoteTags.mathInline: _InlineMathBuilder(_styleSheet!),
      },
      paddingBuilders: const {},
      listItemCrossAxisAlignment: MarkdownListItemCrossAxisAlignment.start,
    );
    return builder.build(nodes);
  }

  // ---- MarkdownBuilderDelegate ----

  @override
  GestureRecognizer createLink(String text, String? href, String title) {
    final recognizer = TapGestureRecognizer()..onTap = () => _onTapLink(href);
    _recognizers.add(recognizer);
    return recognizer;
  }

  @override
  TextSpan formatText(MarkdownStyleSheet styleSheet, String code) => TextSpan(
    style: styleSheet.code,
    text: code.replaceAll(RegExp(r'\n$'), ''),
  );

  void _onTapLink(String? href) {
    if (href == null || href.isEmpty) return;
    if (href.startsWith('#')) {
      final slug = Uri.decodeComponent(href.substring(1));
      final heading = _ast?.headings.where((h) => h.slug == slug).firstOrNull;
      if (heading != null) {
        _anchors.reveal(heading.index).ignore();
        return;
      }
    }
    Clipboard.setData(ClipboardData(text: href)).ignore();
    showAppSnackBar(context, 'Link copied: $href');
  }

  // ---- Element builders ----

  Widget _checkbox(bool checked) {
    final order = _ast?.taskBuildOrder ?? const <int>[];
    final index = _taskCursor < order.length ? order[_taskCursor] : -1;
    _taskCursor++;
    final onToggle = widget.onToggleTask;
    return _TaskCheckbox(
      key: index >= 0 ? Key('note-task-$index') : null,
      checked: checked,
      onChanged: onToggle == null || index < 0
          ? null
          : () => widget.onToggleTask?.call(index, !checked),
    );
  }

  Widget _heading(md.Element element) {
    final index = int.tryParse(element.attributes['index'] ?? '') ?? 0;
    final slug = element.attributes['slug'] ?? '';
    final original = _ast!.childrenOf(element);
    final title = original.isEmpty ? '' : original.first.textContent;
    return _HeadingAnchor(
      key: _anchors.keyFor(index),
      slug: slug,
      title: title,
      child: _column(_buildNodes(original)),
    );
  }

  Widget _callout(md.Element element) {
    final type = element.attributes['type'] ?? 'note';
    return NoteCallout(
      type: type,
      child: _column(_buildNodes(_ast!.childrenOf(element))),
    );
  }

  Widget _mathBlock(md.Element element) {
    final tex = element.attributes['tex'] ?? '';
    final style = _styleSheet!.p;
    return _ScrollableMath(
      child: Math.tex(
        tex,
        key: const Key('note-math-block'),
        mathStyle: MathStyle.display,
        textStyle: style?.copyWith(fontSize: (style.fontSize ?? 16) * 1.1),
        onErrorFallback: (e) => MathError(tex: tex, message: e.message),
      ),
    );
  }

  Widget _column(List<Widget> children) => children.length == 1
      ? children.single
      : Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: children,
        );

  @override
  Widget build(BuildContext context) {
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: _children,
    );
    return widget.selectable ? SelectionArea(child: body) : body;
  }
}

MarkdownStyleSheet _buildStyleSheet(BuildContext context) {
  final theme = Theme.of(context);
  final colors = AppColors.of(context);
  final text = theme.textTheme;
  final body = text.bodyLarge?.copyWith(height: 1.65);
  final mono = text.bodyMedium?.copyWith(
    fontFamily: 'monospace',
    fontFamilyFallback: const ['Menlo', 'Consolas', 'Courier New'],
    fontSize: (body?.fontSize ?? 16) * 0.88,
    backgroundColor: colors.hover,
    color: theme.colorScheme.onSurface,
  );
  return MarkdownStyleSheet.fromTheme(theme).copyWith(
    p: body,
    listBullet: body?.copyWith(color: colors.mutedText),
    h1: text.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
    h2: text.titleLarge?.copyWith(fontWeight: FontWeight.w600),
    h3: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    h4: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
    h5: text.titleSmall,
    h6: text.titleSmall?.copyWith(color: colors.mutedText),
    h1Padding: const EdgeInsets.only(top: Insets.md),
    h2Padding: const EdgeInsets.only(top: Insets.sm),
    h3Padding: const EdgeInsets.only(top: Insets.xs),
    blockSpacing: Insets.md,
    code: mono,
    a: TextStyle(
      color: theme.colorScheme.primary,
      decoration: TextDecoration.underline,
      decorationColor: theme.colorScheme.primary.withValues(alpha: 0.4),
    ),
    blockquote: body?.copyWith(color: colors.mutedText),
    blockquotePadding: const EdgeInsets.fromLTRB(Insets.lg, 2, 0, 2),
    blockquoteDecoration: BoxDecoration(
      border: Border(left: BorderSide(color: colors.border, width: 3)),
    ),
    horizontalRuleDecoration: BoxDecoration(
      border: Border(top: BorderSide(color: colors.hairline)),
    ),
    tableHead: body?.copyWith(fontWeight: FontWeight.w600),
    tableBody: body,
    tableHeadAlign: TextAlign.left,
    tableBorder: TableBorder.all(
      color: colors.hairline,
      borderRadius: Radii.mdAll,
    ),
    tableColumnWidth: const IntrinsicColumnWidth(),
    tableCellsPadding: const EdgeInsets.symmetric(
      horizontal: Insets.md,
      vertical: Insets.sm,
    ),
    tableHeadCellsDecoration: BoxDecoration(color: colors.sidebar),
    tableCellsDecoration: const BoxDecoration(),
    tableScrollbarThumbVisibility: false,
    tablePadding: const EdgeInsets.only(bottom: Insets.xs),
    checkbox: body?.copyWith(color: colors.mutedText),
    listIndent: 26,
  );
}

class _BlockBuilder extends MarkdownElementBuilder {
  _BlockBuilder(this.build);

  final Widget Function(md.Element element) build;

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) => build(element);
}

class _InlineMathBuilder extends MarkdownElementBuilder {
  _InlineMathBuilder(this.styleSheet);

  final MarkdownStyleSheet styleSheet;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final tex = element.textContent;
    final style = parentStyle ?? styleSheet.p;
    final display = element.attributes['display'] == 'true';
    return Text.rich(
      WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Math.tex(
          tex,
          key: const Key('note-math-inline'),
          mathStyle: display ? MathStyle.display : MathStyle.text,
          textStyle: style,
          onErrorFallback: (e) => Text(
            '\$$tex\$',
            style: style?.copyWith(
              fontFamily: 'monospace',
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        ),
      ),
    );
  }
}

/// A TeX parse error shown in place of a formula.
class MathError extends StatelessWidget {
  const MathError({super.key, required this.tex, required this.message});

  final String tex;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Tooltip(
      message: message,
      child: Text(
        tex,
        style: Theme.of(context).textTheme.bodyMedium
            ?.copyWith(fontFamily: 'monospace', color: colors.danger),
      ),
    );
  }
}

class _ScrollableMath extends StatefulWidget {
  const _ScrollableMath({required this.child});

  final Widget child;

  @override
  State<_ScrollableMath> createState() => _ScrollableMathState();
}

class _ScrollableMathState extends State<_ScrollableMath> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: Insets.xs),
    child: LayoutBuilder(
      builder: (context, constraints) => Scrollbar(
        controller: _controller,
        child: SingleChildScrollView(
          controller: _controller,
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: Center(child: widget.child),
          ),
        ),
      ),
    ),
  );
}

class _TaskCheckbox extends StatelessWidget {
  const _TaskCheckbox({super.key, required this.checked, this.onChanged});

  final bool checked;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final icon = Icon(
      checked ? Icons.check_box : Icons.check_box_outline_blank,
      size: 20,
      color: checked ? theme.colorScheme.primary : colors.mutedText,
    );
    return Semantics(
      checked: checked,
      enabled: onChanged != null,
      label: checked ? 'Completed task' : 'Open task',
      child: Padding(
        padding: const EdgeInsets.only(top: 3, right: Insets.xs),
        child: Align(
          alignment: Alignment.topLeft,
          child: onChanged == null
              ? Padding(padding: const EdgeInsets.all(2), child: icon)
              : InkWell(
                  borderRadius: Radii.xsAll,
                  onTap: onChanged,
                  child: Padding(padding: const EdgeInsets.all(2), child: icon),
                ),
        ),
      ),
    );
  }
}

/// A heading with a hover "copy link" button (`[Title](#slug)`).
class _HeadingAnchor extends StatefulWidget {
  const _HeadingAnchor({
    super.key,
    required this.slug,
    required this.title,
    required this.child,
  });

  final String slug;
  final String title;
  final Widget child;

  @override
  State<_HeadingAnchor> createState() => _HeadingAnchorState();
}

class _HeadingAnchorState extends State<_HeadingAnchor> {
  bool _hover = false;

  Future<void> _copy() async {
    await Clipboard.setData(
      ClipboardData(text: '[${widget.title}](#${widget.slug})'),
    );
    if (mounted) showAppSnackBar(context, 'Heading link copied');
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          widget.child,
          Positioned(
            right: 0,
            bottom: 0,
            child: AnimatedOpacity(
              opacity: _hover ? 1 : 0,
              duration: Motion.fast,
              child: IgnorePointer(
                ignoring: !_hover,
                child: IconButton(
                  tooltip: 'Copy link to heading',
                  iconSize: 16,
                  visualDensity: VisualDensity.compact,
                  color: colors.faintText,
                  icon: const Icon(Icons.link),
                  onPressed: _copy,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Minimal callout box for GitHub alerts.
class NoteCallout extends StatelessWidget {
  const NoteCallout({super.key, required this.type, required this.child});

  /// note, tip, important, warning or caution.
  final String type;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final (
      IconData icon,
      String label,
      Color accent,
      Color fill,
    ) = switch (type) {
      'tip' => (
        Icons.lightbulb_outline,
        'Tip',
        colors.success,
        colors.successContainer,
      ),
      'important' => (
        Icons.priority_high,
        'Important',
        theme.colorScheme.primary,
        theme.colorScheme.primaryContainer,
      ),
      'warning' => (
        Icons.warning_amber_outlined,
        'Warning',
        colors.warning,
        colors.warningContainer,
      ),
      'caution' => (
        Icons.report_outlined,
        'Caution',
        colors.danger,
        colors.dangerContainer,
      ),
      _ => (Icons.info_outline, 'Note', colors.info, colors.infoContainer),
    };
    return Container(
      key: Key('note-callout-$type'),
      decoration: BoxDecoration(
        color: fill.withValues(alpha: 0.35),
        borderRadius: Radii.mdAll,
        border: Border(left: BorderSide(color: accent, width: 3)),
      ),
      padding: const EdgeInsets.fromLTRB(
        Insets.md,
        Insets.sm,
        Insets.md,
        Insets.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: accent),
              Gaps.w8,
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(color: accent),
              ),
            ],
          ),
          Gaps.h4,
          child,
        ],
      ),
    );
  }
}
