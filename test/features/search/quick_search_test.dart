import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:quiz_app/core/router/app_shell.dart';
import 'package:quiz_app/core/widgets/app_card.dart';
import 'package:quiz_app/data/data_providers.dart';
import 'package:quiz_app/data/sync/sync_engine.dart';
import 'package:quiz_app/features/search/presentation/search_screen.dart';
import 'package:quiz_app/features/search/widgets/quick_search.dart';
import 'package:quiz_app/features/search/widgets/search_entry.dart';

import 'support/org_fakes.dart';
import 'support/search_fixtures.dart';

class _Sync implements SyncEngine {
  @override
  SyncStatus get currentStatus => const SyncStatus();

  @override
  Stream<SyncStatus> get status => Stream.value(const SyncStatus());

  @override
  void start() {}

  @override
  Future<void> sync() async {}

  @override
  Future<void> dispose() async {}
}

Future<GoRouter> _pumpShell(
  WidgetTester tester, {
  Size size = const Size(1280, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  Widget label(String text) => Scaffold(body: Text(text));
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      ShellRoute(
        builder: (_, state, child) =>
            AppShell(location: state.matchedLocation, child: child),
        routes: [
          GoRoute(
            path: '/home',
            builder: (_, _) => Scaffold(
              appBar: AppBar(
                title: const Text('Home'),
                actions: const [SearchIconButton()],
              ),
              body: const Text('home page'),
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/search',
        builder: (_, s) =>
            SearchScreen(initialQuery: s.uri.queryParameters['q']),
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
        path: '/subjects/:id',
        builder: (_, s) => label('subject ${s.pathParameters['id']}'),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...searchOverrides(buildSearchIndex(), FakeOrganizationRepository()),
        syncEngineProvider.overrideWithValue(_Sync()),
        dueCountProvider.overrideWith((ref) => Stream.value(0)),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

Future<void> _ctrlK(WidgetTester tester, {bool meta = false}) async {
  final modifier = meta
      ? LogicalKeyboardKey.metaLeft
      : LogicalKeyboardKey.controlLeft;
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
  await tester.sendKeyUpEvent(modifier);
  await tester.pumpAndSettle();
}

List<String> _selected(WidgetTester tester) => [
  for (final t in tester.widgetList<ListRowTile>(
    find.descendant(
      of: find.byType(QuickSearchDialog),
      matching: find.byType(ListRowTile),
    ),
  ))
    if (t.selected) (t.key! as ValueKey<Object>).value.toString(),
];

void main() {
  setUp(() => QuickSearchDialog.isOpen = false);

  testWidgets('Ctrl+K opens the palette; ↓ + Enter opens a result', (
    tester,
  ) async {
    final router = await _pumpShell(tester);
    expect(find.byType(QuickSearchDialog), findsNothing);

    await _ctrlK(tester);
    expect(find.byType(QuickSearchDialog), findsOneWidget);
    // Pressing it again does not stack a second palette.
    await _ctrlK(tester);
    expect(find.byType(QuickSearchDialog), findsOneWidget);

    await tester.enterText(find.byKey(QuickSearchDialog.fieldKey), 'cell');
    await tester.pumpAndSettle();
    // Grouped, at most 3 per type, plus "Show all".
    Finder inPalette(String text) => find.descendant(
      of: find.byType(QuickSearchDialog),
      matching: find.text(text),
    );
    expect(inPalette('Subjects'), findsOneWidget);
    expect(inPalette('Notes'), findsOneWidget);
    expect(find.byKey(QuickSearchDialog.showAllKey), findsOneWidget);
    expect(_selected(tester), ['search-result-subject-s1']);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(_selected(tester), ['search-result-note-n2']);

    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.byType(QuickSearchDialog), findsNothing);
    expect(router.state.uri.path, '/notes/n2');
    expect(find.text('note n2'), findsOneWidget);
  });

  testWidgets('Cmd+K works too; Esc closes', (tester) async {
    await _pumpShell(tester);
    await _ctrlK(tester, meta: true);
    expect(find.byType(QuickSearchDialog), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(QuickSearchDialog), findsNothing);
    expect(QuickSearchDialog.isOpen, isFalse);
  });

  testWidgets('expands to the full search screen', (tester) async {
    final router = await _pumpShell(tester);
    await tester.tap(find.byKey(SidebarSearchButton.buttonKey));
    await tester.pumpAndSettle();
    expect(find.byType(QuickSearchDialog), findsOneWidget);

    await tester.enterText(find.byKey(QuickSearchDialog.fieldKey), 'quiz');
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(find.byType(QuickSearchDialog), findsNothing);
    expect(router.state.uri.toString(), '/search?q=quiz');
    expect(find.byType(SearchScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('search-result-quiz-q1')), findsOne);

    // Ctrl+K on the search screen focuses its field instead.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await _ctrlK(tester);
    expect(find.byType(QuickSearchDialog), findsNothing);
    final field = tester.widget<TextField>(find.byKey(SearchScreen.fieldKey));
    expect(field.focusNode!.hasFocus, isTrue);
  });

  testWidgets('"Show all" row and recent queries in the palette', (
    tester,
  ) async {
    final router = await _pumpShell(tester);
    await _ctrlK(tester);
    expect(
      find.text('Search subjects, notes, quizzes, decks, files and chats.'),
      findsOneWidget,
    );
    await tester.enterText(find.byKey(QuickSearchDialog.fieldKey), 'romans');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(QuickSearchDialog.showAllKey));
    await tester.pumpAndSettle();
    expect(router.state.uri.toString(), '/search?q=romans');

    router.pop();
    await tester.pumpAndSettle();
    await _ctrlK(tester);
    // The query is remembered; Enter on it fills the field.
    expect(find.byKey(const ValueKey('quick-recent-romans')), findsOneWidget);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(QuickSearchDialog.fieldKey))
          .controller!
          .text,
      'romans',
    );
    expect(find.byKey(const ValueKey('search-result-note-n3')), findsOne);
  });

  testWidgets('phone: app-bar search button opens the search screen', (
    tester,
  ) async {
    final router = await _pumpShell(tester, size: const Size(390, 800));
    expect(find.byKey(SidebarSearchButton.buttonKey), findsNothing);
    await tester.tap(find.byKey(SearchIconButton.buttonKey));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/search');
    expect(find.text('Search everything'), findsOneWidget);
  });
}
