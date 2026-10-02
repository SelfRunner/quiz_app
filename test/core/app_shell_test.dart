import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/core/router/app_shell.dart';
import 'package:quiz_app/core/theme/app_theme.dart';
import 'package:quiz_app/core/widgets/sync_status_indicator.dart';
import 'package:quiz_app/data/data_providers.dart';
import 'package:quiz_app/data/sync/sync_engine.dart';

class FakeShellSyncEngine implements SyncEngine {
  FakeShellSyncEngine(this.currentStatus);

  @override
  final SyncStatus currentStatus;
  int syncCalls = 0;

  @override
  Stream<SyncStatus> get status => Stream.value(currentStatus);

  @override
  void start() {}

  @override
  Future<void> sync() async => syncCalls++;

  @override
  Future<void> dispose() async {}
}

Future<FakeShellSyncEngine> pumpShell(
  WidgetTester tester, {
  required Size size,
  SyncStatus status = const SyncStatus(),
  ThemeMode mode = ThemeMode.light,
  int due = 0,
  String location = '/shared',
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final engine = FakeShellSyncEngine(status);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        syncEngineProvider.overrideWithValue(engine),
        dueCountProvider.overrideWith((ref) => Stream.value(due)),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: mode,
        home: AppShell(location: location, child: const Text('content')),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return engine;
}

void main() {
  testWidgets('expanded width: extended sidebar with name and sync row', (
    tester,
  ) async {
    final engine = await pumpShell(tester, size: const Size(1280, 800));
    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail.extended, isTrue);
    expect(rail.selectedIndex, 3); // Home, Subjects, Study, Shared, Settings
    expect(rail.destinations, hasLength(5));
    expect(find.text(AppShell.appName), findsOneWidget);
    expect(find.byType(SyncStatusTile), findsOneWidget);
    expect(find.text('Not synced yet'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
    expect(find.text('content'), findsOneWidget);

    await tester.tap(find.text('Not synced yet'));
    await tester.pumpAndSettle();
    expect(find.text('Sync now'), findsOneWidget);
    await tester.tap(find.text('Sync now'));
    expect(engine.syncCalls, 1);
  });

  testWidgets('medium width: compact rail with sync button', (tester) async {
    await pumpShell(tester, size: const Size(800, 700), mode: ThemeMode.dark);
    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail.extended, isFalse);
    expect(find.byType(SyncStatusButton), findsOneWidget);
    expect(find.byTooltip('Sign out'), findsOneWidget);
    expect(find.text('Subjects'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('phone width: bottom bar and offline banner', (tester) async {
    await pumpShell(
      tester,
      size: const Size(390, 800),
      status: const SyncStatus(state: SyncState.offline, pendingOps: 2),
    );
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byType(SyncStatusBanner), findsOneWidget);
    expect(find.textContaining('Offline'), findsOneWidget);
  });

  testWidgets('destinations map locations to tabs', (tester) async {
    expect(AppShell.indexFor('/home'), 0);
    expect(AppShell.indexFor('/'), 1);
    expect(AppShell.indexFor('/study'), 2);
    expect(AppShell.indexFor('/shared'), 3);
    expect(AppShell.indexFor('/settings'), 4);
    await pumpShell(tester, size: const Size(390, 800), location: '/home');
    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.destinations, hasLength(5));
    expect(bar.selectedIndex, 0);
    for (final label in ['Home', 'Subjects', 'Study', 'Shared', 'Settings']) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('Study shows a badge with the due count', (tester) async {
    await pumpShell(tester, size: const Size(390, 800), due: 7);
    expect(find.byKey(AppShell.studyBadgeKey), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(AppShell.studyBadgeKey),
        matching: find.text('7'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('sidebar badge caps at 99+', (tester) async {
    await pumpShell(tester, size: const Size(1280, 800), due: 120);
    expect(find.text('99+'), findsOneWidget);
  });

  testWidgets('no badge when nothing is due', (tester) async {
    await pumpShell(tester, size: const Size(1280, 800));
    expect(find.byKey(AppShell.studyBadgeKey), findsNothing);
  });

  testWidgets('sync button has one short semantics label', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpShell(tester, size: const Size(800, 700));
    expect(find.bySemanticsLabel('Sync status: Not synced'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Tap for details')), findsNothing);
    semantics.dispose();
  });
}
