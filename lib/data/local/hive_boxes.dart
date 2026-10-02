import 'package:hive_ce_flutter/hive_ce_flutter.dart';

/// Hive CE storage layout.
///
/// Storage format: every entity box is a `Box<String>` keyed by entity id
/// whose values are `jsonEncode(model.toJson())` (the exact Supabase row
/// JSON). No TypeAdapters are used, so model changes never require Hive
/// type-id migrations; decode with `Model.fromJson(jsonDecode(value))`.
///
/// Boxes hold the current user's own rows plus rows shared with them (pulled
/// by sync). The data layer must clear all boxes on sign-out.
abstract final class HiveBoxes {
  static const String subjects = 'subjects';
  static const String notes = 'notes';
  static const String quizzes = 'quizzes';
  static const String quizAttempts = 'quiz_attempts';

  /// `OutboxOp` JSON keyed by op id; process in `createdAt` order.
  static const String outbox = 'outbox';

  /// Sync metadata: pull cursors per table (`cursor:{table}`), last user id,
  /// etc. Values are strings.
  static const String syncMeta = 'sync_meta';

  /// Non-secret app preferences (theme, last selected subject, ...).
  /// API keys are NOT stored here (see `ApiKeyStore`).
  static const String prefs = 'prefs';

  static const List<String> stringBoxes = [
    subjects,
    notes,
    quizzes,
    quizAttempts,
    outbox,
    syncMeta,
    prefs,
  ];

  /// Initializes Hive and opens every box. Called once from bootstrap.
  /// Data-layer agents may extend this (e.g. an image bytes cache box).
  static Future<void> init() async {
    await Hive.initFlutter('quiz_app');
    registerAdapters();
    for (final name in stringBoxes) {
      await Hive.openBox<String>(name);
    }
  }

  /// Hook for TypeAdapter registration. Intentionally empty: all models are
  /// stored as JSON strings.
  static void registerAdapters() {}

  static Box<String> box(String name) => Hive.box<String>(name);

  /// Clears all user data (call on sign-out / account switch).
  static Future<void> clearAll() async {
    for (final name in stringBoxes) {
      await Hive.box<String>(name).clear();
    }
  }
}
