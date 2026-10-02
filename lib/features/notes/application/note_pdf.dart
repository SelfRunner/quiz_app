import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../data/models/models.dart';
import '../../../io/markdown_blocks.dart';

/// Loads an image for the PDF (a `note-image://` reference or a web URL);
/// null when unavailable. Errors are treated like null.
typedef PdfImageLoader = Future<Uint8List?> Function(String url);

/// A4 PDF of [note] built with the pure-Dart `pdf` package (works on web,
/// desktop and mobile): title, meta line (subject, updated date, tags) and
/// the Markdown body via `markdownToBlocks` — headings, paragraphs with
/// bold / italic / code / strike / links, nested ordered / bullet / task
/// lists, code blocks, quotes, tables, rules and images ([loadImage],
/// best effort: an "[Image: alt]" line when missing or undecodable). Math
/// is shown as its TeX source.
///
/// Uses the PDF standard fonts (no embedding), which cover Latin-1 only:
/// common typographic characters are mapped to ASCII and anything else
/// becomes `?` (see [pdfSafeText]).
Future<Uint8List> noteToPdf(
  Note note, {
  String? subjectTitle,
  PdfImageLoader? loadImage,
  DateTime? now,
}) async {
  final blocks = markdownToBlocks(note.contentMd);
  final images = <String, pw.ImageProvider?>{};
  if (loadImage != null) {
    for (final url in _imageUrls(blocks)) {
      images[url] = await _loadPdfImage(loadImage, url);
    }
  }
  final builder = _PdfNoteBuilder(images);
  final title = note.title.trim().isEmpty ? 'Untitled note' : note.title;
  final meta = [
    if (subjectTitle != null && subjectTitle.trim().isNotEmpty) subjectTitle,
    'Updated ${DateFormat.yMMMd().format(note.updatedAt.toLocal())}',
    if (note.tags.isNotEmpty) note.tags.map((t) => '#$t').join('  '),
  ].join('  ·  ');

  final doc = pw.Document(
    title: pdfSafeText(title),
    subject: subjectTitle == null ? null : pdfSafeText(subjectTitle),
    keywords: note.tags.isEmpty ? null : pdfSafeText(note.tags.join(', ')),
    creator: 'Quiz & Notes',
  );
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(56, 56, 56, 48),
      maxPages: 1000,
      footer: (context) => pw.Container(
        alignment: pw.Alignment.centerRight,
        margin: const pw.EdgeInsets.only(top: 12),
        child: pw.Text(
          '${context.pageNumber} / ${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 8, color: _muted),
        ),
      ),
      build: (context) => [
        pw.Text(
          pdfSafeText(title),
          style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 6),
        pw.Text(
          pdfSafeText(meta),
          style: const pw.TextStyle(fontSize: 9, color: _muted),
        ),
        pw.SizedBox(height: 10),
        pw.Divider(color: _hairline, thickness: 0.6),
        pw.SizedBox(height: 6),
        ...builder.blocks(blocks),
      ],
    ),
  );
  return doc.save();
}

const PdfColor _muted = PdfColor.fromInt(0xFF6B6B6B);
const PdfColor _hairline = PdfColor.fromInt(0xFFDDDDDB);
const PdfColor _codeBackground = PdfColor.fromInt(0xFFF3F3F1);
const PdfColor _link = PdfColor.fromInt(0xFF4F46E5);
const double _bodySize = 11;

/// [text] limited to what the PDF standard fonts can draw (Latin-1): smart
/// quotes, dashes, ellipsis, bullets, arrows and a few math symbols become
/// ASCII, tabs four spaces, other characters `?`.
String pdfSafeText(String text) {
  final out = StringBuffer();
  for (final rune in text.runes) {
    if (rune == 0x09) {
      out.write('    ');
    } else if (rune == 0x0A || (rune >= 0x20 && rune <= 0x7E)) {
      out.writeCharCode(rune);
    } else if (rune >= 0xA0 && rune <= 0xFF) {
      out.writeCharCode(rune);
    } else if (_replacements[rune] case final r?) {
      out.write(r);
    } else if (rune == 0x0D || (rune >= 0xFE00 && rune <= 0xFE0F)) {
      // Carriage returns and emoji variation selectors: drop.
    } else if (rune == 0x200B || rune == 0x200D || rune == 0xFEFF) {
      // Zero-width characters: drop.
    } else {
      out.write('?');
    }
  }
  return out.toString();
}

const Map<int, String> _replacements = {
  0x2018: "'", 0x2019: "'", 0x201A: "'", 0x201B: "'", //
  0x201C: '"', 0x201D: '"', 0x201E: '"', 0x201F: '"', //
  0x2010: '-', 0x2011: '-', 0x2012: '-', 0x2013: '-', 0x2014: '-', //
  0x2015: '-', 0x2212: '-', 0x2026: '...', 0x2022: '*', //
  0x2023: '>', 0x2043: '-', 0x25CF: '*', 0x25E6: 'o', //
  0x2190: '<-', 0x2192: '->', 0x2194: '<->', 0x21D2: '=>', 0x21D0: '<=', //
  0x21D4: '<=>', 0x2264: '<=', 0x2265: '>=', 0x2260: '!=', 0x2248: '~', //
  0x221E: 'inf', 0x2713: 'v', 0x2714: 'v', 0x2717: 'x', 0x2718: 'x', //
  0x2122: '(TM)', 0x20AC: 'EUR', 0x2032: "'", 0x2033: '"', 0x2009: ' ', //
  0x2002: ' ', 0x2003: ' ', 0x202F: ' ', 0x2007: ' ', 0x2008: ' ', //
};

Iterable<String> _imageUrls(List<MdBlock> blocks) sync* {
  for (final b in blocks) {
    if (b is MdImage && b.url.isNotEmpty) yield b.url;
    if (b is MdQuote) yield* _imageUrls(b.children);
  }
}

Future<pw.ImageProvider?> _loadPdfImage(PdfImageLoader load, String url) async {
  try {
    final bytes = await load(url);
    if (bytes == null || bytes.isEmpty) return null;
    return pw.MemoryImage(bytes);
  } on Object {
    return null; // Unsupported format, network error, ...
  }
}

class _PdfNoteBuilder {
  _PdfNoteBuilder(this.images);

  final Map<String, pw.ImageProvider?> images;

  final pw.Font _mono = pw.Font.courier();
  final pw.Font _monoBold = pw.Font.courierBold();
  final pw.Font _monoItalic = pw.Font.courierOblique();
  final pw.Font _monoBoldItalic = pw.Font.courierBoldOblique();

  /// Code blocks are split into chunks so one never exceeds a page.
  static const int _codeChunkLines = 40;

  List<pw.Widget> blocks(List<MdBlock> blocks, {int quoteDepth = 0}) => [
    for (final b in blocks) ..._block(b, quoteDepth: quoteDepth),
  ];

  List<pw.Widget> _block(MdBlock block, {required int quoteDepth}) {
    final widgets = switch (block) {
      MdHeading() => [_heading(block)],
      MdParagraph() => [
        _spaced(_rich(block.spans, const pw.TextStyle(fontSize: _bodySize))),
      ],
      MdListItem() => [_listItem(block)],
      MdCode() => _code(block.text),
      MdQuote() => blocks(block.children, quoteDepth: quoteDepth + 1),
      MdTable() => [_spaced(_table(block))],
      MdRule() => [pw.Divider(color: _hairline, thickness: 0.6, height: 18)],
      MdImage() => [_spaced(_image(block))],
      MdMath() => _code(block.tex, math: true),
    };
    // Quotes are flattened (each child gets the bar), so they can span pages.
    if (quoteDepth == 0 || block is MdQuote) return widgets;
    return [
      for (final w in widgets)
        pw.Container(
          padding: const pw.EdgeInsets.only(left: 10),
          decoration: const pw.BoxDecoration(
            border: pw.Border(left: pw.BorderSide(color: _hairline, width: 2)),
          ),
          child: w,
        ),
    ];
  }

  pw.Widget _spaced(pw.Widget child, {double bottom = 8}) => pw.Padding(
    padding: pw.EdgeInsets.only(bottom: bottom),
    child: child,
  );

  pw.Widget _heading(MdHeading h) {
    final size = switch (h.level) {
      1 => 20.0,
      2 => 16.5,
      3 => 14.0,
      4 => 12.5,
      _ => 11.5,
    };
    return pw.Padding(
      padding: pw.EdgeInsets.only(top: h.level <= 2 ? 12 : 8, bottom: 6),
      child: _rich(
        h.spans,
        pw.TextStyle(fontSize: size, fontWeight: pw.FontWeight.bold),
      ),
    );
  }

  pw.Widget _listItem(MdListItem item) {
    final pw.Widget marker;
    if (item.checked != null) {
      marker = pw.Container(
        width: 8,
        height: 8,
        margin: const pw.EdgeInsets.only(top: 3),
        decoration: pw.BoxDecoration(
          color: item.checked! ? _muted : null,
          border: pw.Border.all(color: _muted, width: 0.8),
          borderRadius: pw.BorderRadius.circular(1.5),
        ),
      );
    } else if (item.ordered) {
      marker = pw.Text(
        '${item.number ?? 1}.',
        style: const pw.TextStyle(fontSize: _bodySize),
      );
    } else {
      marker = pw.Container(
        width: 4,
        height: 4,
        margin: const pw.EdgeInsets.only(top: 5, left: 2),
        decoration: pw.BoxDecoration(
          color: item.depth == 0 ? PdfColors.black : null,
          border: pw.Border.all(color: PdfColors.black, width: 0.6),
          shape: pw.BoxShape.circle,
        ),
      );
    }
    return pw.Padding(
      padding: pw.EdgeInsets.only(left: 14.0 * item.depth, bottom: 4),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(width: item.ordered ? 20 : 14, child: marker),
          pw.Expanded(
            child: _rich(
              item.spans,
              pw.TextStyle(
                fontSize: _bodySize,
                color: item.checked == true ? _muted : null,
                decoration: item.checked == true
                    ? pw.TextDecoration.lineThrough
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<pw.Widget> _code(String source, {bool math = false}) {
    final lines = pdfSafeText(source).split('\n');
    final chunks = <List<String>>[
      for (var i = 0; i < lines.length; i += _codeChunkLines)
        lines.sublist(i, (i + _codeChunkLines).clamp(0, lines.length)),
    ];
    return [
      for (final (i, chunk) in chunks.indexed)
        pw.Container(
          width: double.infinity,
          margin: pw.EdgeInsets.only(bottom: i == chunks.length - 1 ? 8 : 0),
          padding: pw.EdgeInsets.fromLTRB(
            8,
            i == 0 ? 6 : 0,
            8,
            i == chunks.length - 1 ? 6 : 0,
          ),
          color: _codeBackground,
          child: pw.Text(
            chunk.join('\n'),
            style: pw.TextStyle(
              font: _mono,
              fontSize: math ? 10 : 9,
              lineSpacing: 1.5,
              fontStyle: math ? pw.FontStyle.italic : null,
              fontItalic: math ? _monoItalic : null,
            ),
          ),
        ),
    ];
  }

  pw.Widget _table(MdTable table) {
    final columns = [
      table.header.length,
      for (final r in table.rows) r.length,
    ].fold(0, (a, b) => a > b ? a : b);
    if (columns == 0) return pw.SizedBox();
    pw.Widget cell(List<MdSpan>? spans, {bool header = false}) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      child: _rich(
        spans ?? const [],
        pw.TextStyle(
          fontSize: 9.5,
          fontWeight: header ? pw.FontWeight.bold : null,
        ),
      ),
    );
    List<pw.Widget> padded(List<List<MdSpan>> cells, {bool header = false}) => [
      for (var i = 0; i < columns; i++)
        cell(i < cells.length ? cells[i] : null, header: header),
    ];
    return pw.Table(
      border: pw.TableBorder.all(color: _hairline, width: 0.6),
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.top,
      children: [
        if (table.header.isNotEmpty)
          pw.TableRow(
            repeat: true,
            decoration: const pw.BoxDecoration(color: _codeBackground),
            children: padded(table.header, header: true),
          ),
        for (final row in table.rows) pw.TableRow(children: padded(row)),
      ],
    );
  }

  pw.Widget _image(MdImage image) {
    final provider = images[image.url];
    if (provider == null) {
      return pw.Text(
        pdfSafeText(
          image.alt.trim().isEmpty ? '[Image]' : '[Image: ${image.alt}]',
        ),
        style: const pw.TextStyle(fontSize: 9, color: _muted),
      );
    }
    return pw.Container(
      alignment: pw.Alignment.centerLeft,
      constraints: const pw.BoxConstraints(maxHeight: 320),
      child: pw.Image(provider, fit: pw.BoxFit.contain),
    );
  }

  pw.Widget _rich(List<MdSpan> spans, pw.TextStyle base) => pw.RichText(
    text: pw.TextSpan(
      style: base.copyWith(lineSpacing: 2.5),
      children: [for (final s in spans) _span(s)],
    ),
  );

  pw.InlineSpan _span(MdSpan s) {
    final link = s.link;
    final linkable =
        link != null &&
        (link.startsWith('http://') ||
            link.startsWith('https://') ||
            link.startsWith('mailto:'));
    final text = s.imageUrl != null
        ? (s.text.trim().isEmpty ? '[Image]' : '[Image: ${s.text}]')
        : s.text;
    final decorations = [
      if (s.strike) pw.TextDecoration.lineThrough,
      if (linkable) pw.TextDecoration.underline,
    ];
    return pw.TextSpan(
      text: pdfSafeText(text),
      annotation: linkable ? pw.AnnotationUrl(link) : null,
      style: pw.TextStyle(
        fontWeight: s.bold ? pw.FontWeight.bold : null,
        fontStyle: s.italic ? pw.FontStyle.italic : null,
        color: linkable ? _link : (s.imageUrl != null ? _muted : null),
        decoration: decorations.isEmpty
            ? null
            : pw.TextDecoration.combine(decorations),
        fontNormal: s.code ? _mono : null,
        fontBold: s.code ? _monoBold : null,
        fontItalic: s.code ? _monoItalic : null,
        fontBoldItalic: s.code ? _monoBoldItalic : null,
        background: s.code
            ? const pw.BoxDecoration(color: _codeBackground)
            : null,
      ),
    );
  }
}
