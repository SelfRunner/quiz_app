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

  group('toggleList', () {
    test('replaces existing markers and keeps indentation', () {
      final r = MarkdownEditing.toggleList(
        _v('- a\n  - b\nc', 0, 11),
        ListKind.task,
      );
      expect(r.text, '- [ ] a\n  - [ ] b\n- [ ] c');
      final back = MarkdownEditing.toggleList(
        _v(r.text, 0, r.text.length),
        ListKind.task,
      );
      expect(back.text, 'a\n  b\nc');
    });

    test('numbered on an empty line adds a marker', () {
      final r = MarkdownEditing.toggleList(_v('', 0), ListKind.numbered);
      expect(r.text, '1. ');
      expect(r.selection.baseOffset, 3);
    });
  });

  group('continueList', () {
    TextEditingValue? enter(String text, int caret) {
      final old = _v(text, caret);
      final typed = TextEditingValue(
        text: text.replaceRange(caret, caret, '\n'),
        selection: TextSelection.collapsed(offset: caret + 1),
      );
      return MarkdownEditing.continueList(old, typed);
    }

    test('continues bullets, numbers, tasks and quotes', () {
      expect(enter('- apples', 8)!.text, '- apples\n- ');
      expect(enter('  9. nine', 9)!.text, '  9. nine\n  10. ');
      expect(enter('- [x] done', 10)!.text, '- [x] done\n- [ ] ');
      expect(enter('> quoted', 8)!.text, '> quoted\n> ');
      final r = enter('- a', 3)!;
      expect(r.selection.baseOffset, r.text.length);
    });

    test('splits an item when Enter is pressed mid-text', () {
      expect(enter('- abcd', 4)!.text, '- ab\n- cd');
    });

    test('empty item ends the list', () {
      final r = enter('- a\n- ', 6)!;
      expect(r.text, '- a\n');
      expect(r.selection.baseOffset, 4);
    });

    test('ignores plain text, pastes and caret inside the marker', () {
      expect(enter('plain', 5), isNull);
      expect(enter('- item', 1), isNull);
      final paste = MarkdownEditing.continueList(
        _v('- a', 3),
        const TextEditingValue(
          text: '- a\nb\nc',
          selection: TextSelection.collapsed(offset: 7),
        ),
      );
      expect(paste, isNull);
    });
  });

  group('indentList', () {
    test('nests under the previous sibling and outdents back', () {
      final r = MarkdownEditing.indentList(_v('- a\n- b', 7))!;
      expect(r.text, '- a\n  - b');
      expect(r.selection.baseOffset, 9);
      final numbered = MarkdownEditing.indentList(_v('1. a\n2. b', 9))!;
      expect(numbered.text, '1. a\n   2. b');
      final out = MarkdownEditing.indentList(_v(r.text, 9), outdent: true)!;
      expect(out.text, '- a\n- b');
    });

    test('returns null outside lists', () {
      expect(MarkdownEditing.indentList(_v('text', 2)), isNull);
    });
  });

  test('table, callout, math and language code blocks', () {
    final table = MarkdownEditing.table(_v('', 0), rows: 1, columns: 2);
    expect(table.text, '| Column 1 | Column 2 |\n| --- | --- |\n|   |   |\n');
    expect(table.selection.textInside(table.text), 'Column 1');

    final callout = MarkdownEditing.callout(_v('', 0), 'tip');
    expect(callout.text, '> [!TIP]\n> Text\n');
    expect(callout.selection.textInside(callout.text), 'Text');
    final quoted = MarkdownEditing.callout(_v('a\nb', 0, 3), 'NOTE');
    expect(quoted.text, '> [!NOTE]\n> a\n> b\n');

    final math = MarkdownEditing.mathBlock(_v('', 0));
    expect(math.text, '\$\$\nE = mc^2\n\$\$\n');
    expect(math.selection.textInside(math.text), 'E = mc^2');
    expect(MarkdownEditing.mathInline(_v('', 0)).text, r'$x^2$');

    final code = MarkdownEditing.codeBlock(_v('', 0), language: 'dart');
    expect(code.text, '```dart\ncode\n```\n');
    expect(code.selection.textInside(code.text), 'code');
  });
}
