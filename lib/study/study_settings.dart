import 'dart:convert';
import 'dart:math' as math;

import 'package:meta/meta.dart';

import 'fsrs.dart';

/// Device-level flashcard preferences (Hive `prefs` box, key
/// [StudySettings.prefsKey]; kept on sign-out).
@immutable
class StudySettings {
  const StudySettings({
    this.newCardsPerDay = defaultNewCardsPerDay,
    this.desiredRetention = defaultRetention,
    this.fuzz = true,
  });

  static const String prefsKey = 'study_settings';
  static const int defaultNewCardsPerDay = 20;
  static const double defaultRetention = 0.9;
  static const int maxNewCardsPerDay = 9999;

  /// New (never reviewed) cards introduced per local day, across decks.
  final int newCardsPerDay;

  /// FSRS target recall probability, 0.7..0.99.
  final double desiredRetention;

  /// Spread review intervals slightly (FSRS fuzz).
  final bool fuzz;

  StudySettings copyWith({
    int? newCardsPerDay,
    double? desiredRetention,
    bool? fuzz,
  }) => StudySettings(
    newCardsPerDay: (newCardsPerDay ?? this.newCardsPerDay).clamp(
      0,
      maxNewCardsPerDay,
    ),
    desiredRetention: (desiredRetention ?? this.desiredRetention).clamp(
      0.7,
      0.99,
    ),
    fuzz: fuzz ?? this.fuzz,
  );

  /// The FSRS scheduler for these settings.
  Fsrs scheduler({math.Random? random}) => Fsrs(
    desiredRetention: desiredRetention,
    enableFuzz: fuzz,
    random: random,
  );

  Map<String, Object?> toJson() => {
    'new_cards_per_day': newCardsPerDay,
    'desired_retention': desiredRetention,
    'fuzz': fuzz,
  };

  String encode() => jsonEncode(toJson());

  /// Parses stored settings; invalid or missing values fall back to the
  /// defaults.
  static StudySettings decode(String? raw) {
    if (raw == null) return const StudySettings();
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, Object?>) return const StudySettings();
      final n = json['new_cards_per_day'];
      final r = json['desired_retention'];
      final f = json['fuzz'];
      return const StudySettings().copyWith(
        newCardsPerDay: n is int ? n : null,
        desiredRetention: r is num ? r.toDouble() : null,
        fuzz: f is bool ? f : null,
      );
    } catch (_) {
      return const StudySettings();
    }
  }

  @override
  bool operator ==(Object other) =>
      other is StudySettings &&
      other.newCardsPerDay == newCardsPerDay &&
      other.desiredRetention == desiredRetention &&
      other.fuzz == fuzz;

  @override
  int get hashCode => Object.hash(newCardsPerDay, desiredRetention, fuzz);
}
