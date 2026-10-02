import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/features/notes/application/markdown_editing.dart';

TextEditingValue _v(String text, int start, [int? end]) => TextEditingValue(
  text: text,
  selection: TextSelection(baseOffset: start, extentOffset: end ?? start),
);

void main() {
  group('wrap', () {
    test('wraps the selection', () {
      final r = MarkdownEditing.wrap(_v('say hello', 4, 9), '**', '**');
      expect(r.text, 'say **hello**');
      expect(r.selection.textInside(r.text), 'hello');
    });

    test('inserts and selects a placeholder when nothing is selected', () {
      final r = MarkdownEditing.wrap(
        _v('ab', 1),
        '_',
        '_',
        placeholder: 'italic',
      );
      expect(r.text, 'a_italic_b');
      expect(r.selection.textInside(r.text), 'italic');
    });

    test('toggles off existing markers', () {
      final r = MarkdownEditing.wrap(_v('**bold**', 2, 6), '**', '**');
      expect(r.text, 'bold');
    });

    test('invalid selection appends at the end', () {
      const v = TextEditingValue(text: 'x');
      expect(MarkdownEditing.wrap(v, '`', '`').text, 'x`text`');
    });
  });

  group('prefixLines', () {
    test('adds and removes list prefixes on all selected lines', () {
      final added = MarkdownEditing.prefixLines(_v('a\nb\nc', 0, 3), '- ');
      expect(added.text, '- a\n- b\nc');
      final removed = MarkdownEditing.prefixLines(_v(added.text, 0, 7), '- ');
      expect(removed.text, 'a\nb\nc');
    });

    test('numbered lists count up', () {
      final r = MarkdownEditing.prefixLines(
        _v('a\nb', 0, 3),
        '1. ',
        numbered: true,
      );
      expect(r.text, '1. a\n2. b');
    });

    test('headings replace the existing level', () {
      final r = MarkdownEditing.prefixLines(_v('# Title', 3), '## ');
      expect(r.text, '## Title');
    });
  });

  test('insertBlock puts content on its own line', () {
    final r = MarkdownEditing.image(
      _v('textmore', 4),
      url: 'note-image://a/b/c.png',
    );
    expect(r.text, 'text\n![image](note-image://a/b/c.png)\nmore');
  });

  test('codeBlock fences the selection', () {
    final r = MarkdownEditing.codeBlock(_v('x = 1', 0, 5));
    expect(r.text, '```\nx = 1\n```\n');
  });

  test('link uses selection as label', () {
    final r = MarkdownEditing.link(_v('see docs', 4, 8), url: 'https://d.io');
    expect(r.text, 'see [docs](https://d.io)');
  });

  test('preview text strips markdown', () {
    expect(
      markdownPreviewText('# Title\n\nSome **bold** and [link](x) ![i](y)'),
      'Title Some bold and link',
    );
  });
}
