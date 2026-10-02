import 'dart:async';
import 'dart:math' as math;

import '../../core/utils/clock.dart';
import '../local/local_database.dart';
import '../local/local_table.dart';
import '../local/sync_meta_store.dart';
import '../models/models.dart';
import '../remote/remote_data_source.dart';
import 'connectivity_monitor.dart';
import 'note_image_copy_processor.dart';
import 'sync_engine.dart';

/// A change the server rejected permanently (dropped from the outbox).
class SyncRejection {
  const SyncRejection({
    required this.op,
    required this.message,
    required this.at,
  });

  final OutboxOp op;
  final String message;
  final DateTime at;
}

/// Offline-first sync: push the outbox, then pull every table.
///
/// **Push** (FIFO by `OutboxOp.createdAt`):
/// - success: op removed (unless it was coalesced with newer data meanwhile);
///   the returned server row is written back when no newer op is pending.
/// - network error: stop, state `offline`, retry with backoff / on
///   connectivity regained. Nothing is dropped.
/// - auth error: stop, state `error` (session expired).
/// - FK violation (parent not pushed yet): op deferred to the end of the pass;
///   up to 3 passes per sync.
/// - permanent error (RLS 42501, constraint, 4xx): op dropped, the server
///   version of the row (if visible) replaces the local one, the rejection is
///   reported via [rejections] and `SyncStatus.error`. The queue never blocks.
/// - transient error (5xx, unknown): `attempts++`; dropped as permanent after
///   [maxAttempts]; retried with exponential backoff.
///
/// **Pull**: per table, keyset pages of `(updated_at, id) > cursor` ordered
/// ascending. The cursor is the max server `updated_at` (raw string) seen, so
/// the client clock is never involved; each sync re-reads a short
/// [pullLookback] window to catch rows committed late by long transactions.
/// Merge is last-write-wins: a pulled row replaces the local row unless the
/// outbox still has a pending op for it (the local change is newer and will
/// be pushed). Tombstones of other users' rows are purged locally; own
/// tombstones are kept.
///
/// **Shares** (see docs/CONTRACTS.md "Data layer notes"): after the pull the
/// engine lists shares received by the user. New shares trigger a targeted
/// backfill of the shared tree (rows older than the cursor would otherwise
/// never be pulled). Revoked shares (and every [reconcileInterval]) trigger a
/// reconciliation: ids of locally cached rows owned by others are checked
/// against the server and rows that are no longer visible are purged.
class DefaultSyncEngine implements SyncEngine {
  DefaultSyncEngine({
    required this.db,
    required this.remote,
    required this.imageRemote,
    required this._currentUserId,
    this._userChanges,
    this._connectivity = const AlwaysOnlineMonitor(),
    this._foregroundChanges,
    this._clock = systemClock,
    this.pageSize = 500,
    this.periodicInterval = const Duration(minutes: 5),
    this.localWriteDebounce = const Duration(seconds: 2),
    this.reconcileInterval = const Duration(minutes: 30),
    this.pullLookback = const Duration(seconds: 5),
    this.maxAttempts = 8,
    this.maxRetryDelay = const Duration(minutes: 5),
  }) : imageCopies = NoteImageCopyProcessor(imageRemote, db.images) {
    _status = SyncStatus(
      lastSyncedAt: db.meta.lastSyncedAt,
      pendingOps: db.outbox.length,
    );
  }

  final LocalDatabase db;
  final SyncRemoteDataSource remote;
  final ImageRemoteDataSource imageRemote;

  /// Storage copies queued by `copy_*` RPCs (run on every sync).
  final NoteImageCopyProcessor imageCopies;
  final String? Function() _currentUserId;
  final Stream<String?>? _userChanges;
  final ConnectivityMonitor _connectivity;
  final Stream<bool>? _foregroundChanges;
  final Clock _clock;

  final int pageSize;
  final Duration periodicInterval;
  final Duration localWriteDebounce;
  final Duration reconcileInterval;
  final Duration pullLookback;
  final int maxAttempts;
  final Duration maxRetryDelay;

  static const int _idChunk = 100;
  static const int _maxPushPasses = 3;

  final StreamController<SyncStatus> _statusController =
      StreamController<SyncStatus>.broadcast();
  final StreamController<SyncRejection> _rejections =
      StreamController<SyncRejection>.broadcast();
  final List<StreamSubscription<Object?>> _subs = [];
  late SyncStatus _status;

  Future<void>? _current;
  bool _rerun = false;
  bool _started = false;
  bool _disposed = false;
  bool _foreground = true;
  bool _online = true;
  int _generation = 0;
  int _consecutiveFailures = 0;
  bool _hasUserStream = false;
  String? _userId;
  Future<void> _userChain = Future<void>.value();
  Timer? _periodic;
  Timer? _debounce;
  Timer? _retry;

  /// Server rejections (dropped ops), for UI snackbars / diagnostics.
  Stream<SyncRejection> get rejections => _rejections.stream;

  @override
  Stream<SyncStatus> get status => Stream<SyncStatus>.multi((controller) {
    controller.add(_status);
    final sub = _statusController.stream.listen(
      controller.add,
      onDone: controller.close,
    );
    controller.onCancel = sub.cancel;
  });

  @override
  SyncStatus get currentStatus => _status;

  String? get _user => _hasUserStream ? _userId : _currentUserId();

  @override
  void start() {
    if (_started || _disposed) return;
    _started = true;
    _subs
      ..add(
        db.outbox.watchCount().listen((n) {
          if (n != _status.pendingOps) _emit(_status.copyWith(pendingOps: n));
        }),
      )
      ..add(db.outbox.onEnqueued.listen((_) => _scheduleDebounced()))
      ..add(_connectivity.onChanged.listen(_onConnectivity));
    final userChanges = _userChanges;
    if (userChanges != null) {
      _hasUserStream = true;
      _userId = _currentUserId();
      _subs.add(userChanges.listen(_onUser));
      if (_userId != null) _onUser(_userId);
    } else {
      _requestSync();
    }
    final foreground = _foregroundChanges;
    if (foreground != null) _subs.add(foreground.listen(_onForeground));
    _startPeriodic();
  }

  @override
  Future<void> sync() {
    if (_disposed) return Future<void>.value();
    return _current ??= _loop().whenComplete(() => _current = null);
  }

  /// Like [sync], but guarantees a cycle that *starts* after this call (waits
  /// for a running cycle first). Use after server-side changes such as a
  /// copy RPC, whose rows a running cycle may already have missed.
  Future<void> syncFresh() async {
    await _awaitCurrent();
    await sync();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _periodic?.cancel();
    _debounce?.cancel();
    _retry?.cancel();
    for (final sub in _subs) {
      await sub.cancel();
    }
    _subs.clear();
    await _awaitCurrent();
    try {
      await _userChain;
    } catch (_) {}
    await _statusController.close();
    await _rejections.close();
  }

  // -------------------------------------------------------------------------
  // Triggers
  // -------------------------------------------------------------------------

  void _onUser(String? userId) {
    _userChain = _userChain
        .then((_) => _handleUser(userId))
        .catchError((Object _) {});
  }

  /// Completes when pending sign-in/sign-out handling (e.g. clearing local
  /// data) has finished. Mainly for tests.
  Future<void> get authSettled => _userChain;

  Future<void> _handleUser(String? userId) async {
    if (_disposed) return;
    final previous = _userId;
    _userId = userId;
    if (userId == null) {
      // Signed out: abort any running cycle, then wipe user-scoped data.
      _generation++;
      await _awaitCurrent();
      if (_disposed) return;
      await db.clearUserData();
      _consecutiveFailures = 0;
      _retry?.cancel();
      _emit(const SyncStatus());
      return;
    }
    if (previous != null && previous != userId) {
      _generation++;
      await _awaitCurrent();
    }
    if (_disposed) return;
    await _ensureUserScope(userId);
    _emit(
      _status.copyWith(
        lastSyncedAt: db.meta.lastSyncedAt,
        pendingOps: db.outbox.length,
      ),
    );
    _requestSync();
  }

  void _onConnectivity(bool online) {
    final wasOnline = _online;
    _online = online;
    if (online && (!wasOnline || _status.state == SyncState.offline)) {
      _requestSync();
    } else if (!online && _current == null && _user != null) {
      _emit(_status.copyWith(state: SyncState.offline));
    }
  }

  void _onForeground(bool foreground) {
    _foreground = foreground;
    if (foreground) {
      _startPeriodic();
      _requestSync();
    } else {
      _periodic?.cancel();
      _periodic = null;
    }
  }

  void _startPeriodic() {
    _periodic?.cancel();
    if (!_foreground || _disposed) return;
    _periodic = Timer.periodic(periodicInterval, (_) => _requestSync());
  }

  void _scheduleDebounced() {
    _debounce?.cancel();
    _debounce = Timer(localWriteDebounce, _requestSync);
  }

  void _scheduleRetry() {
    _consecutiveFailures++;
    final seconds = 5 * math.pow(2, math.min(_consecutiveFailures - 1, 10));
    final delay = Duration(
      seconds: math.min(seconds.toInt(), maxRetryDelay.inSeconds),
    );
    _retry?.cancel();
    _retry = Timer(delay, _requestSync);
  }

  void _requestSync() {
    if (_disposed || _user == null) return;
    if (_current != null) {
      _rerun = true;
    } else {
      unawaited(sync());
    }
  }

  Future<void> _awaitCurrent() async {
    try {
      await _current;
    } catch (_) {}
  }

  // -------------------------------------------------------------------------
  // Cycle
  // -------------------------------------------------------------------------

  Future<void> _loop() async {
    do {
      _rerun = false;
      await _runOnce(_generation);
    } while (_rerun && !_disposed);
  }

  Future<void> _runOnce(int gen) async {
    final userId = _user;
    if (userId == null) {
      _emit(_status.copyWith(state: SyncState.idle, error: null));
      return;
    }
    if (!await _connectivity.isOnline()) {
      _online = false;
      _emit(_status.copyWith(state: SyncState.offline));
      return;
    }
    _online = true;
    _emit(_status.copyWith(state: SyncState.syncing));
    final problems = <String>[];
    try {
      await _ensureUserScope(userId);
      _checkActive(gen);
      final retryLater = await _push(gen, problems);
      await _runImageCopies(gen, problems);
      final initialPull = db.tables.any((t) => db.meta.cursor(t.name) == null);
      await _pull(userId, gen);
      await _syncShares(userId, gen, problems, initialPull: initialPull);
      _checkActive(gen);
      final now = _clock();
      await db.meta.setLastSyncedAt(now);
      if (retryLater) {
        _scheduleRetry();
      } else {
        _consecutiveFailures = 0;
        _retry?.cancel();
      }
      _emit(
        _status.copyWith(
          state: problems.isEmpty ? SyncState.idle : SyncState.error,
          lastSyncedAt: now,
          error: problems.isEmpty ? null : problems.join('\n'),
        ),
      );
    } on _Aborted {
      return;
    } on RemoteException catch (e) {
      if (gen != _generation) return;
      switch (e.kind) {
        case RemoteErrorKind.network:
          _emit(_status.copyWith(state: SyncState.offline, error: null));
          _scheduleRetry();
        case RemoteErrorKind.auth:
          _emit(
            _status.copyWith(
              state: SyncState.error,
              error: 'Your session has expired. Please sign in again.',
            ),
          );
        case _:
          _emit(
            _status.copyWith(
              state: SyncState.error,
              error: 'Sync failed: ${e.message}',
            ),
          );
          _scheduleRetry();
      }
    } catch (e) {
      if (gen != _generation) return;
      _emit(_status.copyWith(state: SyncState.error, error: 'Sync failed: $e'));
      _scheduleRetry();
    }
  }

  Future<void> _ensureUserScope(String userId) async {
    final stored = db.meta.userId;
    if (stored == userId) return;
    if (stored != null) await db.clearUserData();
    await db.meta.setUserId(userId);
  }

  // -------------------------------------------------------------------------
  // Push
  // -------------------------------------------------------------------------

  /// Returns true when some ops must be retried later (transient failures).
  Future<bool> _push(int gen, List<String> problems) async {
    var queue = db.outbox.pending();
    var retryLater = false;
    for (var pass = 0; queue.isNotEmpty && pass < _maxPushPasses; pass++) {
      final deferred = <OutboxOp>[];
      var progressed = false;
      for (final op in queue) {
        _checkActive(gen);
        try {
          await _pushOp(op, gen);
          progressed = true;
        } on RemoteException catch (e) {
          switch (e.kind) {
            case RemoteErrorKind.network:
            case RemoteErrorKind.auth:
              rethrow;
            case RemoteErrorKind.dependency:
              deferred.add(op);
            case RemoteErrorKind.permanent:
            case RemoteErrorKind.conflict:
              await _reject(op, e, gen, problems);
              progressed = true;
            case RemoteErrorKind.transient:
              final updated = await db.outbox.recordFailure(op, e.message);
              if (updated.attempts >= maxAttempts) {
                await _reject(op, e, gen, problems);
              } else {
                retryLater = true;
              }
          }
        }
      }
      queue = deferred;
      if (!progressed) break;
    }
    // Ops still blocked on a missing parent: count as failed attempts.
    for (final op in queue) {
      _checkActive(gen);
      final updated = await db.outbox.recordFailure(
        op,
        'Waiting for a parent row to be saved.',
      );
      if (updated.attempts >= maxAttempts) {
        await _reject(
          op,
          const RemoteException(
            RemoteErrorKind.permanent,
            'The parent item no longer exists.',
          ),
          gen,
          problems,
        );
      } else {
        retryLater = true;
      }
    }
    return retryLater;
  }

  Future<void> _pushOp(OutboxOp op, int gen) async {
    switch (op.op) {
      case OutboxOpType.upsert:
        final payload = op.payload;
        if (payload == null) break;
        final row = await remote.upsert(op.table, payload);
        _checkActive(gen);
        final removed = await db.outbox.complete(op);
        if (removed &&
            row != null &&
            !db.outbox.hasPendingFor(op.table, op.rowId)) {
          await _writeServerRows(db.table(op.table), [row], _user, gen);
        }
        return;
      case OutboxOpType.uploadImage:
        final bytes = await db.images.read(op.rowId);
        if (bytes != null) {
          await imageRemote.uploadImage(
            op.rowId,
            bytes,
            contentType: op.payload?['content_type'] as String?,
          );
        }
      case OutboxOpType.deleteImage:
        await imageRemote.removeImages([op.rowId]);
      case OutboxOpType.delete:
        // Reserved: entities use soft deletes (upserts with deleted_at).
        break;
    }
    _checkActive(gen);
    await db.outbox.complete(op);
  }

  Future<void> _reject(
    OutboxOp op,
    RemoteException e,
    int gen,
    List<String> problems,
  ) async {
    _checkActive(gen);
    await db.outbox.drop(op.id);
    final what = switch (op.table) {
      SyncTables.subjects => 'a subject',
      SyncTables.notes => 'a note',
      SyncTables.quizzes => 'a quiz',
      SyncTables.quizAttempts => 'a quiz attempt',
      SyncTables.noteImagesBucket => 'an image',
      _ => 'an item',
    };
    final message = 'The server rejected a change to $what: ${e.message}';
    problems.add(message);
    if (!_rejections.isClosed) {
      _rejections.add(SyncRejection(op: op, message: message, at: _clock()));
    }
    if (op.op == OutboxOpType.upsert && SyncTables.synced.contains(op.table)) {
      // Restore the server's version so local state does not silently
      // diverge (if the row is not visible, the local copy is kept).
      try {
        final row = await remote.fetchById(op.table, op.rowId);
        if (row != null && !db.outbox.hasPendingFor(op.table, op.rowId)) {
          await _writeServerRows(db.table(op.table), [row], _user, gen);
        }
      } on RemoteException {
        // Best effort.
      }
    }
  }

  Future<void> _runImageCopies(int gen, List<String> problems) async {
    _checkActive(gen);
    try {
      await imageCopies.run();
    } on RemoteException catch (e) {
      if (e.kind == RemoteErrorKind.network || e.kind == RemoteErrorKind.auth) {
        rethrow;
      }
      problems.add('Could not copy images of copied notes: ${e.message}');
    }
  }

  // -------------------------------------------------------------------------
  // Pull
  // -------------------------------------------------------------------------

  Future<void> _pull(String userId, int gen) async {
    for (final table in db.tables) {
      var cursor = db.meta.cursor(table.name);
      PullCursor? after = cursor == null
          ? null
          : PullCursor(
              updatedAt: cursor.updatedAtTime
                  .subtract(pullLookback)
                  .toUtc()
                  .toIso8601String(),
              id: PullCursor.minId,
            );
      while (true) {
        _checkActive(gen);
        final page = await remote.pullPage(
          table.name,
          after: after,
          limit: pageSize,
        );
        if (page.isEmpty) break;
        _checkActive(gen);
        await _writeServerRows(table, page, userId, gen);
        final last = page.last;
        final next = PullCursor(
          updatedAt: last['updated_at'] as String,
          id: last['id'] as String,
        );
        after = next;
        if (cursor == null ||
            !next.updatedAtTime.isBefore(cursor.updatedAtTime)) {
          cursor = next;
          await db.meta.setCursor(table.name, next);
        }
        if (page.length < pageSize) break;
      }
    }
  }

  /// Last-write-wins merge of server rows into [table].
  Future<void> _writeServerRows(
    LocalTable<Syncable> table,
    List<Map<String, dynamic>> rows,
    String? userId,
    int gen,
  ) async {
    Set<String> pendingIds() => {
      for (final op in db.outbox.pending())
        if (op.table == table.name) op.rowId,
    };
    var pending = pendingIds();
    final puts = <String, String>{};
    final removes = <String>[];
    for (final json in rows) {
      final id = json['id'];
      if (id is! String || pending.contains(id)) continue;
      final Syncable row;
      try {
        row = table.decode(json);
      } catch (_) {
        continue; // Unknown shape; skip rather than corrupt local data.
      }
      if (row.isDeleted) {
        // Unknown tombstones carry no information for this device.
        if (table.raw(id) == null) continue;
        // Other users' tombstones are purged; own ones are kept.
        if (!row.isOwnedBy(userId)) {
          removes.add(id);
          continue;
        }
      }
      final encoded = LocalTable.encode(row);
      if (table.raw(id) != encoded) puts[id] = encoded;
    }
    _checkActive(gen);
    // Re-check: a local write may have been queued while decoding.
    pending = pendingIds();
    puts.removeWhere((id, _) => pending.contains(id));
    if (puts.isNotEmpty) await table.box.putAll(puts);
    if (removes.isNotEmpty) await table.removeAll(removes);
  }

  // -------------------------------------------------------------------------
  // Shares: backfill new shares, reconcile revoked access
  // -------------------------------------------------------------------------

  Future<void> _syncShares(
    String userId,
    int gen,
    List<String> problems, {
    required bool initialPull,
  }) async {
    final List<({ShareResourceType type, String resourceId})> incoming;
    try {
      incoming = await remote.incomingShares(userId);
    } on RemoteException catch (e) {
      if (e.kind == RemoteErrorKind.network || e.kind == RemoteErrorKind.auth) {
        rethrow;
      }
      problems.add('Could not check shared items: ${e.message}');
      return;
    }
    _checkActive(gen);
    final keys = {for (final s in incoming) _shareKey(s.type, s.resourceId)};
    final previous = db.meta.incomingShareKeys;
    final added = previous == null
        ? (initialPull ? <String>{} : keys)
        : keys.difference(previous);
    final revoked = previous == null ? <String>{} : previous.difference(keys);

    for (final share in incoming) {
      if (!added.contains(_shareKey(share.type, share.resourceId))) continue;
      await _backfillShare(share.type, share.resourceId, userId, gen);
    }

    final lastReconciled = db.meta.lastReconciledAt;
    final due =
        lastReconciled == null ||
        _clock().difference(lastReconciled) >= reconcileInterval;
    if (revoked.isNotEmpty || due) {
      await reconcileForeignRows(userId: userId, gen: gen);
    }
    _checkActive(gen);
    await db.meta.setIncomingShareKeys(keys);
  }

  static String _shareKey(ShareResourceType type, String id) =>
      '${type.wireName}:$id';

  Future<void> _backfillShare(
    ShareResourceType type,
    String id,
    String userId,
    int gen,
  ) async {
    Future<void> byId(LocalTable<Syncable> table) async {
      final row = await remote.fetchById(table.name, id);
      if (row != null) await _writeServerRows(table, [row], userId, gen);
    }

    Future<void> where(LocalTable<Syncable> table, String column) async {
      final rows = await remote.fetchWhere(table.name, column, id);
      if (rows.isNotEmpty) await _writeServerRows(table, rows, userId, gen);
    }

    switch (type) {
      case ShareResourceType.subject:
        await byId(db.subjects);
        await where(db.notes, 'subject_id');
        await where(db.quizzes, 'subject_id');
      case ShareResourceType.note:
        await byId(db.notes);
        await where(db.quizzes, 'note_id');
      case ShareResourceType.quiz:
        await byId(db.quizzes);
    }
  }

  /// Purges locally cached rows owned by other users that the server no
  /// longer returns (share revoked, item moved out of a shared subject,
  /// tombstone hidden by RLS). Public for tests and manual refresh.
  Future<void> reconcileForeignRows({required String userId, int? gen}) async {
    final g = gen ?? _generation;
    for (final table in [db.subjects, db.notes, db.quizzes]) {
      final foreign = [
        for (final row in table.all())
          if (!row.isOwnedBy(userId)) row,
      ];
      for (var i = 0; i < foreign.length; i += _idChunk) {
        final chunk = foreign.sublist(
          i,
          math.min(i + _idChunk, foreign.length),
        );
        _checkActive(g);
        final visible = await remote.fetchVisibleIds(table.name, [
          for (final r in chunk) r.id,
        ]);
        _checkActive(g);
        final gone = [
          for (final r in chunk)
            if (!visible.contains(r.id)) r,
        ];
        if (gone.isEmpty) continue;
        await table.removeAll(gone.map((r) => r.id));
        if (table.name == SyncTables.notes) {
          for (final note in gone) {
            await db.images.removePrefix('${note.ownerId}/${note.id}/');
          }
        }
      }
    }
    await db.meta.setLastReconciledAt(_clock());
  }

  // -------------------------------------------------------------------------

  void _checkActive(int gen) {
    if (gen != _generation || _disposed) throw const _Aborted();
  }

  void _emit(SyncStatus next) {
    final withCount = next.copyWith(pendingOps: db.outbox.length);
    if (withCount == _status) return;
    _status = withCount;
    if (!_statusController.isClosed) _statusController.add(withCount);
  }
}

/// Thrown internally when the user changed / engine disposed mid-cycle.
class _Aborted implements Exception {
  const _Aborted();
}
