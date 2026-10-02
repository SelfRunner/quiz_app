import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:quiz_app/core/router/routes.dart';
import 'package:quiz_app/core/widgets/app_card.dart';
import 'package:quiz_app/data/repositories/organization_repository.dart';
import 'package:quiz_app/features/search/application/recent_searches.dart';
import 'package:quiz_app/features/search/application/search_logic.dart';
import 'package:quiz_app/features/search/presentation/search_screen.dart';
import 'package:quiz_app/search/search_models.dart';

import 'support/org_fakes.dart';
import 'support/search_fixtures.dart';

Future<GoRouter> _pump(
  WidgetTester tester, {
  String initial = '/search',
  FakeOrganizationRepository? org,
}) async {
  tester.view.physicalSize = const Size(1200, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  Widget label(String text) => Scaffold(body: Text(text));
  final router = GoRouter(
    initialLocation: initial,
    routes: [
      GoRoute(
        path: '/search',
        builder: (_, s) =>
            SearchScreen(initialQuery: s.uri.queryParameters['q']),
      ),
      GoRoute(
        path: '/subjects/:id',
        builder: (_, s) => label('subject ${s.pathParameters['id']}'),
      ),
      GoRoute(
        path: '/notes/:id',
        builder: (_, s) => label('note ${s.pathParameters['id']}'),
      ),
      GoRoute(
        path: '/quizzes/:id',
        builder: (_, s) => label('quiz ${s.pathParameters['id']}'),
      ),
      GoRoute(
        path: '/decks/:id',
        builder: (_, s) => label('deck ${s.pathParameters['id']}'),
      ),
      GoRoute(
        path: '/chats/:id',
        builder: (_, s) => label('chat ${s.pathParameters['id']}'),
      ),
    ],
  );
  addTearDown(router.dispose);
  final fakeOrg = org ?? FakeOrganizationRepository();
  await tester.pumpWidget(
    ProviderScope(
      overrides: searchOverrides(buildSearchIndex(), fakeOrg),
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(SearchScreen)));

List<String> _selectedTitles(WidgetTester tester) => [
  for (final t in tester.widgetList<ListRowTile>(find.byType(ListRowTile)))
    if (t.selected) (t.key! as ValueKey<String>).value,
];

void main() {
  group('search logic', () {
    SearchResult result(SearchItemType type, String id) =>
        SearchResult(document: doc(type, id, id), score: 1);

    test('groups by type in display order, keeps rank, caps per group', () {
      final groups = groupSearchResults([
        result(SearchItemType.chat, 'c1'),
        result(SearchItemType.note, 'n1'),
        result(SearchItemType.subject, 's1'),
        result(SearchItemType.note, 'n2'),
        result(SearchItemType.note, 'n3'),
        result(SearchItemType.attachment, 'a1'),
      ], perGroup: 2);
      expect(groups.map((g) => g.type), [
        SearchItemType.subject,
        SearchItemType.note,
        SearchItemType.attachment,
        SearchItemType.chat,
      ]);
      final notes = groups[1];
      expect(notes.results.map((r) => r.id), ['n1', 'n2']);
      expect(notes.total, 3);
      expect(flattenGroups(groups).map((r) => r.id), [
        's1',
        'n1',
        'n2',
        'a1',
        'c1',
      ]);
    });

    test('highlightedSpan clamps and merges ranges', () {
      const hl = TextStyle(fontWeight: FontWeight.w600);
      final span = highlightedSpan('Cell biology', const [
        HighlightRange(5, 8),
        HighlightRange(0, 4),
        HighlightRange(6, 99),
      ], highlight: hl);
      expect(span.toPlainText(), 'Cell biology');
      expect(boldParts(span), ['Cell', 'biology']);
      expect(
        highlightedSpan('abc', const [], highlight: hl).toPlainText(),
        'abc',
      );
    });

    test('parseSearchInput extracts tag tokens', () {
      final p = parseSearchInput('cells tag:Exam tag:"exam prep"  mito');
      expect(p.text, 'cells mito');
      expect(p.tags, {'exam', 'exam prep'});
      expect(parseSearchInput('plain').tags, isEmpty);
    });

    test('routes per result type (files open their subject)', () {
      expect(
        searchResultRoute(result(SearchItemType.note, 'n1')),
        AppRoutes.note('n1'),
      );
      expect(
        searchResultRoute(result(SearchItemType.attachment, 'a1')),
        AppRoutes.subject('s1'),
      );
      expect(
        searchResultRoute(result(SearchItemType.chat, 'c1')),
        AppRoutes.chat('c1'),
      );
      expect(
        searchResultRoute(result(SearchItemType.deck, 'd1')),
        AppRoutes.deck('d1'),
      );
    });
  });

  group('SearchScreen', () {
    testWidgets('idle state, then instant results grouped by type', (
      tester,
    ) async {
      await _pump(tester);
      expect(find.text('Search everything'), findsOneWidget);

      await tester.enterText(find.byKey(SearchScreen.fieldKey), 'cell');
      await tester.pumpAndSettle();

      final order = [
        for (final t in searchTypeOrder)
          tester.getTopLeft(find.byKey(ValueKey('search-group-${t.name}'))).dy,
      ];
      expect(order, [...order]..sort());
      expect(find.text('Notes'), findsWidgets);
      expect(find.text('Files'), findsWidgets);
      expect(find.byKey(const ValueKey('search-result-note-n1')), findsOne);
      // Archived subject's note does not match "cell".
      expect(find.byKey(const ValueKey('search-result-note-n3')), findsNothing);

      // Matches are highlighted in titles and snippets.
      final title = tester.widget<RichText>(richTextWith('Cell biology'));
      expect(boldParts(title.text), ['Cell']);
      final snippet = tester.widget<RichText>(
        find.descendant(
          of: find.byKey(const ValueKey('search-result-note-n1')),
          matching: find.byWidgetPredicate(
            (w) => w is RichText && w.text.toPlainText().contains('powerhouse'),
          ),
        ),
      );
      expect(boldParts(snippet.text), contains('cell'));
    });

    testWidgets('↑ / ↓ move the selection, Enter opens it', (tester) async {
      final router = await _pump(tester);
      await tester.enterText(find.byKey(SearchScreen.fieldKey), 'cell');
      await tester.pumpAndSettle();

      // First result (the subject) is selected by default.
      expect(_selectedTitles(tester), ['search-result-subject-s1']);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(_selectedTitles(tester), ['search-result-note-n1']);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      // Wraps around to the last result.
      expect(_selectedTitles(tester), ['search-result-chat-c1']);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(_selectedTitles(tester), ['search-result-note-n1']);

      final container = _container(tester);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(find.text('note n1'), findsOneWidget);
      expect(router.state.uri.path, '/notes/n1');
      expect(container.read(recentSearchesProvider), ['cell']);
    });

    testWidgets('tap opens the right route per type', (tester) async {
      await _pump(tester, initial: '/search?q=cell');
      expect(
        tester
            .widget<TextField>(find.byKey(SearchScreen.fieldKey))
            .controller!
            .text,
        'cell',
      );
      await tester.tap(find.byKey(const ValueKey('search-result-deck-d1')));
      await tester.pumpAndSettle();
      expect(find.text('deck d1'), findsOneWidget);
    });

    testWidgets('type chips filter; no-result state offers clearing', (
      tester,
    ) async {
      await _pump(tester);
      await tester.enterText(find.byKey(SearchScreen.fieldKey), 'cell');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('search-type-quiz')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('search-result-quiz-q1')), findsOne);
      expect(find.byKey(const ValueKey('search-result-note-n1')), findsNothing);

      await tester.enterText(find.byKey(SearchScreen.fieldKey), 'membranes');
      await tester.pumpAndSettle();
      expect(find.text('No results'), findsOneWidget);
      expect(find.textContaining('with these filters'), findsOneWidget);
      await tester.tap(find.text('Clear filters'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('search-result-note-n2')), findsOne);

      await tester.enterText(find.byKey(SearchScreen.fieldKey), 'zzzz');
      await tester.pumpAndSettle();
      expect(find.text('No results'), findsOneWidget);
      expect(find.text('Clear filters'), findsNothing);
    });

    testWidgets('tag: query becomes a tag filter; tag menu toggles', (
      tester,
    ) async {
      final org = FakeOrganizationRepository()
        ..tags.addAll(const [TagCount('exam', 2), TagCount('bio', 1)]);
      await _pump(tester, initial: '/search?q=tag:exam', org: org);
      // Empty text + tag filter -> every item with the tag.
      expect(find.byKey(const ValueKey('search-result-note-n1')), findsOne);
      expect(find.byKey(const ValueKey('search-result-quiz-q1')), findsOne);
      expect(find.byKey(const ValueKey('search-result-deck-d1')), findsNothing);
      expect(find.text('#exam'), findsOneWidget);

      await tester.tap(find.byKey(const Key('search-tag-filter')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(CheckedPopupMenuItem<String>, '#exam'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Search everything'), findsOneWidget);
    });

    testWidgets('subject filter limits results to one subject', (tester) async {
      final org = FakeOrganizationRepository()
        ..seed('s1', 'Biology')
        ..seed('s2', 'History', archived: true);
      await _pump(tester, org: org);
      await tester.enterText(find.byKey(SearchScreen.fieldKey), 'romans');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('search-result-note-n3')), findsOne);
      // Archived subject shown as such.
      expect(find.textContaining('Archived'), findsWidgets);

      await tester.tap(find.byKey(const Key('search-subject-filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Biology').last);
      await tester.pumpAndSettle();
      expect(find.text('No results'), findsOneWidget);
    });

    testWidgets('recent searches are listed and reusable', (tester) async {
      await _pump(tester);
      final container = _container(tester);
      container.read(recentSearchesProvider.notifier)
        ..add('mitochondria')
        ..add('x') // too short: ignored
        ..add('cell');
      await tester.pumpAndSettle();
      expect(container.read(recentSearchesProvider), ['cell', 'mitochondria']);
      expect(find.text('Recent searches'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('recent-search-mitochondria')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('search-result-note-n1')), findsOne);

      await tester.enterText(find.byKey(SearchScreen.fieldKey), '');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('clear-recent-searches')));
      await tester.pumpAndSettle();
      expect(container.read(recentSearchesProvider), isEmpty);
      expect(find.text('Search everything'), findsOneWidget);
    });
  });
}
