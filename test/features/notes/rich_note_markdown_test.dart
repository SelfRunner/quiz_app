import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/features/notes/application/note_document.dart';
import 'package:quiz_app/features/notes/presentation/widgets/note_code_block.dart';
import 'package:quiz_app/features/notes/presentation/widgets/rich_note_markdown.dart';

Widget _wrap(Widget child) => ProviderScope(
  child: MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ),
);

void main() {
  testWidgets('renders inline and block math', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const RichNoteMarkdown(
          data: 'Einstein: \$E = mc^2\$.\n\n\$\$\n\\frac{a}{b}\n\$\$\n',
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('note-math-inline')), findsOneWidget);
    expect(find.byKey(const Key('note-math-block')), findsOneWidget);
    expect(find.byType(Math), findsNWidgets(2));
    expect(find.textContaining('Einstein'), findsOneWidget);
  });

  testWidgets('invalid TeX falls back to the source', (tester) async {
    await tester.pumpWidget(
      _wrap(const RichNoteMarkdown(data: '\$\$ \\frac{a \$\$')),
    );
    await tester.pump();
    expect(find.byType(MathError), findsOneWidget);
  });

  testWidgets('code block: language label, highlighting, copy', (tester) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    await tester.pumpWidget(
      _wrap(
        const RichNoteMarkdown(
          data: '```python\ndef f(x):\n    return x  # double\n```',
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(NoteCodeBlock), findsOneWidget);
    expect(find.text('Python'), findsOneWidget);
    final rich = tester.widget<Text>(
      find.descendant(
        of: find.byType(NoteCodeBlock),
        matching: find.byWidgetPredicate(
          (w) => w is Text && w.textSpan != null,
        ),
      ),
    );
    // Highlighted: more than one styled span.
    var spans = 0;
    rich.textSpan!.visitChildren((_) {
      spans++;
      return true;
    });
    expect(spans, greaterThan(2));
    expect(rich.textSpan!.toPlainText(), contains('return x'));

    await tester.tap(find.byKey(const Key('note-code-copy')));
    await tester.pump();
    expect(copied.single, 'def f(x):\n    return x  # double');
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('tables render inside a horizontal scroll view', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const RichNoteMarkdown(
          data: '| Organelle | Role |\n| --- | --- |\n| Mitochondria | ATP |',
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(Table), findsOneWidget);
    expect(
      find.ancestor(
        of: find.byType(Table),
        matching: find.byWidgetPredicate(
          (w) =>
              w is SingleChildScrollView &&
              w.scrollDirection == Axis.horizontal,
        ),
      ),
      findsOneWidget,
    );
    expect(find.text('Mitochondria'), findsOneWidget);
  });

  testWidgets('callouts and quotes', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const RichNoteMarkdown(
          data:
              '> [!TIP]\n> Use **flashcards**\n\n'
              '> [!WARNING]\n> Careful\n\n> Just a quote',
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('note-callout-tip')), findsOneWidget);
    expect(find.byKey(const Key('note-callout-warning')), findsOneWidget);
    expect(find.text('Tip'), findsOneWidget);
    expect(find.textContaining('flashcards'), findsOneWidget);
    expect(find.textContaining('Just a quote'), findsOneWidget);
  });

  testWidgets('task checkboxes toggle by document index', (tester) async {
    var data = '- [ ] a\n  - [x] b\n- [ ] c';
    final calls = <(int, bool)>[];
    await tester.pumpWidget(
      _wrap(
        StatefulBuilder(
          builder: (context, setState) => RichNoteMarkdown(
            data: data,
            onToggleTask: (i, checked) {
              calls.add((i, checked));
              setState(
                () => data = NoteDocument.setTask(data, i, checked: checked)!,
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('note-task-0')), findsOneWidget);
    expect(find.byKey(const Key('note-task-1')), findsOneWidget);

    await tester.tap(find.byKey(const Key('note-task-1')));
    await tester.pump();
    expect(calls.last, (1, false));
    expect(data, '- [ ] a\n  - [ ] b\n- [ ] c');

    await tester.tap(find.byKey(const Key('note-task-2')));
    await tester.pump();
    expect(calls.last, (2, true));
    expect(data, '- [ ] a\n  - [ ] b\n- [x] c');
  });

  testWidgets('read-only task checkboxes ignore taps', (tester) async {
    await tester.pumpWidget(_wrap(const RichNoteMarkdown(data: '- [ ] a')));
    await tester.pump();
    expect(
      find.descendant(
        of: find.byKey(const Key('note-task-0')),
        matching: find.byType(InkWell),
      ),
      findsNothing,
    );
  });

  testWidgets('anchor links scroll to headings', (tester) async {
    final anchors = NoteAnchors();
    final filler = List.filled(60, 'Paragraph text.').join('\n\n');
    await tester.pumpWidget(
      _wrap(
        RichNoteMarkdown(
          anchors: anchors,
          data: '[Jump](#the-end)\n\n$filler\n\n## The end\n\nDone',
        ),
      ),
    );
    await tester.pump();
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scrollable.position.pixels, 0);
    await tester.tap(find.text('Jump'));
    await tester.pumpAndSettle();
    expect(scrollable.position.pixels, greaterThan(500));
    expect(anchors.keyFor(0).currentContext, isNotNull);
  });
}
