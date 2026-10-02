import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/ai/ai_tools_service.dart';
import 'package:quiz_app/core/errors/app_exception.dart';

import '../subjects/support/fakes.dart';
import 'support/note_test_app.dart';

const _long =
    '# Cells\n\nIntro\n\n## Membrane\n\nText\n\n## Nucleus\n\nText\n\n'
    '## Mitochondria\n\nPowerhouse';

Future<TestDeps> _open(
  WidgetTester tester, {
  String content = 'Cells are small.\n\n- [ ] read\n- [x] write',
  String ownerId = kUserId,
  bool ai = true,
  Size size = const Size(800, 1000),
  FakeAiToolsService? tools,
}) async {
  setWindowSize(tester, size);
  final deps = TestDeps();
  if (ai) deps.configureAi();
  deps.subjects.seed(id: 's1', title: 'Biology');
  deps.notes.seed(
    id: 'note1',
    subjectId: 's1',
    title: 'Cells',
    contentMd: content,
    ownerId: ownerId,
  );
  await tester.pumpWidget(noteTestApp(deps, '/notes/note1', tools: tools));
  await tester.pumpAndSettle();
  return deps;
}

Future<void> _runTool(WidgetTester tester, NoteToolKind kind) async {
  await tester.tap(find.byKey(const Key('note-ai-menu')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('ai-tool-${kind.name}')));
  await tester.pumpAndSettle();
}

void main() {
  group('note view', () {
    testWidgets('owner toggles a checklist item and it is saved', (
      tester,
    ) async {
      final deps = await _open(tester);
      await tester.tap(find.byKey(const Key('note-task-0')));
      await tester.pumpAndSettle();
      expect(
        deps.notes.updates.single.contentMd,
        'Cells are small.\n\n- [x] read\n- [x] write',
      );
      await tester.tap(find.byKey(const Key('note-task-1')));
      await tester.pumpAndSettle();
      expect(
        deps.notes.updates.last.contentMd,
        'Cells are small.\n\n- [x] read\n- [ ] write',
      );
    });

    testWidgets('shared notes have read-only checkboxes', (tester) async {
      final deps = await _open(tester, ownerId: 'other');
      await tester.tap(find.byKey(const Key('note-task-0')));
      await tester.pumpAndSettle();
      expect(deps.notes.updates, isEmpty);
    });

    testWidgets('table of contents in the side panel on wide screens', (
      tester,
    ) async {
      await _open(tester, content: _long, size: const Size(1400, 900));
      expect(find.byKey(const Key('note-toc')), findsOneWidget);
      expect(find.byKey(const Key('note-toc-button')), findsNothing);
      await tester.tap(find.byKey(const Key('note-toc-3')));
      await tester.pumpAndSettle();
      expect(find.text('Mitochondria'), findsWidgets);
    });

    testWidgets('table of contents sheet on phones', (tester) async {
      await _open(tester, content: _long, size: const Size(400, 800));
      expect(find.byKey(const Key('note-toc')), findsNothing);
      await tester.tap(find.byKey(const Key('note-toc-button')));
      await tester.pumpAndSettle();
      expect(find.text('On this page'), findsOneWidget);
      await tester.tap(find.byKey(const Key('note-toc-2')));
      await tester.pumpAndSettle();
      expect(find.text('On this page'), findsNothing);
    });

    testWidgets('short notes have no table of contents', (tester) async {
      await _open(tester, size: const Size(1400, 900));
      expect(find.byKey(const Key('note-toc')), findsNothing);
      expect(find.byKey(const Key('note-reading-time')), findsOneWidget);
    });
  });

  group('AI note tools', () {
    testWidgets('locked without an AI key: opens the setup sheet', (
      tester,
    ) async {
      final tools = FakeAiToolsService();
      await _open(tester, ai: false, tools: tools);
      await tester.tap(
        find.byKey(const Key('note-ai-menu')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(find.text('Set up AI'), findsOneWidget);
      expect(find.byKey(const Key('ai-tool-summarize')), findsNothing);
      expect(tools.calls, isEmpty);
    });

    testWidgets('summarize -> replace note content (with undo)', (
      tester,
    ) async {
      final tools = FakeAiToolsService()..respond = (_, _) => '# Summary';
      final deps = await _open(tester, tools: tools);
      await _runTool(tester, NoteToolKind.summarize);

      expect(tools.calls.single.$1, startsWith('Cells are small.'));
      expect(tools.calls.single.$2, NoteTool.summarize);
      expect(find.byKey(const Key('ai-panel')), findsOneWidget);
      expect(find.text('Summary'), findsWidgets);

      // Before/after toggle shows the original.
      await tester.tap(find.text('Original'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Cells are small.'), findsWidgets);
      await tester.tap(find.text('Result'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('ai-replace')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ai-panel')), findsNothing);
      expect(deps.notes.updates.last.contentMd, '# Summary');

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(deps.notes.updates.last.contentMd, startsWith('Cells are small.'));
    });

    testWidgets('study guide -> insert below', (tester) async {
      final tools = FakeAiToolsService()..respond = (_, _) => '## Guide';
      final deps = await _open(tester, content: 'Body', tools: tools);
      await _runTool(tester, NoteToolKind.studyGuide);
      await tester.tap(find.byKey(const Key('ai-insert')));
      await tester.pumpAndSettle();
      expect(deps.notes.updates.last.contentMd, 'Body\n\n## Guide\n');
    });

    testWidgets('translate asks for a language and saves as a new note', (
      tester,
    ) async {
      final tools = FakeAiToolsService()..respond = (_, _) => 'Hola';
      final deps = await _open(tester, tools: tools);
      await _runTool(tester, NoteToolKind.translate);
      await tester.tap(find.byKey(const Key('lang-Spanish')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('lang-translate')));
      await tester.pumpAndSettle();
      expect(tools.calls.single.$2, NoteTool.translate('Spanish'));
      expect(find.text('Translate to Spanish'), findsOneWidget);

      await tester.tap(find.byKey(const Key('ai-save-new')));
      await tester.pumpAndSettle();
      final created = deps.notes.updates.isEmpty
          ? null
          : deps.notes.updates.last;
      expect(created, isNull); // Nothing was overwritten.
      final notes = await deps.notes.watchBySubject('s1').first;
      final copy = notes.singleWhere((n) => n.id != 'note1');
      expect(copy.title, 'Células (Spanish)');
      expect(copy.contentMd, 'Hola');
      expect(find.text('Saved as "Células (Spanish)"'), findsOneWidget);
    });

    testWidgets('read-only notes: only save as new (subject picker) and copy', (
      tester,
    ) async {
      final tools = FakeAiToolsService()..respond = (_, _) => 'Short';
      final deps = await _open(tester, ownerId: 'other', tools: tools);
      deps.subjects.seed(id: 'mine', title: 'My biology');
      await _runTool(tester, NoteToolKind.simplify);
      expect(find.byKey(const Key('ai-replace')), findsNothing);
      expect(find.byKey(const Key('ai-insert')), findsNothing);
      expect(find.byKey(const Key('ai-copy')), findsOneWidget);

      await tester.tap(find.byKey(const Key('ai-save-new')));
      await tester.pumpAndSettle();
      expect(find.text('Save to subject'), findsOneWidget);
      await tester.tap(find.byKey(const Key('pick-subject-mine')));
      await tester.pumpAndSettle();

      final notes = await deps.notes.watchBySubject('mine').first;
      expect(notes.single.title, 'Cells (Simplified)');
      expect(notes.single.contentMd, 'Short');
      expect(deps.notes.updates, isEmpty);
    });

    testWidgets('progress can be cancelled; result is ignored', (tester) async {
      final tools = FakeAiToolsService()..gate = Completer<void>();
      final deps = await _open(tester, tools: tools);
      await tester.tap(find.byKey(const Key('note-ai-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ai-tool-expand')));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(find.byKey(const Key('ai-progress')), findsOneWidget);
      expect(find.text('Expanding your note…'), findsOneWidget);

      await tester.tap(find.byKey(const Key('ai-cancel')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ai-panel')), findsNothing);
      tools.gate!.complete();
      await tester.pumpAndSettle();
      expect(deps.notes.updates, isEmpty);
    });

    testWidgets('errors are friendly and can be retried', (tester) async {
      final tools = FakeAiToolsService()
        ..nextError = const AiException(
          'Too many requests.',
          kind: AiErrorKind.rateLimited,
        );
      await _open(tester, tools: tools);
      await _runTool(tester, NoteToolKind.fixFormatting);
      expect(find.byKey(const Key('ai-error')), findsOneWidget);
      expect(find.text('Rate limit or quota reached'), findsOneWidget);

      await tester.tap(find.byKey(const Key('ai-retry')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ai-error')), findsNothing);
      expect(find.byKey(const Key('ai-replace')), findsOneWidget);
      expect(tools.calls, hasLength(2));
    });

    testWidgets('editor AI tools replace the unsaved text', (tester) async {
      final tools = FakeAiToolsService()..respond = (md, _) => md.toUpperCase();
      setWindowSize(tester, const Size(1400, 900));
      final deps = TestDeps()..configureAi();
      deps.notes.seed(id: 'n1', subjectId: 's1', contentMd: 'saved');
      await tester.pumpWidget(
        noteTestApp(deps, '/notes/n1/edit', tools: tools),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('note-content')), 'draft');
      await tester.pump();

      await _runTool(tester, NoteToolKind.fixFormatting);
      // Wide screens use a side panel.
      expect(find.byKey(const Key('ai-panel')), findsOneWidget);
      await tester.tap(find.byKey(const Key('ai-replace')));
      await tester.pumpAndSettle();
      final text = tester
          .widget<TextField>(find.byKey(const Key('note-content')))
          .controller!
          .text;
      expect(text, 'DRAFT');
      expect(tools.calls.single.$1, 'draft');
    });
  });
}
