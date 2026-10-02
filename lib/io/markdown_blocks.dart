import 'package:markdown/markdown.dart' as md;
import 'package:meta/meta.dart';

/// Markdown -> a flat list of simple blocks with styled text spans (pure
/// Dart), for exporters that lay out text themselves (e.g. a PDF export in
/// the UI). GitHub-flavored: headings, paragraphs, (nested / ordered /
/// task) lists, fenced code, quotes, tables, rules, images and `$$` math
/// blocks.
List<MdBlock> markdownToBlocks(String markdown) {
  final document = md.Document(
    extensionSet: md.ExtensionSet.gitHubFlavored,
    encodeHtml: false,
  );
  final nodes = document.parse(markdown.replaceAll('\r\n', '\n'));
  final out = <MdBlock>[];
  _blocks(nodes, out, listDepth: 0);
  return out;
}

/// A run of text with one style.
@immutable
class MdSpan {
  const MdSpan(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.code = false,
    this.strike = false,
    this.link,
    this.imageUrl,
  });

  final String text;
  final bool bold;
  final bool italic;
  final bool code;
  final bool strike;

  /// Link target (`[text](link)`).
  final String? link;

  /// Inline image (`text` is its alt text).
  final String? imageUrl;

  MdSpan _with({
    bool? bold,
    bool? italic,
    bool? code,
    bool? strike,
    String? link,
  }) => MdSpan(
    text,
    bold: bold ?? this.bold,
    italic: italic ?? this.italic,
    code: code ?? this.code,
    strike: strike ?? this.strike,
    link: link ?? this.link,
    imageUrl: imageUrl,
  );

  @override
  bool operator ==(Object other) =>
      other is MdSpan &&
      other.text == text &&
      other.bold == bold &&
      other.italic == italic &&
      other.code == code &&
      other.strike == strike &&
      other.link == link &&
      other.imageUrl == imageUrl;

  @override
  int get hashCode =>
      Object.hash(text, bold, italic, code, strike, link, imageUrl);

  @override
  String toString() {
    final flags = [
      if (bold) 'b',
      if (italic) 'i',
      if (code) 'code',
      if (strike) 's',
      if (link != null) 'link=$link',
      if (imageUrl != null) 'img=$imageUrl',
    ];
    return flags.isEmpty ? '"$text"' : '"$text"(${flags.join(',')})';
  }
}

/// Plain text of [spans].
String spansText(List<MdSpan> spans) => spans.map((s) => s.text).join();

sealed class MdBlock {
  const MdBlock();
}

class MdHeading extends MdBlock {
  const MdHeading(this.level, this.spans);

  /// 1..6.
  final int level;
  final List<MdSpan> spans;

  String get text => spansText(spans);
}

class MdParagraph extends MdBlock {
  const MdParagraph(this.spans);

  final List<MdSpan> spans;

  String get text => spansText(spans);
}

/// One list item; nesting is expressed by [depth] (0 = top level).
class MdListItem extends MdBlock {
  const MdListItem(
    this.spans, {
    required this.depth,
    required this.ordered,
    this.number,
    this.checked,
  });

  final List<MdSpan> spans;
  final int depth;
  final bool ordered;

  /// Item number of an ordered list.
  final int? number;

  /// Task list state (null = not a task item).
  final bool? checked;

  String get text => spansText(spans);
}

class MdCode extends MdBlock {
  const MdCode(this.text, {this.language});

  final String text;
  final String? language;
}

/// A block quote with its own blocks.
class MdQuote extends MdBlock {
  const MdQuote(this.children);

  final List<MdBlock> children;
}

class MdTable extends MdBlock {
  const MdTable({required this.header, required this.rows});

  /// Header cells (may be empty).
  final List<List<MdSpan>> header;
  final List<List<List<MdSpan>>> rows;
}

class MdRule extends MdBlock {
  const MdRule();
}

/// A paragraph that only contains an image.
class MdImage extends MdBlock {
  const MdImage({required this.url, this.alt = ''});

  /// As written (e.g. `note-image://...`, resolve with `NoteImageRef`).
  final String url;
  final String alt;
}

/// A display math block (`$$ ... $$`), TeX source without the delimiters.
class MdMath extends MdBlock {
  const MdMath(this.tex);

  final String tex;
}

// -----------------------------------------------------------------------------

void _blocks(List<md.Node> nodes, List<MdBlock> out, {required int listDepth}) {
  for (final node in nodes) {
    if (node is md.Text) {
      final text = node.text.trim();
      if (text.isNotEmpty) out.add(MdParagraph([MdSpan(text)]));
      continue;
    }
    if (node is! md.Element) continue;
    final tag = node.tag;
    switch (tag) {
      case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
        out.add(MdHeading(int.parse(tag.substring(1)), _inline(node.children)));
      case 'p':
        out.add(_paragraph(node));
      case 'ul' || 'ol':
        _list(node, out, depth: listDepth);
      case 'pre':
        final code = node.children?.whereType<md.Element>().firstOrNull;
        final cls = code?.attributes['class'];
        out.add(
          MdCode(
            (code ?? node).textContent.replaceFirst(RegExp(r'\n$'), ''),
            language: cls != null && cls.startsWith('language-')
                ? cls.substring(9)
                : null,
          ),
        );
      case 'blockquote':
        final children = <MdBlock>[];
        _blocks(node.children ?? const [], children, listDepth: 0);
        out.add(MdQuote(children));
      case 'hr':
        out.add(const MdRule());
      case 'table':
        out.add(_table(node));
      default:
        final text = node.textContent.trim();
        if (text.isNotEmpty) out.add(MdParagraph([MdSpan(text)]));
    }
  }
}

MdBlock _paragraph(md.Element p) {
  final children = p.children ?? const <md.Node>[];
  final meaningful = children
      .where((c) => !(c is md.Text && c.text.trim().isEmpty))
      .toList();
  if (meaningful.length == 1 &&
      meaningful.single is md.Element &&
      (meaningful.single as md.Element).tag == 'img') {
    final img = meaningful.single as md.Element;
    return MdImage(
      url: img.attributes['src'] ?? '',
      alt: img.attributes['alt'] ?? '',
    );
  }
  final text = p.textContent.trim();
  if (text.length >= 4 && text.startsWith(r'$$') && text.endsWith(r'$$')) {
    return MdMath(text.substring(2, text.length - 2).trim());
  }
  return MdParagraph(_inline(children));
}

void _list(md.Element list, List<MdBlock> out, {required int depth}) {
  final ordered = list.tag == 'ol';
  var number = int.tryParse(list.attributes['start'] ?? '') ?? 1;
  for (final li
      in (list.children ?? const <md.Node>[]).whereType<md.Element>().where(
        (e) => e.tag == 'li',
      )) {
    bool? checked;
    final inline = <md.Node>[];
    final nested = <md.Element>[];
    void collect(List<md.Node> nodes) {
      for (final child in nodes) {
        if (child is md.Element) {
          if (child.tag == 'input' && child.attributes['type'] == 'checkbox') {
            checked = child.attributes['checked'] != null;
            continue;
          }
          if (child.tag == 'p') {
            if (inline.isNotEmpty) inline.add(md.Text('\n'));
            collect(child.children ?? const []);
            continue;
          }
          if (const {
            'ul',
            'ol',
            'pre',
            'blockquote',
            'table',
          }.contains(child.tag)) {
            nested.add(child);
            continue;
          }
        }
        inline.add(child);
      }
    }

    collect(li.children ?? const []);
    out.add(
      MdListItem(
        _trimSpans(_inline(inline)),
        depth: depth,
        ordered: ordered,
        number: ordered ? number : null,
        checked: checked,
      ),
    );
    number++;
    for (final child in nested) {
      if (child.tag == 'ul' || child.tag == 'ol') {
        _list(child, out, depth: depth + 1);
      } else {
        _blocks([child], out, listDepth: depth + 1);
      }
    }
  }
}

MdTable _table(md.Element table) {
  final header = <List<MdSpan>>[];
  final rows = <List<List<MdSpan>>>[];
  for (final section
      in (table.children ?? const <md.Node>[]).whereType<md.Element>()) {
    for (final tr
        in (section.children ?? const <md.Node>[])
            .whereType<md.Element>()
            .where((e) => e.tag == 'tr')) {
      final cells = [
        for (final cell
            in (tr.children ?? const <md.Node>[]).whereType<md.Element>())
          _trimSpans(_inline(cell.children ?? const [])),
      ];
      if (section.tag == 'thead') {
        header.addAll(cells);
      } else {
        rows.add(cells);
      }
    }
  }
  return MdTable(header: header, rows: rows);
}

List<MdSpan> _inline(List<md.Node>? nodes, [MdSpan style = const MdSpan('')]) {
  final out = <MdSpan>[];
  for (final node in nodes ?? const <md.Node>[]) {
    if (node is md.Text) {
      if (node.text.isNotEmpty) {
        out.add(
          MdSpan(
            node.text,
            bold: style.bold,
            italic: style.italic,
            code: style.code,
            strike: style.strike,
            link: style.link,
          ),
        );
      }
      continue;
    }
    if (node is! md.Element) continue;
    switch (node.tag) {
      case 'strong':
        out.addAll(_inline(node.children, style._with(bold: true)));
      case 'em':
        out.addAll(_inline(node.children, style._with(italic: true)));
      case 'del':
        out.addAll(_inline(node.children, style._with(strike: true)));
      case 'code':
        out.add(
          MdSpan(
            node.textContent,
            bold: style.bold,
            italic: style.italic,
            code: true,
            strike: style.strike,
            link: style.link,
          ),
        );
      case 'a':
        out.addAll(
          _inline(node.children, style._with(link: node.attributes['href'])),
        );
      case 'img':
        out.add(
          MdSpan(
            node.attributes['alt'] ?? '',
            imageUrl: node.attributes['src'],
          ),
        );
      case 'br':
        out.add(const MdSpan('\n'));
      case 'input':
        break;
      default:
        out.addAll(_inline(node.children, style));
    }
  }
  return _merge(out);
}

/// Merges adjacent spans with the same style.
List<MdSpan> _merge(List<MdSpan> spans) {
  final out = <MdSpan>[];
  for (final s in spans) {
    final last = out.isEmpty ? null : out.last;
    if (last != null &&
        last.imageUrl == null &&
        s.imageUrl == null &&
        last.bold == s.bold &&
        last.italic == s.italic &&
        last.code == s.code &&
        last.strike == s.strike &&
        last.link == s.link) {
      out[out.length - 1] = MdSpan(
        last.text + s.text,
        bold: s.bold,
        italic: s.italic,
        code: s.code,
        strike: s.strike,
        link: s.link,
      );
    } else {
      out.add(s);
    }
  }
  return out;
}

List<MdSpan> _trimSpans(List<MdSpan> spans) {
  if (spans.isEmpty) return spans;
  final out = List<MdSpan>.of(spans);
  MdSpan retext(MdSpan s, String text) => MdSpan(
    text,
    bold: s.bold,
    italic: s.italic,
    code: s.code,
    strike: s.strike,
    link: s.link,
    imageUrl: s.imageUrl,
  );
  out[0] = retext(out.first, out.first.text.trimLeft());
  out[out.length - 1] = retext(out.last, out.last.text.trimRight());
  return out.where((s) => s.text.isNotEmpty || s.imageUrl != null).toList();
}
