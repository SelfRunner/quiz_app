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

/// A local change the server rejected permanently (an outbox op that was
/// dropped). Every dropped op is recorded, including Storage ops; for row
/// upserts the rejected row JSON is kept so the user's content is not lost
/// when the server version is restored locally.
class RejectedChange {
  const RejectedChange({
    required this.id,
    required this.table,
    required this.rowId,
    required this.payload,
    required this.message,
    required this.at,
    this.op = 'upsert',
  });

  /// Id of the dropped outbox op.
  final String id;

  /// Table, or Storage bucket for file ops.
  final String table;

  /// Row id, or object path for file ops.
  final String rowId;

  /// `OutboxOpType` wire name of the dropped op (`upsert`, `upload_image`,
  /// ...). Entries written by older builds are upserts.
  final String op;

  /// The row the user tried to save (snake_case JSON), if any.
  final Map<String, dynamic>? payload;

  /// User-safe reason.
  final String message;
  final DateTime at;

  Map<String, dynamic> toJson() => {
    'id': id,
    'table': table,
    'row_id': rowId,
    'op': op,
    'payload': payload,
    'message': message,
    'at': at.toUtc().toIso8601String(),
  };

  static RejectedChange? tryParse(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    try {
      return RejectedChange(
        id: json['id'] as String,
        table: json['table'] as String,
        rowId: json['row_id'] as String,
        op: json['op'] as String? ?? 'upsert',
        payload: json['payload'] as Map<String, dynamic>?,
        message: json['message'] as String,
        at: DateTime.parse(json['at'] as String),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Last fetched "shared with me" list (offline fallback).
typedef SharedWithMeSnapshot = ({
  String userId,
  DateTime fetchedAt,
  List<Map<String, dynamic>> rows,
});

/// Sync bookkeeping in the `sync_meta` box (all user-scoped; cleared on
/// sign-out).
class SyncMetaStore {
  SyncMetaStore(this.box);

  final Box<String> box;

  static const String _userIdKey = 'user_id';
  static const String _lastSyncedAtKey = 'last_synced_at';
  static const String _lastReconciledAtKey = 'last_reconciled_at';
  static const String _incomingSharesKey = 'incoming_shares';
  static const String _sharedWithMeKey = 'shared_with_me';
  static const String _rejectedKey = 'rejected_changes';

  /// Beyond this many rejected changes the oldest are discarded, derived
  /// study rows (`card_reviews`, `mistakes`) first.
  static const int maxRejectedChanges = 100;

  static const Set<String> _lowValueTables = {'card_reviews', 'mistakes'};

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

  /// Makes the next sync reconcile (e.g. after an incomplete pass).
  Future<void> resetLastReconciledAt() => box.delete(_lastReconciledAtKey);

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

  /// Last "shared with me" list fetched online (rows as `Share` JSON plus
  /// the `owner` profile and `resource_title`), or null.
  SharedWithMeSnapshot? get sharedWithMe {
    final raw = box.get(_sharedWithMeKey);
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return (
        userId: map['user_id'] as String,
        fetchedAt: DateTime.parse(map['fetched_at'] as String),
        rows: (map['rows'] as List<dynamic>).cast<Map<String, dynamic>>(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> setSharedWithMe(SharedWithMeSnapshot snapshot) => box.put(
    _sharedWithMeKey,
    jsonEncode({
      'user_id': snapshot.userId,
      'fetched_at': snapshot.fetchedAt.toUtc().toIso8601String(),
      'rows': snapshot.rows,
    }),
  );

  /// Rejected changes, oldest first.
  List<RejectedChange> get rejectedChanges {
    final raw = box.get(_rejectedKey);
    if (raw == null) return const [];
    try {
      return [
        for (final item in jsonDecode(raw) as List<dynamic>)
          ?RejectedChange.tryParse(item),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> addRejectedChange(RejectedChange change) {
    final all = [...rejectedChanges, change];
    while (all.length > maxRejectedChanges) {
      final lowValue = all.indexWhere((c) => _lowValueTables.contains(c.table));
      all.removeAt(lowValue >= 0 ? lowValue : 0);
    }
    return _putRejected(all);
  }

  Future<void> removeRejectedChange(String id) =>
      _putRejected([...rejectedChanges.where((c) => c.id != id)]);

  Future<void> _putRejected(List<RejectedChange> changes) => changes.isEmpty
      ? box.delete(_rejectedKey)
      : box.put(
          _rejectedKey,
          jsonEncode([for (final c in changes) c.toJson()]),
        );

  /// Ids of chat messages saved locally only (streaming drafts, not queued
  /// for push yet).
  Set<String> get chatDraftIds {
    final raw = box.get(_chatDraftsKey);
    if (raw == null) return <String>{};
    try {
      return (jsonDecode(raw) as List<dynamic>).cast<String>().toSet();
    } catch (_) {
      return <String>{};
    }
  }

  Future<void> setChatDraftIds(Set<String> ids) => ids.isEmpty
      ? box.delete(_chatDraftsKey)
      : box.put(_chatDraftsKey, jsonEncode(ids.toList()..sort()));

  static const String _chatDraftsKey = 'chat_drafts';

  Future<void> clear() => box.clear();

  DateTime? _date(String key) {
    final raw = box.get(key);
    return raw == null ? null : DateTime.tryParse(raw);
  }
}
