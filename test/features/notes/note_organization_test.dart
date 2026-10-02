import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:quiz_app/core/utils/file_saver.dart';
import 'package:quiz_app/core/widgets/locked_feature.dart';
import 'package:quiz_app/core/widgets/tag_widgets.dart';
import 'package:quiz_app/data/data_providers.dart';
import 'package:quiz_app/features/subjects/presentation/subject_detail_screen.dart';

import '../search/support/org_fakes.dart';
import '../subjects/support/fakes.dart';
import 'support/note_test_app.dart';

/// 1x1 PNG.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
);

class _Env {
  _Env(this.deps, this.org, this.saver);

  final TestDeps deps;
  final FakeOrganizationRepository org;
  final FakeFileSaver saver;

  List<Override> get overrides => [
    organizationRepositoryProvider.overrideWithValue(org),
    fileSaverProvider.overrideWithValue(saver),
  ];
}

/// Fakes where tag / pin writes reach the fake note repository.
Future<_Env> _env({
  String ownerId = kUserId,
  List<String> tags = const [],
  bool pinned = false,
  String content = '# Cells\n\nCells are small.',
  bool ai = true,
}) async {
  final deps = TestDeps();
  if (ai) deps.configureAi();
  deps.subjects.seed(id: 's1', title: 'Biology', ownerId: ownerId);
  final note = deps.notes.seed(
    id: 'note1',
    subjectId: 's1',
    title: 'Cells',
    contentMd: content,
    ownerId: ownerId,
  );
  if (tags.isNotEmpty || pinned) {
    await deps.notes.update(note.copyWith(tags: tags, pinned: pinned));
    deps.notes.updates.clear();
  }
  final org = FakeOrganizationRepository()
    ..onItem = (kind, id, {tags, pinned}) {
      deps.notes.getById(id).then((n) {
        if (n == null) return;
        deps.notes.update(
          n.copyWith(tags: tags ?? n.tags, pinned: pinned ?? n.pinned),
        );
      });
    };
  return _Env(deps, org, FakeFileSaver());
}

Future<void> _pump(
  WidgetTester tester,
  _Env env, {
  String location = '/notes/note1',
  Size size = const Size(1000, 1000),
}) async {
  setWindowSize(tester, size);
  await tester.pumpWidget(
    noteTestApp(env.deps, location, overrides: env.overrides),
  );
  await tester.pumpAndSettle();
}

Finder get _launcher => find.byKey(const Key('chat-launcher-note1'));

void main() {
  group('Ask AI launcher', () {
    testWidgets('in the note app bar, unlocked when AI is set up', (
      tester,
    ) async {
      final env = await _env();
      await _pump(tester, env);
      expect(_launcher, findsOneWidget);
      expect(
        find.ancestor(of: _launcher, matching: find.byType(LockedFeature)),
        findsNothing,
      );
      expect(find.byTooltip('Ask AI about this note'), findsOneWidget);
    });

    testWidgets('locked until AI is set up', (tester) async {
      final env = await _env(ai: false);
      await _pump(tester, env);
      expect(
        find.ancestor(of: _launcher, matching: find.byType(LockedFeature)),
        findsOneWidget,
      );
      await tester.tap(_launcher, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('Set up AI'), findsOneWidget);
    });

    testWidgets('also offered on shared (read-only) notes', (tester) async {
      final env = await _env(ownerId: 'other');
      await _pump(tester, env);
      expect(_launcher, findsOneWidget);
    });
  });

  group('tags', () {
    testWidgets('owner adds a tag; chips show it and open tag search', (
      tester,
    ) async {
      final env = await _env();
      await _pump(tester, env);
      expect(find.text('Add tags'), findsOneWidget);

      await tester.tap(find.byKey(const Key('note-tags-button')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(TagEditor.fieldKey), 'Exam Prep,');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('tag-dialog-save')));
      await tester.pumpAndSettle();

      expect(env.org.calls, ['setTags:note:note1:exam prep']);
      expect(find.byKey(const ValueKey('tag-chip-exam prep')), findsOneWidget);
      expect(find.text('Edit tags'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('tag-chip-exam prep')));
      await tester.pumpAndSettle();
      expect(find.text('search tag:"exam prep"'), findsOneWidget);
    });

    testWidgets('shared notes show tags read-only (no edit, no pin)', (
      tester,
    ) async {
      final env = await _env(ownerId: 'other', tags: ['exam']);
      await _pump(tester, env);
      expect(find.byKey(const ValueKey('tag-chip-exam')), findsOneWidget);
      expect(find.byKey(const Key('note-tags-button')), findsNothing);
      expect(find.byKey(const Key('pin-button')), findsNothing);
      await tester.tap(find.byKey(const Key('note-more')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('note-menu-tags')), findsNothing);
      expect(find.byKey(const Key('note-menu-copy-md')), findsOneWidget);
    });

    testWidgets('editor edits tags and later saves keep them', (tester) async {
      final env = await _env();
      await _pump(tester, env, location: '/notes/note1/edit');

      await tester.tap(find.byKey(const Key('note-editor-tags-button')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(TagEditor.fieldKey), 'exam,');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('tag-dialog-save')));
      await tester.pumpAndSettle();
      expect(env.org.calls, ['setTags:note:note1:exam']);
      expect(find.byKey(const ValueKey('tag-chip-exam')), findsOneWidget);

      await tester.enterText(find.byKey(const Key('note-content')), 'New body');
      await tester.tap(find.byKey(const Key('note-save')));
      await tester.pumpAndSettle();
      final saved = env.deps.notes.updates.last;
      expect(saved.contentMd, 'New body');
      expect(saved.tags, ['exam']);
    });
  });

  group('pin', () {
    testWidgets('app bar toggle on wide screens', (tester) async {
      final env = await _env();
      await _pump(tester, env);
      expect(find.byKey(const Key('note-pinned-indicator')), findsNothing);
      await tester.tap(find.byKey(const Key('pin-button')));
      await tester.pumpAndSettle();
      expect(env.org.calls, ['setPinned:note:note1:true']);
      expect(find.byKey(const Key('note-pinned-indicator')), findsOneWidget);
      expect(find.byTooltip('Unpin'), findsOneWidget);
    });

    testWidgets('"More" menu on phones', (tester) async {
      final env = await _env(pinned: true);
      await _pump(tester, env, size: const Size(400, 900));
      expect(find.byKey(const Key('pin-button')), findsNothing);
      await tester.tap(find.byKey(const Key('note-more')));
      await tester.pumpAndSettle();
      expect(find.text('Unpin note'), findsOneWidget);
      await tester.tap(find.byKey(const Key('note-menu-pin')));
      await tester.pumpAndSettle();
      expect(env.org.calls, ['setPinned:note:note1:false']);
      expect(find.text('Note unpinned'), findsOneWidget);
    });

    testWidgets('subject Notes tab lists pinned notes first with tags', (
      tester,
    ) async {
      final env = await _env();
      final deps = env.deps;
      deps.notes.seed(
        id: 'recent',
        title: 'Recent note',
        updatedAt: kNow.add(const Duration(days: 2)),
      );
      final old = deps.notes.seed(
        id: 'old',
        title: 'Old pinned note',
        updatedAt: kNow.subtract(const Duration(days: 9)),
      );
      await deps.notes.update(old.copyWith(pinned: true, tags: ['exam']));
      setWindowSize(tester, const Size(1000, 1000));
      final router = GoRouter(
        initialLocation: '/subjects/s1',
        routes: [
          GoRoute(
            path: '/subjects/:id',
            builder: (_, state) =>
                SubjectDetailScreen(subjectId: state.pathParameters['id']!),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [...deps.overrides, ...env.overrides],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      double top(String id) =>
          tester.getTopLeft(find.byKey(ValueKey('note-row-$id'))).dy;
      expect(top('old'), lessThan(top('note1')));
      expect(top('old'), lessThan(top('recent')));
      expect(find.byKey(const ValueKey('note-pinned-old')), findsOneWidget);
      expect(find.byKey(const ValueKey('tag-chip-exam')), findsOneWidget);

      // Row menu pins another note.
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('note-row-recent')),
          matching: find.byTooltip('More'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('note-row-pin-recent')));
      await tester.pumpAndSettle();
      expect(env.org.calls, ['setPinned:note:recent:true']);
      expect(top('recent'), lessThan(top('note1')));
    });
  });

  group('export', () {
    const content =
        '# Cells\n\nCells are **small** – “really”.\n\n'
        '- [x] read\n- item\n\n```dart\nvoid main() {}\n```\n\n'
        '| a | b |\n|---|---|\n| 1 | 2 |\n\n'
        r'$$E = mc^2$$'
        '\n\n![diagram](note-image://user-1/note1/img1.png)\n';

    testWidgets('Markdown and PDF from the export menu', (tester) async {
      final env = await _env(tags: ['exam'], content: content);
      env.deps.images.saved['user-1/note1/img1.png'] = _png;
      await _pump(tester, env);

      await tester.tap(find.byKey(const Key('note-export')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('export-note-md')));
      await tester.pumpAndSettle();
      final md = env.saver.saved.single;
      expect(md.name, 'Cells.md');
      expect(md.mimeType, 'text/markdown');
      final text = utf8.decode(md.bytes);
      expect(text, startsWith('---\ntitle: "Cells"\nsubject: "Biology"\n'));
      expect(text, contains('tags: ["exam"]\n'));
      expect(text, endsWith('---\n\n$content'));

      await tester.tap(find.byKey(const Key('note-export')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('export-note-pdf')));
      await tester.pumpAndSettle();
      final pdf = env.saver.saved.last;
      expect(pdf.name, 'Cells.pdf');
      expect(pdf.mimeType, 'application/pdf');
      expect(pdf.bytes.length, greaterThan(500));
      expect(ascii.decode(pdf.bytes.sublist(0, 4)), '%PDF');
      expect(find.text('Exported "Cells.pdf"'), findsOneWidget);
    });

    testWidgets('phone "More" menu exports a PDF; shared notes can export', (
      tester,
    ) async {
      final env = await _env(ownerId: 'other', content: content);
      await _pump(tester, env, size: const Size(400, 900));
      expect(find.byKey(const Key('note-export')), findsNothing);
      await tester.tap(find.byKey(const Key('note-more')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('note-menu-export-pdf')));
      await tester.pumpAndSettle();
      final pdf = env.saver.saved.single;
      expect(pdf.name, 'Cells.pdf');
      expect(ascii.decode(pdf.bytes.sublist(0, 5)), '%PDF-');
    });

    testWidgets(
      'Copy as Markdown puts the front-matter file on the clipboard',
      (tester) async {
        String? copied;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'] as String?;
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        final env = await _env(tags: ['exam']);
        await _pump(tester, env);
        await tester.tap(find.byKey(const Key('note-more')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('note-menu-copy-md')));
        await tester.pumpAndSettle();
        expect(copied, startsWith('---\ntitle: "Cells"\n'));
        expect(copied, contains('tags: ["exam"]'));
        expect(copied, endsWith('# Cells\n\nCells are small.\n'));
        expect(find.text('Copied as Markdown'), findsOneWidget);
        expect(env.saver.saved, isEmpty);
      },
    );
  });
}
