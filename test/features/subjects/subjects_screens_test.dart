import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:quiz_app/core/widgets/locked_feature.dart';
import 'package:quiz_app/data/models/models.dart';
import 'package:quiz_app/features/subjects/presentation/subject_detail_screen.dart';
import 'package:quiz_app/features/subjects/presentation/subjects_screen.dart';
import 'package:quiz_app/features/subjects/presentation/widgets/subject_visuals.dart';

import 'support/fakes.dart';

Widget _app(TestDeps deps, {String initial = '/'}) {
  final router = GoRouter(
    initialLocation: initial,
    routes: [
      GoRoute(path: '/', builder: (_, _) => const SubjectsScreen()),
      GoRoute(
        path: '/subjects/:id',
        builder: (_, state) =>
            SubjectDetailScreen(subjectId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/notes/:id/edit',
        builder: (_, state) => Text('edit ${state.pathParameters['id']}'),
      ),
      GoRoute(
        path: '/ai/generate',
        builder: (_, state) => Text('generate ${state.uri}'),
      ),
      GoRoute(path: '/settings', builder: (_, _) => const Text('settings')),
    ],
  );
  return ProviderScope(
    overrides: deps.overrides,
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  testWidgets('empty state -> create subject dialog validates and creates', (
    tester,
  ) async {
    final deps = TestDeps();
    await tester.pumpWidget(_app(deps));
    await tester.pumpAndSettle();
    expect(find.text('No subjects yet'), findsOneWidget);

    await tester.tap(find.byKey(const Key('new-subject-empty')));
    await tester.pumpAndSettle();
    expect(find.text('New subject'), findsOneWidget);

    // Empty title is rejected.
    await tester.tap(find.byKey(const Key('subject-submit')));
    await tester.pump();
    expect(find.text('Enter a title'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('subject-title')), ' Physics ');
    await tester.enterText(
      find.byKey(const Key('subject-description')),
      'Mechanics',
    );
    final color = subjectPalette[2];
    await tester.tap(find.byKey(Key('subject-color-$color')));
    await tester.tap(find.byKey(const Key('subject-submit')));
    await tester.pumpAndSettle();

    expect(deps.subjects.created, hasLength(1));
    final s = deps.subjects.created.single;
    expect(s.title, 'Physics');
    expect(s.description, 'Mechanics');
    expect(s.color, color);
    // Navigated to the new subject.
    expect(find.text('No notes yet'), findsOneWidget);
  });

  testWidgets('grid shows subjects with counts; pull to refresh syncs', (
    tester,
  ) async {
    final deps = TestDeps();
    deps.subjects.seed(id: 's1', title: 'Biology');
    deps.notes.seed(subjectId: 's1');
    deps.notes.seed(subjectId: 's1');
    await tester.pumpWidget(_app(deps));
    await tester.pumpAndSettle();

    expect(find.byType(SubjectCard), findsOneWidget);
    expect(find.text('2 notes'), findsOneWidget);
    expect(find.text('0 quizzes'), findsOneWidget);

    await tester.fling(find.byType(SubjectCard), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();
    expect(deps.sync.syncCalls, greaterThan(0));
  });

  testWidgets('owner sees edit actions; new note opens the editor', (
    tester,
  ) async {
    final deps = TestDeps();
    deps.subjects.seed(id: 's1', title: 'Biology');
    await tester.pumpWidget(_app(deps, initial: '/subjects/s1'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Share'), findsOneWidget);
    expect(find.text('Read-only'), findsNothing);
    await tester.tap(find.byKey(const Key('new-note-fab')));
    await tester.pumpAndSettle();
    expect(find.text('edit n1'), findsOneWidget);
  });

  testWidgets('shared subject is read-only and shows who shared it', (
    tester,
  ) async {
    final deps = TestDeps();
    deps.subjects.seed(id: 's9', title: 'Chemistry', ownerId: 'other');
    deps.shares.add(
      Share(
        id: 'sh1',
        ownerId: 'other',
        recipientId: kUserId,
        resourceType: ShareResourceType.subject,
        resourceId: 's9',
        createdAt: kNow,
        owner: const Profile(id: 'other', displayName: 'Grace'),
      ),
    );
    final router = GoRouter(
      initialLocation: '/subjects/s9',
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
        overrides: deps.overrides,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Read-only'), findsOneWidget);
    expect(find.text('Shared by Grace'), findsOneWidget);
    expect(find.byKey(const Key('new-note-fab')), findsNothing);
    expect(find.byTooltip('Share'), findsNothing);
  });

  testWidgets('list view and name sort', (tester) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final deps = TestDeps();
    deps.subjects.seed(id: 's1', title: 'Zoology');
    deps.subjects.seed(id: 's2', title: 'algebra');
    await deps.subjects.update(
      deps.subjects
          .seed(id: 's3', title: 'Music')
          .copyWith(updatedAt: kNow.add(const Duration(days: 1))),
    );
    await tester.pumpWidget(_app(deps));
    await tester.pumpAndSettle();

    List<String> titles() => tester
        .widgetList<SubjectCard>(find.byType(SubjectCard))
        .map((c) => c.subject.title)
        .toList();
    // Default: most recently updated first.
    expect(titles().first, 'Music');

    await tester.tap(find.byKey(const Key('subjects-sort')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(CheckedPopupMenuItem<SubjectsSort>, 'Name'),
    );
    await tester.pumpAndSettle();
    expect(titles(), ['algebra', 'Music', 'Zoology']);

    await tester.tap(find.byTooltip('List'));
    await tester.pumpAndSettle();
    expect(find.byType(SubjectCard), findsNothing);
    expect(find.byType(SubjectRow), findsNWidgets(3));
  });

  testWidgets('"Generate with AI" is locked until AI is set up', (
    tester,
  ) async {
    final deps = TestDeps();
    deps.subjects.seed(id: 's1', title: 'Biology');
    await tester.pumpWidget(_app(deps, initial: '/subjects/s1'));
    await tester.pumpAndSettle();

    for (final key in const ['generate-with-ai', 'notes-generate-ai']) {
      final gate = find.ancestor(
        of: find.byKey(Key(key)),
        matching: find.byType(LockedFeature),
      );
      expect(
        find.descendant(of: gate, matching: find.byKey(LockedFeature.badgeKey)),
        findsOneWidget,
        reason: key,
      );
    }
    await tester.tap(
      find.ancestor(
        of: find.byKey(const Key('generate-with-ai')),
        matching: find.byType(LockedFeature),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Set up AI'), findsOneWidget);
    expect(find.text('Generate quiz'), findsNothing);
  });

  testWidgets('"Generate with AI" opens the menu when AI is ready', (
    tester,
  ) async {
    final deps = TestDeps()..configureAi();
    deps.subjects.seed(id: 's1', title: 'Biology');
    await tester.pumpWidget(_app(deps, initial: '/subjects/s1'));
    await tester.pumpAndSettle();

    expect(find.byKey(LockedFeature.badgeKey), findsNothing);
    await tester.tap(find.byKey(const Key('generate-with-ai')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Generate note'));
    await tester.pumpAndSettle();
    expect(
      find.text('generate /ai/generate?kind=note&subjectId=s1'),
      findsOneWidget,
    );
  });

  for (final size in const [Size(360, 740), Size(1280, 800)]) {
    testWidgets('subject screens fit at ${size.width.toInt()}px', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final deps = TestDeps();
      deps.subjects.seed(
        id: 's1',
        title: 'Introduction to Molecular Biology and Genetics',
        description: 'A long description ' * 6,
      );
      deps.notes.seed(subjectId: 's1', contentMd: '# Hi\n\nSome text');
      await tester.pumpWidget(_app(deps));
      await tester.pumpAndSettle();
      expect(find.byType(SubjectCard), findsOneWidget);

      await tester.tap(find.byType(SubjectCard));
      await tester.pumpAndSettle();
      expect(find.text('Notes'), findsWidgets);
    });
  }
}
