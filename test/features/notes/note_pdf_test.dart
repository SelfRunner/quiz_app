import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/data/models/models.dart';
import 'package:quiz_app/features/notes/application/note_export_actions.dart';
import 'package:quiz_app/features/notes/application/note_pdf.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
);

Note _note(String content, {String title = 'Cells', List<String>? tags}) =>
    Note(
      id: 'n1',
      subjectId: 's1',
      ownerId: 'u1',
      title: title,
      contentMd: content,
      tags: tags ?? const ['exam'],
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 2),
    );

bool _isPdf(Uint8List bytes) =>
    bytes.length > 500 && ascii.decode(bytes.sublist(0, 5)) == '%PDF-';

void main() {
  test('renders every block kind; loads images best effort', () async {
    final requested = <String>[];
    final bytes = await noteToPdf(
      _note(
        '# Title\n\n## Sub\n\nSome **bold**, _italic_, `code`, ~~gone~~ and '
        '[a link](https://example.com) – “quotes” … ✓ 日本 😀\n\n'
        '1. one\n2. two\n   - nested\n- [ ] todo\n- [x] done\n\n'
        '> quoted\n> > deeper\n\n```python\nprint("hi")\n```\n\n'
        '| h1 | h2 | h3 |\n|---|---|---|\n| a | **b** |\n\n---\n\n'
        r'$$\int_0^1 x\,dx$$'
        '\n\n![ok](note-image://u1/n1/a.png)\n\n'
        '![broken](note-image://u1/n1/b.png)\n\n'
        '![missing](https://example.com/x.png)\n\nInline ![i](x.png) image.\n',
      ),
      subjectTitle: 'Biology',
      loadImage: (url) async {
        requested.add(url);
        if (url.endsWith('a.png')) return _png;
        if (url.endsWith('b.png')) return Uint8List.fromList([1, 2, 3]);
        throw Exception('offline');
      },
    );
    expect(_isPdf(bytes), isTrue);
    expect(requested, [
      'note-image://u1/n1/a.png',
      'note-image://u1/n1/b.png',
      'https://example.com/x.png',
    ]);
  });

  test(
    'long content spans pages (huge code block, table, paragraphs)',
    () async {
      final code = List.generate(300, (i) => 'line $i();').join('\n');
      final rows = List.generate(120, (i) => '| $i | value $i |').join('\n');
      final paragraphs = List.generate(
        60,
        (i) => 'Paragraph $i. ${'Lorem ipsum dolor sit amet. ' * 12}',
      ).join('\n\n');
      final bytes = await noteToPdf(
        _note('```\n$code\n```\n\n| n | v |\n|---|---|\n$rows\n\n$paragraphs'),
      );
      expect(_isPdf(bytes), isTrue);
      expect(bytes.length, greaterThan(20000));
    },
  );

  test('empty notes and untitled notes still produce a PDF', () async {
    expect(_isPdf(await noteToPdf(_note('', title: '', tags: []))), isTrue);
  });

  test('pdfSafeText keeps Latin-1 and maps typography', () {
    expect(pdfSafeText('café – “ok” … → ≤ ✓'), 'café - "ok" ... -> <= v');
    expect(pdfSafeText('日本😀\tx\r'), '???    x');
  });

  test('notesPinnedFirst keeps each group in order', () {
    Note n(String id, {bool pinned = false}) =>
        _note('').copyWith(id: id, pinned: pinned);
    expect(
      notesPinnedFirst([
        n('a'),
        n('b', pinned: true),
        n('c'),
        n('d', pinned: true),
      ]).map((e) => e.id),
      ['b', 'd', 'a', 'c'],
    );
  });

  test('export file names are safe', () {
    expect(
      noteExportBaseName(_note('', title: 'A/B: c?')),
      isNot(contains('/')),
    );
    expect(noteExportBaseName(_note('', title: '  ')), 'note');
  });
}
