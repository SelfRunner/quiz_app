import 'dart:convert';

import 'package:markdown/markdown.dart' as md;

/// Custom element tags produced by [parseNoteMarkdown] (rendered by
/// `RichNoteMarkdown`).
abstract final class NoteTags {
  /// Inline math: `$...$` (text style) or `$$...$$` inside a paragraph
  /// (display style). One [md.Text] child with the TeX source; attribute
  /// `display` = `true` / `false`.
  static const mathInline = 'x-math-inline';

  /// Block math (`$$` on its own lines). Attribute `tex`.
  static const mathBlock = 'x-math';

  /// A heading (h1-h6) with anchor data. Attributes `index`, `level`,
  /// `slug`; the original heading element is in [NoteMarkdownAst.childrenOf].
  static const heading = 'x-heading';

  /// GitHub alert (`> [!NOTE]`, `[!TIP]`, `[!IMPORTANT]`, `[!WARNING]`,
  /// `[!CAUTION]`). Attribute `type`; content in [NoteMarkdownAst.childrenOf].
  static const callout = 'x-callout';

  /// Fenced / indented code block. Attributes `language` (may be empty) and
  /// `code`.
  static const code = 'x-code';
}

/// `$x^2$`, `$$\sum$$` inside text. The opening `$` must not be followed by
/// a space and the closing one must not follow a space or precede a digit,
/// so prices like "$5 and $10" stay plain text. `\$` is a literal dollar.
class MathInlineSyntax extends md.InlineSyntax {
  MathInlineSyntax()
    : super(
        r'\$\$([^\n$]+?)\$\$|\$(?![\s$])((?:\\.|[^\\$\n])+?)(?<!\s)\$(?!\d)',
        startCharacter: 0x24,
      );

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final display = match[1] != null;
    final tex = (match[1] ?? match[2] ?? '').trim();
    if (tex.isEmpty) return false;
    parser.addNode(
      md.Element(NoteTags.mathInline, [md.Text(tex)])
        ..attributes['display'] = '$display',
    );
    return true;
  }
}

/// Block math:
///
/// ```text
/// $$
/// \int_0^1 x^2 \, dx
/// $$
/// ```
///
/// or `$$ E = mc^2 $$` on one line. An unclosed `$$` stays a paragraph.
class MathBlockSyntax extends md.BlockSyntax {
  const MathBlockSyntax();

  static final RegExp _open = RegExp(r'^ {0,3}\$\$(.*)$');

  @override
  RegExp get pattern => _open;

  static bool _closesOnFirstLine(String rest) {
    final t = rest.trimRight();
    return t.length >= 3 && t.endsWith(r'$$');
  }

  @override
  bool canParse(md.BlockParser parser) {
    final match = _open.firstMatch(parser.current.content);
    if (match == null) return false;
    if (_closesOnFirstLine(match[1]!)) return true;
    for (var i = 1; ; i++) {
      final line = parser.peek(i);
      if (line == null) return false;
      if (line.content.trimRight().endsWith(r'$$')) return true;
    }
  }

  @override
  md.Node? parse(md.BlockParser parser) {
    final rest = _open.firstMatch(parser.current.content)![1]!;
    final lines = <String>[];
    if (_closesOnFirstLine(rest)) {
      final t = rest.trimRight();
      lines.add(t.substring(0, t.length - 2));
      parser.advance();
    } else {
      if (rest.trim().isNotEmpty) lines.add(rest);
      parser.advance();
      while (!parser.isDone) {
        final t = parser.current.content.trimRight();
        parser.advance();
        if (t.endsWith(r'$$')) {
          lines.add(t.substring(0, t.length - 2));
          break;
        }
        lines.add(t);
      }
    }
    return md.Element.empty(NoteTags.mathBlock)
      ..attributes['tex'] = lines.join('\n').trim();
  }
}

/// One heading of a note (for the table of contents and anchors).
class NoteHeading {
  const NoteHeading({
    required this.index,
    required this.level,
    required this.text,
    required this.slug,
  });

  /// Position among the note's headings (0-based, document order).
  final int index;

  /// 1-6.
  final int level;
  final String text;

  /// GitHub-style anchor id (`#slug`), unique within the note.
  final String slug;

  @override
  String toString() => 'NoteHeading($level, $text, #$slug)';
}

/// Parsed note: the AST (with [NoteTags] elements) plus derived data.
class NoteMarkdownAst {
  NoteMarkdownAst._(
    this.nodes,
    this.headings,
    this.taskCount,
    this.taskBuildOrder,
    this._stash,
  );

  final List<md.Node> nodes;
  final List<NoteHeading> headings;

  /// Number of task-list items (`- [ ]` / `- [x]`).
  final int taskCount;

  /// Task indices (document order) in the order a Markdown widget builder
  /// completes their list items (post-order: nested items first).
  final List<int> taskBuildOrder;

  final Expando<List<md.Node>> _stash;

  /// Content of a [NoteTags.heading] (the original heading element) or a
  /// [NoteTags.callout] (its blocks). Kept out of the element itself so the
  /// outer builder does not render it twice.
  List<md.Node> childrenOf(md.Element element) =>
      _stash[element] ?? element.children ?? const [];
}

/// The Markdown document used for notes: GitHub flavored + math + alerts.
md.Document noteMarkdownDocument() => md.Document(
  extensionSet: md.ExtensionSet.gitHubFlavored,
  blockSyntaxes: const [MathBlockSyntax(), md.AlertBlockSyntax()],
  inlineSyntaxes: [MathInlineSyntax()],
  encodeHtml: false,
);

const _headingTags = {'h1', 'h2', 'h3', 'h4', 'h5', 'h6'};

/// Parses note Markdown and rewrites the AST for `RichNoteMarkdown`:
/// headings -> [NoteTags.heading], alerts -> [NoteTags.callout], code
/// blocks -> [NoteTags.code], task checkboxes get a `data-task` index (and
/// are moved to the front of loose list items so they render as the item's
/// bullet).
NoteMarkdownAst parseNoteMarkdown(String markdown) {
  final lines = const LineSplitter().convert(markdown);
  final nodes = noteMarkdownDocument().parseLines(lines);
  final ctx = _Ctx();
  _rewrite(nodes, ctx);
  final order = <int>[];
  _postOrderTasks(nodes, ctx.stash, order);
  return NoteMarkdownAst._(nodes, ctx.headings, ctx.tasks, order, ctx.stash);
}

/// Headings of [markdown] in document order.
List<NoteHeading> noteHeadings(String markdown) =>
    parseNoteMarkdown(markdown).headings;

class _Ctx {
  final headings = <NoteHeading>[];
  final slugCounts = <String, int>{};
  final stash = Expando<List<md.Node>>('note-markdown-children');
  int tasks = 0;

  String uniqueSlug(String text) {
    var base = slugify(text);
    if (base.isEmpty) base = 'section';
    final n = slugCounts[base] ?? 0;
    slugCounts[base] = n + 1;
    return n == 0 ? base : '$base-$n';
  }
}

/// GitHub-style heading slug: lowercase, punctuation removed, spaces to `-`.
String slugify(String text) => text
    .toLowerCase()
    .replaceAll(RegExp(r'[^\p{L}\p{N}\s_-]', unicode: true), '')
    .trim()
    .replaceAll(RegExp(r'\s+'), '-');

bool _isCheckbox(md.Node? node) =>
    node is md.Element &&
    node.tag == 'input' &&
    node.attributes['type'] == 'checkbox';

void _rewrite(List<md.Node> nodes, _Ctx ctx) {
  for (var i = 0; i < nodes.length; i++) {
    final node = nodes[i];
    if (node is! md.Element) continue;
    final tag = node.tag;

    if (_headingTags.contains(tag)) {
      final index = ctx.headings.length;
      final text = node.textContent.replaceAll(RegExp(r'\s+'), ' ').trim();
      final slug = ctx.uniqueSlug(text);
      final level = int.parse(tag.substring(1));
      ctx.headings.add(
        NoteHeading(index: index, level: level, text: text, slug: slug),
      );
      final anchor = md.Element.empty(NoteTags.heading)
        ..attributes.addAll({
          'index': '$index',
          'level': '$level',
          'slug': slug,
        });
      ctx.stash[anchor] = [node];
      nodes[i] = anchor;
      continue;
    }

    final cls = node.attributes['class'] ?? '';
    if (tag == 'div' && cls.contains('markdown-alert')) {
      final type =
          RegExp(r'markdown-alert-(\w+)').firstMatch(cls)?.group(1) ?? 'note';
      final children = [...?node.children];
      if (children.isNotEmpty &&
          children.first is md.Element &&
          (children.first as md.Element).attributes['class'] ==
              'markdown-alert-title') {
        children.removeAt(0);
      }
      _rewrite(children, ctx);
      final callout = md.Element.empty(NoteTags.callout)
        ..attributes['type'] = type;
      ctx.stash[callout] = children;
      nodes[i] = callout;
      continue;
    }

    if (tag == 'pre') {
      final code = node.children?.whereType<md.Element>().firstOrNull;
      final language =
          RegExp(r'language-(\S+)')
              .firstMatch(code?.attributes['class'] ?? '')
              ?.group(1) ??
          '';
      var text = code?.textContent ?? node.textContent;
      if (text.endsWith('\n')) text = text.substring(0, text.length - 1);
      nodes[i] = md.Element.empty(NoteTags.code)
        ..attributes['language'] = language
        ..attributes['code'] = text;
      continue;
    }

    if (tag == 'li') {
      // Loose task items have the checkbox inside their first paragraph;
      // move it to the front so it renders as the item's bullet.
      final children = node.children;
      if (children != null && children.isNotEmpty) {
        final first = children.first;
        if (first is md.Element &&
            first.tag == 'p' &&
            first.children != null &&
            first.children!.isNotEmpty &&
            _isCheckbox(first.children!.first)) {
          children.insert(0, first.children!.removeAt(0));
        }
      }
    }

    if (_isCheckbox(node)) {
      node.attributes['data-task'] = '${ctx.tasks++}';
    }

    final children = node.children;
    if (children != null) _rewrite(children, ctx);
  }
}

void _postOrderTasks(
  List<md.Node> nodes,
  Expando<List<md.Node>> stash,
  List<int> out,
) {
  for (final node in nodes) {
    if (node is! md.Element) continue;
    _postOrderTasks(stash[node] ?? node.children ?? const [], stash, out);
    if (node.tag == 'li') {
      final first = node.children?.firstOrNull;
      if (_isCheckbox(first)) {
        final index = int.tryParse(
          (first! as md.Element).attributes['data-task'] ?? '',
        );
        if (index != null) out.add(index);
      }
    }
  }
}
