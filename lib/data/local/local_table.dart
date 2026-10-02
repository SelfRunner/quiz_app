import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive_ce.dart';

import '../models/syncable.dart';

/// Typed view over one entity box (`Box<String>` of row JSON keyed by id).
///
/// Reads include tombstones unless stated otherwise; `watch*` streams always
/// exclude soft-deleted rows. Decoded models are memoized per raw string, so
/// re-evaluating queries on every box change is cheap.
class LocalTable<T extends Syncable> {
  LocalTable({required this.name, required this.box, required this._fromJson});

  /// Supabase table name (`SyncTables.*`), also the box name.
  final String name;
  final Box<String> box;
  final T Function(Map<String, dynamic>) _fromJson;
  final Map<String, ({String raw, T value})> _memo = {};

  /// Decodes a stored/pulled row. Throws [FormatException] or a cast error
  /// when the JSON does not match the model.
  T decode(Map<String, dynamic> json) => _fromJson(json);

  /// Normalized JSON string as stored in Hive.
  static String encode(Syncable row) => jsonEncode(row.toJson());

  String? raw(String id) => box.get(id);

  /// Row by id, including tombstones. Null when missing or undecodable.
  T? get(String id) {
    final raw = box.get(id);
    if (raw == null) return null;
    return _decodeRaw(id, raw);
  }

  /// Row by id, excluding tombstones.
  T? getLive(String id) {
    final row = get(id);
    return row == null || row.isDeleted ? null : row;
  }

  /// Every decodable row, including tombstones.
  List<T> all() {
    final result = <T>[];
    for (final key in box.keys) {
      final id = key as String;
      final raw = box.get(id);
      if (raw == null) continue;
      final row = _decodeRaw(id, raw);
      if (row != null) result.add(row);
    }
    return result;
  }

  /// Rows matching [test]; tombstones excluded unless [includeDeleted].
  List<T> where(
    bool Function(T row) test, {
    bool includeDeleted = false,
    Comparator<T>? compare,
  }) {
    final rows = all()
        .where((r) => (includeDeleted || !r.isDeleted) && test(r))
        .toList();
    if (compare != null) rows.sort(compare);
    return rows;
  }

  Future<void> put(T row) => box.put(row.id, encode(row));

  Future<void> putAll(Iterable<T> rows) =>
      box.putAll({for (final r in rows) r.id: encode(r)});

  /// Hard-removes rows locally (used for purging rows the user lost access
  /// to; never pushed).
  Future<void> remove(String id) => box.delete(id);

  Future<void> removeAll(Iterable<String> ids) => box.deleteAll(ids);

  Future<void> clear() async {
    _memo.clear();
    await box.clear();
  }

  /// Emits the matching live rows on listen and whenever the box changes
  /// (bursts of changes are coalesced; identical results are not re-emitted).
  Stream<List<T>> watchWhere(
    bool Function(T row) test, {
    Comparator<T>? compare,
  }) =>
      _watch<List<T>>(() => where(test, compare: compare), equals: listEquals);

  /// Emits the live row with [id] (null when missing or deleted).
  Stream<T?> watchById(String id) =>
      _watch<T?>(() => getLive(id), equals: (a, b) => a == b);

  Stream<R> _watch<R>(
    R Function() query, {
    required bool Function(R a, R b) equals,
  }) {
    late final StreamController<R> controller;
    StreamSubscription<BoxEvent>? sub;
    Timer? pending;
    var hasLast = false;
    late R last;

    void emit() {
      pending = null;
      if (controller.isClosed) return;
      final R next;
      try {
        next = query();
      } catch (e, st) {
        controller.addError(e, st);
        return;
      }
      if (hasLast && equals(last, next)) return;
      hasLast = true;
      last = next;
      controller.add(next);
    }

    controller = StreamController<R>(
      onListen: () {
        emit();
        sub = box.watch().listen((_) {
          pending ??= Timer(Duration.zero, emit);
        });
      },
      onCancel: () async {
        pending?.cancel();
        await sub?.cancel();
      },
    );
    return controller.stream;
  }

  T? _decodeRaw(String id, String raw) {
    final memo = _memo[id];
    if (memo != null && (identical(memo.raw, raw) || memo.raw == raw)) {
      return memo.value;
    }
    try {
      final value = _fromJson(jsonDecode(raw) as Map<String, dynamic>);
      _memo[id] = (raw: raw, value: value);
      return value;
    } catch (_) {
      // Corrupt / incompatible row: ignore rather than break every query.
      return null;
    }
  }
}
