import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/core/errors/app_exception.dart';
import 'package:quiz_app/data/models/models.dart';
import 'package:quiz_app/data/sync/sync_engine.dart';
import 'package:quiz_app/features/sharing/presentation/shared_with_me_screen.dart';
import 'package:quiz_app/features/sharing/widgets/shared_by_chip.dart';

import 'sharing_fakes.dart';

void main() {
  final alice = profile('alice', name: 'Alice');
  final carol = profile('carol', name: 'Carol');

  List<Share> sampleShares() => [
    makeShare(
      id: 'a',
      type: ShareResourceType.subject,
      resourceId: 's1',
      owner: alice,
      title: 'Biology',
    ),
    makeShare(
      id: 'b',
      type: ShareResourceType.note,
      resourceId: 'n9',
      ownerId: 'carol',
      owner: carol,
      title: 'Cell notes',
    ),
    makeShare(
      id: 'c',
      type: ShareResourceType.quiz,
      resourceId: 'qz9',
      ownerId: 'carol',
      owner: carol,
      title: 'Cell quiz',
    ),
  ];

  Widget app(FakeShareRepository shares, {FakeSyncEngine? engine}) => harness(
    home: const SharedWithMeScreen(),
    shares: shares,
    engine: engine,
    subjects: FakeSubjectRepository([
      makeSubject('s1', 'Biology', ownerId: 'alice'),
    ]),
    notes: FakeNoteRepository([
      makeNote('n1', 's1'),
      makeNote('n2', 's1'),
      makeNote('n9', 'other', ownerId: 'carol'),
    ]),
    quizzes: FakeQuizRepository([
      makeQuiz('q1', 's1'),
      makeQuiz('qz9', 'other', ownerId: 'carol', questions: 3),
      makeQuiz('qn', 'other', noteId: 'n9', ownerId: 'carol'),
    ]),
  );

  testWidgets('groups shares by type with owner, date and counts', (
    tester,
  ) async {
    final shares = FakeShareRepository()..received = sampleShares();
    await tester.pumpWidget(app(shares));
    await tester.pumpAndSettle();

    // Section headers show the type and its count.
    expect(find.text('Subjects  1'), findsOneWidget);
    expect(find.text('Notes  1'), findsOneWidget);
    expect(find.text('Quizzes  1'), findsOneWidget);
    expect(find.text('Biology'), findsOneWidget);
    expect(find.text('Cell notes'), findsOneWidget);
    expect(find.text('Cell quiz'), findsOneWidget);
    expect(find.text('Shared by Alice'), findsOneWidget);
    expect(find.text('Shared by Carol'), findsNWidgets(2));
    expect(find.text('Sep 1, 2026 · 2 notes · 1 quiz'), findsOneWidget);
    expect(find.text('Sep 1, 2026 · 1 quiz'), findsOneWidget);
    expect(find.text('Sep 1, 2026 · 3 questions'), findsOneWidget);

    // Sections are in order Subjects, Notes, Quizzes.
    final ys = [
      'Subjects  1',
      'Notes  1',
      'Quizzes  1',
    ].map((t) => tester.getTopLeft(find.text(t)).dy).toList();
    expect(ys, orderedEquals([...ys]..sort()));
  });

  testWidgets('renders on a phone and on a wide screen', (tester) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1;
    for (final size in const [Size(360, 740), Size(1400, 900)]) {
      tester.view.physicalSize = size;
      final shares = FakeShareRepository()..received = sampleShares();
      await tester.pumpWidget(app(shares));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Cell quiz'), findsOneWidget);
    }
  });

  testWidgets('tapping an item opens its detail route', (tester) async {
    final shares = FakeShareRepository()..received = sampleShares();
    await tester.pumpWidget(app(shares));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cell notes'));
    await tester.pumpAndSettle();
    expect(find.text('note:n9'), findsOneWidget);
  });

  testWidgets('shows the empty state explaining sharing', (tester) async {
    await tester.pumpWidget(app(FakeShareRepository()));
    await tester.pumpAndSettle();

    expect(find.text('Nothing shared with you yet'), findsOneWidget);
    expect(find.textContaining(meEmail), findsOneWidget);
    expect(find.textContaining('view-only'), findsOneWidget);
  });

  testWidgets('pull-to-refresh syncs and reloads', (tester) async {
    final shares = FakeShareRepository();
    final engine = FakeSyncEngine();
    await tester.pumpWidget(app(shares, engine: engine));
    await tester.pumpAndSettle();
    expect(find.text('Nothing shared with you yet'), findsOneWidget);

    shares.received = sampleShares();
    await tester.fling(
      find.text('Nothing shared with you yet'),
      const Offset(0, 400),
      1000,
    );
    await tester.pumpAndSettle();

    expect(engine.syncCalls, 1);
    expect(find.text('Biology'), findsOneWidget);
  });

  testWidgets('offline without data shows an offline message', (tester) async {
    final shares = FakeShareRepository()
      ..sharedWithMeError = const NetworkException("You're offline.");
    await tester.pumpWidget(app(shares));
    await tester.pumpAndSettle();

    expect(find.text("You're offline"), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('shows a stale-data banner when sync is offline', (tester) async {
    final shares = FakeShareRepository()..received = sampleShares();
    await tester.pumpWidget(
      app(
        shares,
        engine: FakeSyncEngine(const SyncStatus(state: SyncState.offline)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('shared-offline-banner')), findsOneWidget);
    expect(find.text('Biology'), findsOneWidget);
  });

  testWidgets('SharedByChip resolves the owner name', (tester) async {
    final shares = FakeShareRepository()..received = sampleShares();
    await tester.pumpWidget(
      harness(
        home: const Scaffold(
          body: Column(
            children: [
              SharedByChip(ownerId: 'alice'),
              SharedByChip(ownerId: 'zed'),
              SharedByChip(ownerId: 'x', ownerName: 'Xavier'),
            ],
          ),
        ),
        shares: shares,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Shared by Alice'), findsOneWidget);
    expect(find.text('Shared with you'), findsOneWidget);
    expect(find.text('Shared by Xavier'), findsOneWidget);
  });
}
