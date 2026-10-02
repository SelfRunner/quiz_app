import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../core/errors/app_exception.dart';
import 'ai_source.dart';

/// In-app text extraction for text-like attachments, so they work with every
/// model (they are sent as text, not as files).
///
/// Supported: plain text (`text/*`, .txt, .md, .csv, .json, ...) decoded as
/// UTF-8 (a BOM is stripped, invalid bytes are replaced), and Word .docx
/// (paragraph text from `word/document.xml`, tabs and line breaks kept).
/// Not supported: PDF, images, legacy .doc, .odt, .rtf.
///
/// The data layer can call [extract] once on upload and store the result
/// (e.g. `extracted_text`) to avoid re-parsing.
abstract final class TextExtractor {
  static const docxMimeType =
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document';

  static const _textExtensions = {
    'txt',
    'text',
    'md',
    'markdown',
    'csv',
    'tsv',
    'json',
    'log',
  };

  static const _textMimeTypes = {
    'application/json',
    'application/x-markdown',
    'application/markdown',
  };

  /// Whether [extract] can turn this file into text.
  static bool canExtract(String name, String? mimeType) {
    final ext = fileExtension(name);
    if (ext == 'docx' || _textExtensions.contains(ext)) return true;
    final mime = normalizeMimeType(name, mimeType);
    return mime == docxMimeType ||
        mime.startsWith('text/') ||
        _textMimeTypes.contains(mime);
  }

  /// The text of a text-like file, or null when the type is not supported
  /// (see [canExtract]). Throws [ValidationException] for a corrupt .docx.
  static String? extract(String name, String? mimeType, Uint8List bytes) {
    if (!canExtract(name, mimeType)) return null;
    final isDocx =
        fileExtension(name) == 'docx' ||
        normalizeMimeType(name, mimeType) == docxMimeType;
    return isDocx ? extractDocx(bytes, name: name) : decodeText(bytes);
  }

  /// UTF-8 decode, tolerant of a BOM and invalid sequences; CRLF -> LF.
  static String decodeText(Uint8List bytes) {
    var start = 0;
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      start = 3;
    }
    return utf8
        .decode(Uint8List.sublistView(bytes, start), allowMalformed: true)
        .replaceAll('\r\n', '\n');
  }

  /// Paragraph text of a .docx (paragraphs separated by newlines).
  static String extractDocx(Uint8List bytes, {String name = 'document'}) {
    final ArchiveFile? entry;
    try {
      entry = ZipDecoder().decodeBytes(bytes).findFile('word/document.xml');
    } catch (e, st) {
      throw ValidationException(
        'Could not read "$name". Is it a valid Word (.docx) file?',
        cause: e,
        stackTrace: st,
      );
    }
    if (entry == null) {
      throw ValidationException(
        '"$name" is not a Word (.docx) document (word/document.xml missing).',
      );
    }
    final xml = utf8.decode(entry.content, allowMalformed: true);
    return docxXmlToText(xml);
  }

  // `<w:p>`/`</w:p>` paragraph bounds, `<w:t>` text runs, tabs and breaks.
  static final _token = RegExp(
    r'<(/?)w:(p|r|t|tab|br|cr)\b[^>]*?(/?)>|<[^>]*>|([^<]+)',
  );

  /// Converts WordprocessingML (`word/document.xml`) to plain text.
  static String docxXmlToText(String xml) {
    final out = StringBuffer();
    final paragraph = StringBuffer();
    var inText = false;
    var inRun = false;
    var inParagraph = false;
    void endParagraph() {
      out
        ..write(paragraph.toString().trimRight())
        ..write('\n');
      paragraph.clear();
    }

    for (final m in _token.allMatches(xml)) {
      final tag = m.group(2);
      final closing = m.group(1) == '/';
      final selfClosing = m.group(3) == '/';
      final text = m.group(4);
      if (text != null) {
        if (inText) paragraph.write(_unescape(text));
        continue;
      }
      switch (tag) {
        case 'p':
          if (closing) {
            endParagraph();
            inParagraph = false;
          } else if (selfClosing) {
            endParagraph();
          } else {
            if (inParagraph) endParagraph();
            inParagraph = true;
          }
        case 'r':
          inRun = !closing && !selfClosing;
        case 't':
          inText = !closing && !selfClosing;
        // Tab stops in paragraph properties also use <w:tab/>; only runs
        // carry real tabs/breaks.
        case 'tab':
          if (!closing && inRun) paragraph.write('\t');
        case 'br' || 'cr':
          if (!closing && inRun) paragraph.write('\n');
        default:
          break; // other markup
      }
    }
    if (paragraph.isNotEmpty) endParagraph();
    return out.toString().replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }

  static final _entity = RegExp(r'&(#x[0-9a-fA-F]+|#\d+|amp|lt|gt|quot|apos);');

  static String _unescape(String s) => s.replaceAllMapped(_entity, (m) {
    final e = m.group(1)!;
    switch (e) {
      case 'amp':
        return '&';
      case 'lt':
        return '<';
      case 'gt':
        return '>';
      case 'quot':
        return '"';
      case 'apos':
        return "'";
    }
    final code = e.startsWith('#x')
        ? int.tryParse(e.substring(2), radix: 16)
        : int.tryParse(e.substring(1));
    return code == null ? m.group(0)! : String.fromCharCode(code);
  });
}
