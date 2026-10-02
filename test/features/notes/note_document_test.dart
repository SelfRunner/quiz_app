import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:quiz_app/features/notes/application/note_document.dart';
import 'package:quiz_app/features/notes/application/note_markdown_syntax.dart';

List<md.Element> _elements(List<md.Node> nodes, String tag) => [
  for (final n in nodes)
    if (n is md.Element) ...[
      if (n.tag == tag) n,
      ..._elements(n.children ?? const [], tag),
    ],
];

void main() {
  group('parseNoteMarkdown', () {
    test('inline and block math', () {
      final ast = parseNoteMarkdown(
        r'Energy $E = mc^2$ costs $5 and $10.'
        '\n\n'
        r'$$'
        '\n'
        r'\int_0^1 x\,dx'
        '\n'
        r'$$',
      );
      final inline = _elements(ast.nodes, NoteTags.mathInline);
      expect(inline.map((e) => e.textContent), ['E = mc^2']);
      final block = _elements(ast.nodes, NoteTags.mathBlock).single;
      expect(block.attributes['tex'], r'\int_0^1 x\,dx');
    });

    test('single-line block math and unclosed blocks', () {
      final one = parseNoteMarkdown(r'$$ a^2 + b^2 $$');
      expect(
        _elements(one.nodes, NoteTags.mathBlock).single.attributes['tex'],
        'a^2 + b^2',
      );
      final open = parseNoteMarkdown('\$\$\nnot math');
      expect(_elements(open.nodes, NoteTags.mathBlock), isEmpty);
    });

    test('code blocks keep language and text; math in code is ignored', () {
      final ast = parseNoteMarkdown('```dart\nfinal x = r"\$a\$";\n```');
      final code = _elements(ast.nodes, NoteTags.code).single;
      expect(code.attributes['language'], 'dart');
      expect(code.attributes['code'], r'final x = r"$a$";');
      expect(_elements(ast.nodes, NoteTags.mathInline), isEmpty);
    });

    test('headings get unique slugs', () {
      final ast = parseNoteMarkdown(
        '# Intro\n\n## Cell *biology*\n\n## Intro\n\ntext',
      );
      expect(ast.headings.map((h) => h.slug), [
        'intro',
        'cell-biology',
        'intro-1',
      ]);
      expect(ast.headings.map((h) => h.level), [1, 2, 2]);
      expect(ast.headings[1].text, 'Cell biology');
    });

    test('callouts', () {
      final ast = parseNoteMarkdown('> [!WARNING]\n> Hot surface\n\n> plain');
      final callout = _elements(ast.nodes, NoteTags.callout).single;
      expect(callout.attributes['type'], 'warning');
      expect(
        ast.childrenOf(callout).map((n) => n.textContent),
        contains('Hot surface'),
      );
      expect(_elements(ast.nodes, 'blockquote'), hasLength(1));
    });

    test('task build order is post-order', () {
      final ast = parseNoteMarkdown(
        '- [ ] a\n  - [x] b\n  - [ ] c\n- [ ] d\n\n'
        '1. [ ] loose\n\n2. [x] items',
      );
      expect(ast.taskCount, 6);
      expect(ast.taskBuildOrder, [1, 2, 0, 3, 4, 5]);
    });
  });

  group('NoteDocument tasks', () {
    const doc =
        '- [ ] one\n'
        '```\n- [ ] not a task\n```\n'
        '  - [x] two\n'
        '> - [ ] three\n'
        '3) [ ] four';

    test('offsets skip code blocks', () {
      expect(NoteDocument.taskOffsets(doc), hasLength(4));
      expect(parseNoteMarkdown(doc).taskCount, 4);
    });

    test('setTask toggles the right line', () {
      final checked = NoteDocument.setTask(doc, 2, checked: true)!;
      expect(checked, contains('> - [x] three'));
      final unchecked = NoteDocument.setTask(checked, 1, checked: false)!;
      expect(unchecked, contains('  - [ ] two'));
      expect(unchecked, contains('- [ ] not a task'));
      expect(NoteDocument.setTask(doc, 9, checked: true), isNull);
    });

    test('word count and reading time', () {
      expect(NoteDocument.wordCount('# Hi there\n\n- [ ] **bold** move'), 4);
      expect(
        NoteDocument.wordCount('[link text](http://x.y) ![img](a.png)'),
        2,
      );
      expect(NoteDocument.readingMinutes(0), 0);
      expect(NoteDocument.readingMinutes(201), 2);
      expect(NoteDocument.statsLabel('one two'), '2 words · 1 min read');
    });
  });
}
