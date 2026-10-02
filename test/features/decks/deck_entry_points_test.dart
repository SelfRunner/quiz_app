import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:quiz_app/data/data_providers.dart';
import 'package:quiz_app/features/notes/presentation/note_view_screen.dart';
import 'package:quiz_app/features/subjects/presentation/subject_detail_screen.dart';

import '../subjects/support/fakes.dart';
import 'support/deck_fakes.dart';

Widget _app(TestDeps deps, FakeDeckRepository decks, String initial) {
  final router = GoRouter(
    initialLocation: initial,
    routes: [
      GoRoute(
        path: '/subjects/:id',
        builder: (_, s) =>
            SubjectDetailScreen(subjectId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/notes/:id',
        builder: (_, s) => NoteViewScreen(noteId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/decks/:id',
        builder: (_, s) => Text('deck ${s.pathParameters['id']}'),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      ...deps.overrides,
      deckRepositoryProvider.overrideWithValue(decks),
      reviewRepositoryProvider.overrideWithValue(FakeReviewRepository(decks)),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  testWidgets('subject tabs: Notes | Quizzes | Decks | Files', (tester) async {
    final deps = TestDeps();
    deps.subjects.seed(id: 's1', title: 'Biology');
    final decks = FakeDeckRepository()
      ..put(deck('d1', [card('c1', 'Q', 'A')], title: 'Cells', owner: kUserId));
    await tester.pumpWidget(_app(deps, decks, '/subjects/s1'));
    await tester.pumpAndSettle();

    final tabs = tester.widget<TabBar>(find.byType(TabBar)).tabs;
    expect(
      [for (final t in tabs) (t as Tab).text],
      ['Notes', 'Quizzes', 'Decks', 'Files'],
    );
    await tester.tap(find.text('Decks'));
    await tester.pumpAndSettle();
    expect(find.text('Flashcards  1', findRichText: true), findsOneWidget);
    expect(find.text('Cells'), findsOneWidget);
    expect(find.byKey(const Key('deck-new')), findsOneWidget);

    await tester.tap(find.text('Cells'));
    await tester.pumpAndSettle();
    expect(find.text('deck d1'), findsOneWidget);
  });

  testWidgets('note view lists the note decks', (tester) async {
    final deps = TestDeps();
    deps.subjects.seed(id: 's1', title: 'Biology');
    deps.notes.seed(id: 'n1', title: 'Organelles', contentMd: 'Text');
    final decks = FakeDeckRepository()
      ..put(
        deck(
          'd1',
          [card('c1', 'Q', 'A')],
          title: 'Organelle cards',
          noteId: 'n1',
          owner: kUserId,
        ),
      );
    await tester.pumpWidget(_app(deps, decks, '/notes/n1'));
    await tester.pumpAndSettle();
    final sections = find.byKey(const Key('note-study-sections'));
    expect(
      find.descendant(of: sections, matching: find.text('Organelle cards')),
      findsOneWidget,
    );
  });
}
