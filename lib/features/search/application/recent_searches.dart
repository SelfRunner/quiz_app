import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive_ce.dart';

import '../../../data/local/hive_boxes.dart';

/// Recent search queries, newest first (max [RecentSearches.max]), kept in
/// the Hive `prefs` box (key [RecentSearches.prefsKey]; device-scoped).
/// In memory only when the box is not open (tests).
final recentSearchesProvider = NotifierProvider<RecentSearches, List<String>>(
  RecentSearches.new,
);

class RecentSearches extends Notifier<List<String>> {
  static const String prefsKey = 'recent_searches';
  static const int max = 8;

  static Box<String>? get _prefs => Hive.isBoxOpen(HiveBoxes.prefs)
      ? Hive.box<String>(HiveBoxes.prefs)
      : null;

  @override
  List<String> build() {
    try {
      final raw = _prefs?.get(prefsKey);
      if (raw == null) return const [];
      return [
        for (final q in jsonDecode(raw) as List<Object?>)
          if (q is String && q.trim().isNotEmpty) q,
      ].take(max).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Records [query] (trimmed; ignored when shorter than 2 characters).
  void add(String query) {
    final q = query.trim();
    if (q.length < 2) return;
    _set(
      [
        q,
        for (final e in state)
          if (e.toLowerCase() != q.toLowerCase()) e,
      ].take(max).toList(),
    );
  }

  void remove(String query) => _set([
    for (final e in state)
      if (e != query) e,
  ]);

  void clear() => _set(const []);

  void _set(List<String> next) {
    state = next;
    _prefs?.put(prefsKey, jsonEncode(next)).ignore();
  }
}
