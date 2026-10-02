import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../subjects/support/fakes.dart';
import 'support/note_test_app.dart';

TextEditingController _controller(WidgetTester tester) =>
    tester.widget<TextField>(find.byKey(const Key('note-content'))).controller!;

Future<void> _openEditor(
  WidgetTester tester,
  String content, {
  Size size = const Size(800, 900),
}) async {
  setWindowSize(tester, size);
  final deps = TestDeps();
  deps.subjects.seed(id: 's1');
  deps.notes.seed(id: 'n1', subjectId: 's1', contentMd: content);
  await tester.pumpWidget(noteTestApp(deps, '/notes/n1/edit'));
  await tester.pumpAndSettle();
}

Future<void> _focusAt(WidgetTester tester, int offset) async {
  await tester.tap(find.byKey(const Key('note-content')));
  await tester.pump();
  final c = _controller(tester);
  c.selection = TextSelection.collapsed(offset: offset);
  await tester.pump();
}

Future<void> _chord(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool shift = false,
}) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(key);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

void main() {
  testWidgets('keyboard shortcuts format the selection', (tester) async {
    await _openEditor(tester, 'word');
    await tester.tap(find.byKey(const Key('note-content')));
    await tester.pump();
    final c = _controller(tester);
    c.selection = const TextSelection(baseOffset: 0, extentOffset: 4);
    await tester.pump();

    await _chord(tester, LogicalKeyboardKey.keyB);
    expect(c.text, '**word**');
    await _chord(tester, LogicalKeyboardKey.keyB);
    expect(c.text, 'word');

    c.selection = const TextSelection(baseOffset: 0, extentOffset: 4);
    await _chord(tester, LogicalKeyboardKey.keyE);
    expect(c.text, '`word`');

    c.selection = const TextSelection.collapsed(offset: 3);
    await _chord(tester, LogicalKeyboardKey.digit8, shift: true);
    expect(c.text, '- `word`');
    await _chord(tester, LogicalKeyboardKey.digit9, shift: true);
    expect(c.text, '- [ ] `word`');
    await _chord(tester, LogicalKeyboardKey.digit7, shift: true);
    expect(c.text, '1. `word`');

    await _chord(tester, LogicalKeyboardKey.keyK);
    expect(find.text('Insert link'), findsOneWidget);
  });

  testWidgets('Enter continues lists; Tab indents list items', (tester) async {
    await _openEditor(tester, '- apples');
    await _focusAt(tester, 8);
    final c = _controller(tester);

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '- apples\n',
        selection: TextSelection.collapsed(offset: 9),
      ),
    );
    await tester.pump();
    expect(c.text, '- apples\n- ');
    expect(c.selection.baseOffset, 11);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(c.text, '- apples\n  - ');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(c.text, '- apples\n- ');

    // Enter on the empty item ends the list.
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '- apples\n- \n',
        selection: TextSelection.collapsed(offset: 12),
      ),
    );
    await tester.pump();
    expect(c.text, '- apples\n');
  });

  testWidgets('word count and reading time follow the text', (tester) async {
    await _openEditor(tester, 'one two three');
    expect(find.text('3 words · 1 min read'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('note-content')), 'hello');
    await tester.pump();
    expect(find.text('1 word · 1 min read'), findsOneWidget);
  });

  testWidgets('toolbar menus insert tables, callouts, code and math', (
    tester,
  ) async {
    await _openEditor(tester, '', size: const Size(1400, 900));
    final c = _controller(tester);

    Future<void> pick(String menu, String item) async {
      await tester.tap(find.byKey(Key('md-$menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(item).last);
      await tester.pumpAndSettle();
    }

    await pick('table', '2 × 2 table');
    expect(c.text, contains('| Column 1 | Column 2 |'));
    c.value = const TextEditingValue(text: '');
    await pick('quote', 'Warning callout');
    expect(c.text, '> [!WARNING]\n> Text\n');
    c.value = const TextEditingValue(text: '');
    await pick('codeblock', 'Python');
    expect(c.text, '```python\ncode\n```\n');
    c.value = const TextEditingValue(text: '');
    await pick('math', r'Math block  $$ … $$');
    expect(c.text, '\$\$\nE = mc^2\n\$\$\n');
    await tester.pumpAndSettle();
    // Split view renders the math in the preview.
    expect(find.byKey(const Key('note-math-block')), findsOneWidget);
    c.value = const TextEditingValue(text: 'Heading');
    await pick('heading', 'Heading 2');
    expect(c.text, '## Heading');
  });

  testWidgets('preview checkboxes update the editor text', (tester) async {
    await _openEditor(tester, '- [ ] milk\n- [x] eggs');
    await tester.tap(find.byTooltip('Preview'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('note-task-0')));
    await tester.pump();
    await tester.tap(find.byTooltip('Write'));
    await tester.pumpAndSettle();
    expect(_controller(tester).text, '- [x] milk\n- [x] eggs');
  });

  testWidgets('focus mode hides chrome on desktop and Esc exits', (
    tester,
  ) async {
    await _openEditor(tester, 'Draft', size: const Size(1280, 800));
    expect(find.byKey(const Key('note-title')), findsOneWidget);
    await tester.tap(find.byKey(const Key('note-focus-mode')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('note-focus-scaffold')), findsOneWidget);
    expect(find.byKey(const Key('note-title')), findsNothing);
    expect(find.byKey(const Key('md-bold')), findsNothing);
    expect(find.byKey(const Key('note-preview')), findsNothing);
    expect(find.byKey(const Key('note-word-count')), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('note-title')), findsOneWidget);

    await _chord(tester, LogicalKeyboardKey.keyF, shift: true);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('note-focus-scaffold')), findsOneWidget);
    await tester.tap(find.byKey(const Key('note-exit-focus')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('note-focus-scaffold')), findsNothing);
  });

  testWidgets('focus mode is not offered on phones', (tester) async {
    await _openEditor(tester, 'Draft', size: const Size(400, 800));
    expect(find.byKey(const Key('note-focus-mode')), findsNothing);
  });
}
