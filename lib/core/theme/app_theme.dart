import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive_ce.dart';

import '../../data/local/hive_boxes.dart';

/// Material 3 light/dark themes generated from a single seed color.
abstract final class AppTheme {
  static const Color seed = Color(0xFF3F51B5);

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
      cardTheme: const CardThemeData(clipBehavior: Clip.antiAlias),
    );
  }
}

/// App theme mode, persisted in the Hive `prefs` box (device-scoped, kept on
/// sign-out). Falls back to in-memory when the box is not open (tests).
final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);

class ThemeModeController extends Notifier<ThemeMode> {
  static const String prefsKey = 'theme_mode';

  static Box<String>? get _prefs => Hive.isBoxOpen(HiveBoxes.prefs)
      ? Hive.box<String>(HiveBoxes.prefs)
      : null;

  @override
  ThemeMode build() =>
      ThemeMode.values.asNameMap()[_prefs?.get(prefsKey)] ?? ThemeMode.system;

  void set(ThemeMode mode) {
    state = mode;
    _prefs?.put(prefsKey, mode.name).ignore();
  }
}
