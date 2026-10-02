import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:quiz_app/data/data_providers.dart';
import 'package:quiz_app/data/local/hive_boxes.dart';
import 'package:quiz_app/features/settings/presentation/settings_screen.dart';
import 'package:quiz_app/study/study_settings.dart';

import '../subjects/support/fakes.dart';

Future<ProviderContainer> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1000, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: TestDeps().overrides,
      child: const MaterialApp(home: SettingsScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(SettingsScreen)));
}

void main() {
  testWidgets('Study section edits new cards, retention and resets', (
    tester,
  ) async {
    final c = await _pump(tester);
    StudySettings settings() => c.read(studySettingsProvider);

    expect(find.text('Study'), findsOneWidget);
    expect(find.text('90%'), findsWidgets);
    expect(find.byKey(const Key('study-reset')), findsOneWidget);
    expect(
      tester.widget<TextButton>(find.byKey(const Key('study-reset'))).onPressed,
      isNull,
    );

    await tester.tap(find.byKey(const Key('study-new-cards-plus')));
    await tester.pump();
    expect(settings().newCardsPerDay, 25);

    await tester.enterText(find.byKey(const Key('study-new-cards')), '40');
    await tester.pump();
    expect(settings().newCardsPerDay, 40);

    // Retention slider: 0.80..0.95.
    final slider = tester.widget<Slider>(
      find.byKey(const Key('study-retention')),
    );
    expect(slider.min, 0.80);
    expect(slider.max, 0.95);
    await tester.drag(
      find.byKey(const Key('study-retention')),
      const Offset(-2000, 0),
    );
    await tester.pumpAndSettle();
    expect(settings().desiredRetention, 0.80);
    expect(
      tester.widget<Text>(find.byKey(const Key('study-retention-value'))).data,
      '80%',
    );

    await tester.tap(find.byKey(const Key('study-reset')));
    await tester.pumpAndSettle();
    expect(settings(), const StudySettings());
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('study-new-cards')))
          .controller!
          .text,
      '20',
    );
  });

  group('persistence', () {
    late Directory dir;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('study_settings_test_');
      Hive.init(dir.path);
      await Hive.openBox<String>(HiveBoxes.prefs);
    });

    tearDown(() async {
      await Hive.close();
      dir.deleteSync(recursive: true);
    });

    test('settings are stored in the prefs box and read back', () async {
      final first = ProviderContainer();
      first.read(studySettingsProvider.notifier)
        ..setNewCardsPerDay(35)
        ..setDesiredRetention(0.85);
      first.dispose();

      final raw = Hive.box<String>(HiveBoxes.prefs).get(StudySettings.prefsKey);
      expect(StudySettings.decode(raw).newCardsPerDay, 35);

      final second = ProviderContainer();
      addTearDown(second.dispose);
      final restored = second.read(studySettingsProvider);
      expect(restored.newCardsPerDay, 35);
      expect(restored.desiredRetention, 0.85);

      second.read(studySettingsProvider.notifier).set(const StudySettings());
      expect(
        StudySettings.decode(
          Hive.box<String>(HiveBoxes.prefs).get(StudySettings.prefsKey),
        ),
        const StudySettings(),
      );
    });
  });
}
