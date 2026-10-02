import 'dart:convert';

import 'package:hive_ce/hive_ce.dart';

/// Server-side position in one table's change feed: the raw `updated_at`
/// string returned by Supabase (kept verbatim to preserve microsecond
/// precision on web) plus the row id as tie-breaker for keyset paging.
class PullCursor {
  const PullCursor({required this.updatedAt, required this.id});

  /// Smallest possible id, for cursors that only bound the timestamp.
  static const String minId = '00000000-0000-0000-0000-000000000000';

  final String updatedAt;
  final String id;

  DateTime get updatedAtTime => DateTime.parse(updatedAt);

  Map<String, String> toJson() => {'updated_at': updatedAt, 'id': id};

  static PullCursor? tryParse(String? raw) {
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return PullCursor(
        updatedAt: map['updated_at'] as String,
        id: map['id'] as String,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is PullCursor && other.updatedAt == updatedAt && other.id == id;

  @override
  int get hashCode => Object.hash(updatedAt, id);

  @override
  String toString() => 'PullCursor($updatedAt, $id)';
}

/// Sync bookkeeping in the `sync_meta` box (all user-scoped; cleared on
/// sign-out).
class SyncMetaStore {
  SyncMetaStore(this.box);

  final Box<String> box;

  static const String _userIdKey = 'user_id';
  static const String _lastSyncedAtKey = 'last_synced_at';
  static const String _lastReconciledAtKey = 'last_reconciled_at';
  static const String _incomingSharesKey = 'incoming_shares';

  static String cursorKey(String table) => 'cursor:$table';

  PullCursor? cursor(String table) =>
      PullCursor.tryParse(box.get(cursorKey(table)));

  Future<void> setCursor(String table, PullCursor cursor) =>
      box.put(cursorKey(table), jsonEncode(cursor.toJson()));

  Future<void> resetCursor(String table) => box.delete(cursorKey(table));

  /// User whose data is currently stored locally.
  String? get userId => box.get(_userIdKey);
  Future<void> setUserId(String userId) => box.put(_userIdKey, userId);

  DateTime? get lastSyncedAt => _date(_lastSyncedAtKey);
  Future<void> setLastSyncedAt(DateTime at) =>
      box.put(_lastSyncedAtKey, at.toUtc().toIso8601String());

  DateTime? get lastReconciledAt => _date(_lastReconciledAtKey);
  Future<void> setLastReconciledAt(DateTime at) =>
      box.put(_lastReconciledAtKey, at.toUtc().toIso8601String());

  /// Keys (`{type}:{resourceId}`) of shares received, as of the last sync.
  /// Null before the first share check.
  Set<String>? get incomingShareKeys {
    final raw = box.get(_incomingSharesKey);
    if (raw == null) return null;
    try {
      return (jsonDecode(raw) as List<dynamic>).cast<String>().toSet();
    } catch (_) {
      return null;
    }
  }

  Future<void> setIncomingShareKeys(Set<String> keys) =>
      box.put(_incomingSharesKey, jsonEncode(keys.toList()..sort()));

  Future<void> clear() => box.clear();

  DateTime? _date(String key) {
    final raw = box.get(key);
    return raw == null ? null : DateTime.tryParse(raw);
  }
}
