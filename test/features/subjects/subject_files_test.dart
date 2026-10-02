import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:quiz_app/core/widgets/locked_feature.dart';
import 'package:quiz_app/data/models/models.dart';
import 'package:quiz_app/data/repositories/attachment_repository.dart';
import 'package:quiz_app/features/subjects/application/attachment_actions.dart';
import 'package:quiz_app/features/subjects/application/attachment_picker.dart';
import 'package:quiz_app/features/subjects/application/file_saver.dart';
import 'package:quiz_app/features/subjects/presentation/subject_detail_screen.dart';

import 'support/fakes.dart';

class _FakePicker implements AttachmentFilePicker {
  List<PickedAttachmentFile> next = const [];

  @override
  Future<List<PickedAttachmentFile>> pickFiles() async => next;
}

class _FakeSaver implements FileSaver {
  final List<String> saved = [];

  @override
  Future<String?> save(
    String fileName,
    Uint8List bytes, {
    String? mimeType,
  }) async {
    saved.add(fileName);
    return '/downloads/$fileName';
  }
}

Uint8List _bytes(String s) => Uint8List.fromList(utf8.encode(s));

Future<void> _pumpFiles(
  WidgetTester tester,
  TestDeps deps, {
  _FakePicker? picker,
  _FakeSaver? saver,
  String subjectId = 's1',
}) async {
  tester.view.physicalSize = const Size(1100, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: '/subjects/$subjectId',
    routes: [
      GoRoute(
        path: '/subjects/:id',
        builder: (_, state) =>
            SubjectDetailScreen(subjectId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/ai/generate',
        builder: (_, state) => Text('generate ${state.uri}'),
      ),
      GoRoute(path: '/settings', builder: (_, _) => const Text('settings')),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...deps.overrides,
        attachmentFilePickerProvider.overrideWithValue(picker ?? _FakePicker()),
        fileSaverProvider.overrideWithValue(saver ?? _FakeSaver()),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Files'));
  // Not pumpAndSettle: an "Uploading…" spinner never settles.
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  test('formatFileSize', () {
    expect(formatFileSize(512), '512 B');
    expect(formatFileSize(2048), '2 KB');
    expect(formatFileSize(1572864), '1.5 MB');
    expect(formatFileSize(50 * 1024 * 1024), '50 MB');
  });

  testWidgets('upload adds files, extracts text and reports size errors', (
    tester,
  ) async {
    final deps = TestDeps();
    deps.subjects.seed(id: 's1', title: 'Biology');
    final picker = _FakePicker()
      ..next = [
        PickedAttachmentFile.bytes('notes.md', _bytes('# Cells\nMitosis')),
        PickedAttachmentFile.bytes('slides.pdf', _bytes('%PDF-1.7')),
        PickedAttachmentFile(
          name: 'lecture.mp4',
          size: Attachment.maxSizeBytes + 1,
          read: () => throw StateError('must not be read'),
        ),
      ];
    await _pumpFiles(tester, deps, picker: picker);
    expect(find.text('No files yet'), findsOneWidget);

    await tester.tap(find.byKey(const Key('files-upload')));
    await tester.pumpAndSettle();

    final added = deps.attachments.added;
    expect(added.map((a) => a.name), ['notes.md', 'slides.pdf']);
    expect(added.first.extractedText, '# Cells\nMitosis');
    expect(added.last.extractedText, isNull);
    expect(find.text('notes.md'), findsOneWidget);
    expect(find.text('slides.pdf'), findsOneWidget);

    final errors = find.byKey(const Key('files-upload-errors'));
    expect(errors, findsOneWidget);
    expect(
      find.descendant(of: errors, matching: find.textContaining('lecture.mp4')),
      findsOneWidget,
    );
    expect(find.textContaining('at most 50 MB'), findsOneWidget);

    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pumpAndSettle();
    expect(errors, findsNothing);
  });

  testWidgets('rows show kind icons, size and upload status', (tester) async {
    final deps = TestDeps();
    deps.subjects.seed(id: 's1');
    final names = {
      'a.pdf': AttachmentKind.pdf,
      'b.png': AttachmentKind.image,
      'c.txt': AttachmentKind.text,
      'd.docx': AttachmentKind.docx,
      'e.mp3': AttachmentKind.audio,
      'f.mov': AttachmentKind.video,
      'g.zip': AttachmentKind.other,
    };
    for (final name in names.keys) {
      deps.attachments.seed(name: name, sizeBytes: 1572864);
    }
    deps.attachments.uploads['a1'] = const AttachmentUploadState(
      AttachmentUploadPhase.uploading,
    );
    deps.attachments.uploads['a2'] = const AttachmentUploadState(
      AttachmentUploadPhase.queued,
    );
    await _pumpFiles(tester, deps);

    for (final kind in names.values) {
      expect(
        find.byKey(Key('attachment-icon-${kind.name}')),
        findsOneWidget,
        reason: kind.name,
      );
    }
    expect(find.byIcon(Icons.picture_as_pdf_outlined), findsOneWidget);
    expect(find.textContaining('1.5 MB'), findsNWidgets(names.length));
    expect(find.text('Uploading…'), findsOneWidget);
    expect(find.text('Waiting to upload'), findsOneWidget);
  });

  testWidgets('owner renames, deletes and previews text files', (tester) async {
    final deps = TestDeps();
    deps.subjects.seed(id: 's1');
    deps.attachments.seed(
      id: 'a1',
      name: 'reading.txt',
      extractedText: 'Photosynthesis basics',
    );
    final saver = _FakeSaver();
    await _pumpFiles(tester, deps, saver: saver);

    // Preview shows the extracted text.
    await tester.tap(find.text('reading.txt'));
    await tester.pumpAndSettle();
    expect(find.text('Photosynthesis basics'), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    // Rename.
    await tester.tap(find.byKey(const Key('attachment-menu-a1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('attachment-rename')),
      'chapter 1.txt',
    );
    await tester.tap(find.byKey(const Key('attachment-rename-save')));
    await tester.pumpAndSettle();
    expect(find.text('chapter 1.txt'), findsOneWidget);

    // Delete.
    await tester.tap(find.byKey(const Key('attachment-menu-a1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(deps.attachments.deleted, ['a1']);
    expect(find.text('No files yet'), findsOneWidget);
  });

  testWidgets('PDFs are downloaded to open externally', (tester) async {
    final deps = TestDeps();
    deps.subjects.seed(id: 's1');
    deps.attachments.seed(id: 'a1', name: 'slides.pdf', data: _bytes('%PDF'));
    final saver = _FakeSaver();
    await _pumpFiles(tester, deps, saver: saver);

    await tester.tap(find.text('slides.pdf'));
    await tester.pumpAndSettle();
    expect(saver.saved, ['slides.pdf']);
    expect(find.text('Saved to /downloads/slides.pdf'), findsOneWidget);
  });

  testWidgets('shared subject files are read-only', (tester) async {
    final deps = TestDeps();
    deps.subjects.seed(id: 's9', ownerId: 'other');
    deps.attachments.seed(id: 'a1', subjectId: 's9', ownerId: 'other');
    await _pumpFiles(tester, deps, subjectId: 's9');

    expect(find.byKey(const Key('files-read-only')), findsOneWidget);
    expect(find.byKey(const Key('files-upload')), findsNothing);
    expect(find.byKey(const Key('attachment-ai-a1')), findsNothing);

    await tester.tap(find.byKey(const Key('attachment-menu-a1')));
    await tester.pumpAndSettle();
    expect(find.text('Download'), findsOneWidget);
    expect(find.text('Rename'), findsNothing);
    expect(find.text('Delete'), findsNothing);
  });

  testWidgets('"Use in AI" is locked until AI is set up', (tester) async {
    final deps = TestDeps();
    deps.subjects.seed(id: 's1');
    deps.attachments.seed(id: 'a1', name: 'slides.pdf');
    await _pumpFiles(tester, deps);

    final gate = find.ancestor(
      of: find.byKey(const Key('attachment-ai-a1')),
      matching: find.byType(LockedFeature),
    );
    expect(
      find.descendant(of: gate, matching: find.byKey(LockedFeature.badgeKey)),
      findsOneWidget,
    );
    await tester.tap(gate);
    await tester.pumpAndSettle();
    expect(find.text('Set up AI'), findsOneWidget);
    await tester.tap(find.text('Open Settings'));
    await tester.pumpAndSettle();
    expect(find.text('settings'), findsOneWidget);
  });

  testWidgets('"Use in AI" opens the generator when AI is ready', (
    tester,
  ) async {
    final deps = TestDeps()..configureAi();
    deps.subjects.seed(id: 's1');
    deps.attachments.seed(id: 'a1', name: 'slides.pdf');
    await _pumpFiles(tester, deps);

    expect(find.byKey(LockedFeature.badgeKey), findsNothing);
    await tester.tap(find.byKey(const Key('attachment-ai-a1')));
    await tester.pumpAndSettle();
    expect(
      find.text('generate /ai/generate?kind=quiz&subjectId=s1'),
      findsOneWidget,
    );
  });
}
