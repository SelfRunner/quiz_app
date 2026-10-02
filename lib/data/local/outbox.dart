import 'dart:async';
import 'dart:convert';

import 'package:hive_ce/hive_ce.dart';

import '../../core/utils/clock.dart';
import '../models/outbox_op.dart';

/// Persistent FIFO queue of local writes waiting to be pushed.
///
/// - Ordering: ops are processed by `createdAt`; [enqueue] makes `createdAt`
///   strictly increasing (even with a frozen/skewed clock), so the order is
///   total and stable.
/// - Coalescing: a new upsert for a row that already has a pending upsert
///   replaces that op's payload **in place** (keeps its queue position, so a
///   row is still created before anything enqueued after it that depends on
///   it). Its retry state is reset.
/// - Concurrency: the sync engine removes an op with [complete], which only
///   removes it if it was not coalesced while being pushed; otherwise the
///   newer payload stays queued and is pushed on the next pass.
class Outbox {
  Outbox(this.box, {required this._clock, required this._newId});

  final Box<String> box;
  final Clock _clock;
  final IdGenerator _newId;
  final StreamController<OutboxOp> _enqueued =
      StreamController<OutboxOp>.broadcast();
  DateTime? _lastCreatedAt;

  /// Fires after every [enqueue] (used by sync for local-write triggers).
  Stream<OutboxOp> get onEnqueued => _enqueued.stream;

  int get length => box.length;

  /// Emits the number of pending ops on listen and on every change.
  Stream<int> watchCount() async* {
    yield box.length;
    yield* box.watch().map((_) => box.length);
  }

  /// Pending ops in processing order.
  List<OutboxOp> pending() {
    final ops = <OutboxOp>[];
    for (final key in box.keys) {
      final op = _read(key as String);
      if (op != null) ops.add(op);
    }
    ops.sort(_compare);
    return ops;
  }

  /// Whether any op for [table]/[rowId] is waiting.
  bool hasPendingFor(String table, String rowId) =>
      _findFor(table, rowId) != null;

  OutboxOp? pendingFor(String table, String rowId, {OutboxOpType? op}) =>
      _findFor(table, rowId, op: op);

  /// Queues an upsert of a full row (soft deletes are upserts with
  /// `deleted_at` set). Coalesces with a pending upsert of the same row.
  Future<OutboxOp> enqueueUpsert(
    String table,
    String rowId,
    Map<String, dynamic> payload,
  ) => enqueue(
    table: table,
    op: OutboxOpType.upsert,
    rowId: rowId,
    payload: payload,
  );

  Future<OutboxOp> enqueue({
    required String table,
    required OutboxOpType op,
    required String rowId,
    Map<String, dynamic>? payload,
  }) async {
    if (op == OutboxOpType.upsert) {
      final existing = _findFor(table, rowId, op: OutboxOpType.upsert);
      if (existing != null) {
        final merged = existing.copyWith(
          payload: payload,
          attempts: 0,
          lastError: null,
        );
        await _write(merged);
        _enqueued.add(merged);
        return merged;
      }
    }
    final created = OutboxOp(
      id: _newId(),
      table: table,
      op: op,
      rowId: rowId,
      payload: payload,
      createdAt: _nextCreatedAt(),
    );
    await _write(created);
    _enqueued.add(created);
    return created;
  }

  /// Removes [op] after a successful push, unless it was coalesced with newer
  /// data in the meantime. Returns whether it was removed.
  Future<bool> complete(OutboxOp op) async {
    final current = _read(op.id);
    if (current == null) return true;
    if (current != op) return false;
    await box.delete(op.id);
    return true;
  }

  /// Records a failed attempt (unless the op changed meanwhile). Returns the
  /// stored op.
  Future<OutboxOp> recordFailure(OutboxOp op, String error) async {
    final current = _read(op.id);
    if (current == null || current != op) return current ?? op;
    final updated = op.copyWith(attempts: op.attempts + 1, lastError: error);
    await _write(updated);
    return updated;
  }

  /// Unconditionally removes an op (permanent failure / obsolete).
  Future<void> drop(String opId) => box.delete(opId);

  /// Removes every pending op of [type] for [table]/[rowId].
  Future<void> removeFor(String table, String rowId, OutboxOpType type) async {
    final ids = [
      for (final op in pending())
        if (op.table == table && op.rowId == rowId && op.op == type) op.id,
    ];
    await box.deleteAll(ids);
  }

  Future<void> clear() async {
    _lastCreatedAt = null;
    await box.clear();
  }

  OutboxOp? _findFor(String table, String rowId, {OutboxOpType? op}) {
    for (final candidate in pending()) {
      if (candidate.table == table &&
          candidate.rowId == rowId &&
          (op == null || candidate.op == op)) {
        return candidate;
      }
    }
    return null;
  }

  DateTime _nextCreatedAt() {
    var last = _lastCreatedAt;
    if (last == null) {
      for (final op in pending()) {
        if (last == null || op.createdAt.isAfter(last)) last = op.createdAt;
      }
    }
    var now = _clock();
    if (last != null && !now.isAfter(last)) {
      now = last.add(const Duration(milliseconds: 1));
    }
    _lastCreatedAt = now;
    return now;
  }

  Future<void> _write(OutboxOp op) => box.put(op.id, jsonEncode(op.toJson()));

  OutboxOp? _read(String id) {
    final raw = box.get(id);
    if (raw == null) return null;
    try {
      return OutboxOp.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static int _compare(OutboxOp a, OutboxOp b) {
    final byTime = a.createdAt.compareTo(b.createdAt);
    return byTime != 0 ? byTime : a.id.compareTo(b.id);
  }

  Future<void> dispose() => _enqueued.close();
}
