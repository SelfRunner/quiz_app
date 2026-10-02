import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/ai/ai_source.dart';
import 'package:quiz_app/ai/text_extractor.dart';
import 'package:quiz_app/core/errors/app_exception.dart';

import 'test_helpers.dart';

String para(String inner) => '<w:p>$inner</w:p>';
String run(String text) =>
    '<w:r><w:rPr><w:b/></w:rPr><w:t xml:space="preserve">$text</w:t></w:r>';

void main() {
  test('docx: paragraphs, split runs, tabs, breaks, entities', () {
    final bytes = buildDocx(
      // Heading with paragraph properties (tab stops must not leak).
      '<w:p><w:pPr><w:pStyle w:val="Heading1"/><w:tabs>'
      '<w:tab w:val="left" w:pos="720"/></w:tabs></w:pPr>'
      '${run('Cell ')}${run('biology')}</w:p>'
      '${para('${run('Mitochondria')}<w:r><w:tab/></w:r>${run('make ATP &amp; heat')}')}'
      '${para('')}'
      '${para('${run('Line one')}<w:r><w:br/></w:r>${run('Line two &#8211; &lt;b&gt;')}')}'
      '<w:tbl><w:tr><w:tc>${para(run('Cell A'))}</w:tc>'
      '<w:tc>${para(run('Cell B'))}</w:tc></w:tr></w:tbl>'
      '<w:sectPr/>',
    );
    final text = TextExtractor.extract(
      'Lecture.DOCX',
      'application/octet-stream',
      bytes,
    );
    expect(
      text,
      'Cell biology\n'
      'Mitochondria\tmake ATP & heat\n'
      '\n'
      'Line one\nLine two – <b>\n'
      'Cell A\n'
      'Cell B',
    );
  });

  test('docx detected by MIME type too', () {
    final bytes = buildDocx(para(run('Hello')));
    expect(
      TextExtractor.extract('upload', TextExtractor.docxMimeType, bytes),
      'Hello',
    );
  });

  test('corrupt or non-Word zip -> ValidationException', () {
    expect(
      () => TextExtractor.extract(
        'x.docx',
        null,
        Uint8List.fromList([1, 2, 3, 4]),
      ),
      throwsA(isA<ValidationException>()),
    );
    final zip = ZipEncoder().encodeBytes(
      Archive()..addFile(ArchiveFile('a.txt', 1, [65])),
    );
    expect(
      () => TextExtractor.extract('x.docx', null, zip),
      throwsA(
        isA<ValidationException>().having(
          (e) => e.message,
          'message',
          contains('not a Word'),
        ),
      ),
    );
  });

  test('plain text: UTF-8 with BOM, CRLF, malformed bytes tolerated', () {
    final bytes = Uint8List.fromList([
      0xEF, 0xBB, 0xBF, //
      ...utf8.encode('Größe\r\nzwei'),
      0xFF,
    ]);
    expect(TextExtractor.extract('a.txt', 'text/plain', bytes), 'Größe\nzwei�');
    expect(TextExtractor.extract('notes.md', null, utf8.encode('# T')), '# T');
  });

  test('canExtract / non-text types', () {
    expect(TextExtractor.canExtract('a.md', null), isTrue);
    expect(TextExtractor.canExtract('a', 'text/csv'), isTrue);
    expect(TextExtractor.canExtract('a.json', null), isTrue);
    expect(TextExtractor.canExtract('a.pdf', 'application/pdf'), isFalse);
    expect(TextExtractor.canExtract('a.png', null), isFalse);
    expect(TextExtractor.canExtract('a.doc', 'application/msword'), isFalse);
    expect(
      TextExtractor.extract('a.pdf', 'application/pdf', Uint8List(3)),
      isNull,
    );
  });

  test('AiInputKind.ofFile and MIME normalization', () {
    expect(AiInputKind.ofFile('a.pdf', null), AiInputKind.pdf);
    expect(AiInputKind.ofFile('a.JPG', ''), AiInputKind.image);
    expect(normalizeMimeType('a.jpg', 'image/jpg'), 'image/jpeg');
    expect(AiInputKind.ofFile('a', 'audio/mpeg; codecs=x'), AiInputKind.audio);
    expect(AiInputKind.ofFile('a.mov', null), AiInputKind.video);
    expect(AiInputKind.ofFile('a.docx', null), AiInputKind.text);
    expect(AiInputKind.ofFile('a.zip', 'application/zip'), isNull);
    expect(normalizeMimeType('x.bin', null), 'application/octet-stream');
  });
}
