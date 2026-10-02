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
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final engine = FakeShellSyncEngine(status);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [syncEngineProvider.overrideWithValue(engine)],
      child: MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: mode,
        home: const AppShell(location: '/shared', child: Text('content')),
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
    expect(rail.selectedIndex, 1);
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
}
