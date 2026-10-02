import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:quiz_app/core/widgets/note_markdown.dart';
import 'package:quiz_app/features/notes/application/note_image_picker.dart';
import 'package:quiz_app/features/notes/presentation/note_edit_screen.dart';
import 'package:quiz_app/features/notes/presentation/note_view_screen.dart';

import '../subjects/support/fakes.dart';

class _FakePicker implements NoteImagePicker {
  @override
  Future<PickedImage?> pickImage() async => PickedImage(
    bytes: Uint8List.fromList([1, 2, 3]),
    extension: 'png',
    name: 'diagram.png',
  );
}

Widget _app(TestDeps deps, String initial) {
  final router = GoRouter(
    initialLocation: initial,
    routes: [
      GoRoute(
        path: '/notes/:id',
        builder: (_, state) =>
            NoteViewScreen(noteId: state.pathParameters['id']!),
        routes: [
          GoRoute(
            path: 'edit',
            builder: (_, state) =>
                NoteEditScreen(noteId: state.pathParameters['id']!),
          ),
        ],
      ),
      GoRoute(
        path: '/subjects/:id',
        builder: (_, state) => Text('subject ${state.pathParameters['id']}'),
      ),
      GoRoute(
        path: '/ai/generate',
        builder: (_, state) => Text(state.uri.toString()),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      ...deps.overrides,
      noteImagePickerProvider.overrideWithValue(_FakePicker()),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

String _content(WidgetTester tester) => tester
    .widget<TextField>(find.byKey(const Key('note-content')))
    .controller!
    .text;

void main() {
  testWidgets('toolbar bold inserts markers; save persists', (tester) async {
    final deps = TestDeps();
    deps.subjects.seed(id: 's1');
    deps.notes.seed(id: 'n1', subjectId: 's1', title: 'Cells');
    await tester.pumpWidget(_app(deps, '/notes/n1/edit'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('md-bold')));
    await tester.pump();
    expect(_content(tester), '**bold**');

    await tester.tap(find.byKey(const Key('md-bullets')));
    await tester.pump();
    expect(_content(tester), '- **bold**');

    await tester.tap(find.byKey(const Key('note-save')));
    await tester.pumpAndSettle();
    expect(deps.notes.updates.last.contentMd, '- **bold**');
    expect(deps.notes.updates.last.title, 'Cells');
  });

  testWidgets('insert image stores bytes and inserts a note-image ref', (
    tester,
  ) async {
    final deps = TestDeps();
    deps.notes.seed(id: 'n1', subjectId: 's1', contentMd: 'Intro');
    await tester.pumpWidget(_app(deps, '/notes/n1/edit'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('md-image')));
    await tester.pumpAndSettle();

    expect(deps.images.saved.keys, ['user-1/n1/img1.png']);
    expect(
      _content(tester),
      contains('![diagram](note-image://user-1/n1/img1.png)'),
    );
  });

  testWidgets('autosaves after a pause', (tester) async {
    final deps = TestDeps();
    deps.notes.seed(id: 'n1', subjectId: 's1');
    await tester.pumpWidget(_app(deps, '/notes/n1/edit'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('note-content')), 'draft');
    await tester.pump();
    expect(deps.notes.updates, isEmpty);
    await tester.pump(
      NoteEditScreen.autosaveDelay + const Duration(milliseconds: 100),
    );
    await tester.pumpAndSettle();
    expect(deps.notes.updates.single.contentMd, 'draft');
  });

  testWidgets('unsaved-changes guard on back', (tester) async {
    final deps = TestDeps();
    deps.notes.seed(id: 'n1', subjectId: 's1', title: 'Cells');
    await tester.pumpWidget(_app(deps, '/notes/n1/edit'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('note-content')), 'changed');
    await tester.pump();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Unsaved changes'), findsOneWidget);

    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(deps.notes.updates, isEmpty);
    expect(find.byType(NoteViewScreen), findsOneWidget);
  });

  testWidgets('untouched new note is discarded on back', (tester) async {
    final deps = TestDeps();
    deps.notes.seed(id: 'n1', subjectId: 's1', title: kUntitledNoteTitle);
    await tester.pumpWidget(_app(deps, '/notes/n1/edit'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(deps.notes.deleted, ['n1']);
  });

  testWidgets('note view renders markdown and resolves note images', (
    tester,
  ) async {
    final deps = TestDeps();
    deps.subjects.seed(id: 's1', title: 'Biology');
    final image = await deps.images.saveNoteImage(
      noteId: 'n1',
      bytes: Uint8List.fromList([1, 2, 3]),
      extension: 'png',
    );
    deps.notes.seed(
      id: 'n1',
      subjectId: 's1',
      title: 'Cells',
      contentMd: '# Mitochondria\n\n![cell](${image.markdownUrl})',
    );
    await tester.pumpWidget(_app(deps, '/notes/n1'));
    await tester.pumpAndSettle();

    expect(find.text('Mitochondria'), findsOneWidget);
    expect(find.byType(NoteMarkdownImage), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(find.byKey(const Key('note-edit')), findsOneWidget);

    await tester.tap(find.byTooltip('Generate quiz from this note'));
    await tester.pumpAndSettle();
    expect(
      find.text('/ai/generate?kind=quiz&subjectId=s1&noteId=n1'),
      findsOneWidget,
    );
  });

  testWidgets('shared note is read-only', (tester) async {
    final deps = TestDeps();
    deps.notes.seed(
      id: 'n1',
      subjectId: 's1',
      ownerId: 'other',
      contentMd: 'x',
    );
    await tester.pumpWidget(_app(deps, '/notes/n1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('note-edit')), findsNothing);
    expect(find.text('Shared · read-only'), findsOneWidget);
  });

  for (final size in const [Size(360, 740), Size(1280, 800)]) {
    testWidgets('layouts fit at ${size.width.toInt()}px', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final deps = TestDeps();
      deps.subjects.seed(id: 's1', title: 'Biology', description: 'Cells');
      deps.notes.seed(
        id: 'n1',
        subjectId: 's1',
        title: 'A rather long note title for small screens',
        contentMd: '# Heading\n\nBody text with **bold**.',
      );
      await tester.pumpWidget(_app(deps, '/notes/n1/edit'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('note-content')), findsOneWidget);
      if (size.width >= 1000) {
        expect(find.byKey(const Key('note-preview')), findsOneWidget);
      }
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(NoteViewScreen), findsOneWidget);
    });
  }
}
