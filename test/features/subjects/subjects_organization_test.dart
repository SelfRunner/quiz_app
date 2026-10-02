import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:quiz_app/core/utils/file_saver.dart';
import 'package:quiz_app/data/data_providers.dart';
import 'package:quiz_app/data/models/models.dart';
import 'package:quiz_app/data/repositories/deck_repository.dart';
import 'package:quiz_app/data/repositories/organization_repository.dart';
import 'package:quiz_app/features/subjects/presentation/subjects_screen.dart';

import '../search/support/org_fakes.dart';
import 'support/fakes.dart';

/// Decks of one subject (export only).
class _Decks implements DeckRepository {
  _Decks(this.decks);

  final List<Deck> decks;

  @override
  Stream<List<Deck>> watchBySubject(String subjectId) => Stream.value([
    for (final d in decks)
      if (d.subjectId == subjectId) d,
  ]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Env {
  final deps = TestDeps();
  final org = FakeOrganizationRepository(now: kNow);
  final saver = FakeFileSaver();
  final decks = <Deck>[];

  Future<void> pump(
    WidgetTester tester, {
    Size size = const Size(1100, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const SubjectsScreen()),
        GoRoute(
          path: '/subjects/:id',
          builder: (_, s) => Text('subject ${s.pathParameters['id']}'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...deps.overrides,
          organizationRepositoryProvider.overrideWithValue(org),
          subjectsProvider.overrideWith((ref) => org.watchSubjects()),
          archivedSubjectsProvider.overrideWith(
            (ref) => org.watchSubjects(
              const SubjectListQuery(archive: ArchiveFilter.archived),
            ),
          ),
          fileSaverProvider.overrideWithValue(saver),
          deckRepositoryProvider.overrideWithValue(_Decks(decks)),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }
}

List<String> _titles(WidgetTester tester) => [
  for (final c in tester.widgetList<SubjectCard>(find.byType(SubjectCard)))
    c.subject.title,
];

Future<void> _menu(WidgetTester tester, String subjectId, String action) async {
  await tester.tap(find.byKey(ValueKey('subject-menu-$subjectId')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey('subject-menu-$action')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('pinned subjects come first in their own section', (
    tester,
  ) async {
    final env = _Env();
    env.org
      ..seed('s1', 'Algebra')
      ..seed('s2', 'Biology', pinned: true)
      ..seed('s3', 'Chemistry');
    await env.pump(tester);
    expect(find.byKey(const Key('subjects-pinned-header')), findsOneWidget);
    expect(find.text('Pinned  1'), findsOneWidget);
    expect(_titles(tester).first, 'Biology');
    expect(find.byKey(const ValueKey('subject-pin-icon')), findsOneWidget);

    // Pin another from its menu: it joins the pinned section.
    await _menu(tester, 's3', 'pin');
    expect(env.org.calls, ['pinSubject:s3:true']);
    expect(_titles(tester).take(2), ['Biology', 'Chemistry']);

    // Unpin both: the section disappears.
    await _menu(tester, 's2', 'pin');
    await _menu(tester, 's3', 'pin');
    expect(find.byKey(const Key('subjects-pinned-header')), findsNothing);
  });

  testWidgets('archive hides a subject; archived view restores it', (
    tester,
  ) async {
    final env = _Env();
    env.org
      ..seed('s1', 'Algebra')
      ..seed('s2', 'Biology');
    await env.pump(tester);

    await _menu(tester, 's2', 'archive');
    expect(env.org.calls, ['archive:s2']);
    expect(_titles(tester), ['Algebra']);
    expect(find.text('Archived "Biology"'), findsOneWidget);

    await tester.tap(find.byKey(const Key('subjects-archived-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('Archived  1'), findsOneWidget);
    expect(_titles(tester), ['Biology']);
    expect(find.byKey(const ValueKey('subject-archived-icon')), findsOneWidget);
    expect(find.byKey(const Key('new-subject-fab')), findsNothing);

    // No "Pin" for archived subjects; unarchive brings it back.
    await tester.tap(find.byKey(const ValueKey('subject-menu-s2')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('subject-menu-pin')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('subject-menu-archive')));
    await tester.pumpAndSettle();
    expect(env.org.calls.last, 'unarchive:s2');
    expect(find.text('No archived subjects'), findsOneWidget);

    await tester.tap(find.byKey(const Key('subjects-show-active')));
    await tester.pumpAndSettle();
    expect(_titles(tester), ['Algebra', 'Biology']);
  });

  testWidgets('undo after archiving; empty list links to archived view', (
    tester,
  ) async {
    final env = _Env();
    env.org.seed('s1', 'Algebra');
    await env.pump(tester);
    await _menu(tester, 's1', 'archive');
    expect(find.text('No subjects yet'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(env.org.calls, ['archive:s1', 'unarchive:s1']);
    expect(_titles(tester), ['Algebra']);

    await _menu(tester, 's1', 'archive');
    await tester.tap(find.byKey(const Key('subjects-show-archived-empty')));
    await tester.pumpAndSettle();
    expect(_titles(tester), ['Algebra']);
  });

  testWidgets('sort by recently created', (tester) async {
    final env = _Env();
    env.org
      ..seed('s1', 'Old', createdAt: kNow.subtract(const Duration(days: 9)))
      ..seed('s2', 'New', createdAt: kNow.add(const Duration(days: 1)))
      ..seed('s3', 'Mid', createdAt: kNow);
    await env.pump(tester);
    await tester.tap(find.byKey(const Key('subjects-sort')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(
        CheckedPopupMenuItem<SubjectsSort>,
        'Recently created',
      ),
    );
    await tester.pumpAndSettle();
    expect(_titles(tester), ['New', 'Mid', 'Old']);
  });

  test('sortSubjects keeps pinned first in every order', () {
    Subject s(String id, String title, {bool pinned = false, int day = 1}) =>
        Subject(
          id: id,
          ownerId: kUserId,
          title: title,
          pinned: pinned,
          createdAt: DateTime.utc(2026, 1, day),
          updatedAt: DateTime.utc(2026, 1, day),
        );
    final list = [
      s('a', 'b', day: 3),
      s('b', 'a', day: 1),
      s('c', 'c', pinned: true, day: 2),
    ];
    for (final sort in SubjectsSort.values) {
      expect(sortSubjects(list, sort).first.id, 'c');
    }
    expect(sortSubjects(list, SubjectsSort.name).map((x) => x.title), [
      'c',
      'a',
      'b',
    ]);
    expect(
      sortSubjects(list, SubjectsSort.recent, pinnedFirst: false).first.id,
      'a',
    );
  });

  testWidgets('export a subject as a Markdown zip', (tester) async {
    final env = _Env();
    env.org.seed('s1', 'Biology');
    env.deps.notes.seed(
      id: 'n1',
      subjectId: 's1',
      title: 'Cells',
      contentMd: 'The **cell**.',
    );
    env.decks.add(
      Deck(
        id: 'd1',
        subjectId: 's1',
        ownerId: kUserId,
        title: 'Cards',
        cards: const [Flashcard(id: 'c1', front: 'Q', back: 'A')],
        createdAt: kNow,
        updatedAt: kNow,
      ),
    );
    await env.pump(tester);
    await _menu(tester, 's1', 'export');

    final file = env.saver.saved.single;
    expect(file.name, 'Biology.zip');
    expect(file.mimeType, 'application/zip');
    final zip = ZipDecoder().decodeBytes(file.bytes);
    String read(String name) => utf8.decode(
      zip.files.firstWhere((f) => f.name == name).content,
    );
    expect(read('Biology/Cells.md'), contains('The **cell**.'));
    expect(read('Biology/decks/Cards.csv'), contains('Q,A'));
    expect(find.text('Exported "Biology.zip"'), findsOneWidget);
  });
}
