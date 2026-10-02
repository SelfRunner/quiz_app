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
/// - transient error (5xx, unknown): `attempts++`, retried with capped
///   exponential backoff, **never dropped** (an outage must not lose data).
///   Ops with `attempts >= maxAttempts` are reported as `SyncStatus.stuckOps`.
/// - rejected upserts keep the user's row JSON in `sync_meta`
///   ([rejectedChanges]) until [dismissRejectedChange].
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
  }) : imageCopies = NoteImageCopyProcessor(
         imageRemote,
         db.images,
         attachmentCache: db.attachmentFiles,
       ) {
    _rejectedCount = db.meta.rejectedChanges.length;
    _status = SyncStatus(
      lastSyncedAt: db.meta.lastSyncedAt,
      pendingOps: db.outbox.length,
      stuckOps: _countStuck(),
      rejectedChanges: _rejectedCount,
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

  /// Transient failures after which an op counts as "stuck" (still retried).
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
  int _rejectedCount = 0;

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

  /// Rejected changes whose content is kept locally (oldest first).
  List<RejectedChange> get rejectedChanges => db.meta.rejectedChanges;

  /// Forgets a kept rejected change (e.g. after the user re-applied it).
  Future<void> dismissRejectedChange(String id) async {
    await db.meta.removeRejectedChange(id);
    _rejectedCount = db.meta.rejectedChanges.length;
    _emit(_status);
  }

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
      // Signed out: abort any running cycle and stop syncing, but keep local
      // data. The session may have ended involuntarily (refresh token
      // revoked/expired); unpushed changes are pushed when the same user
      // signs back in. Data is wiped by [clearAfterSignOut] (explicit
      // sign-out) or when a different user signs in ([_ensureUserScope]).
      _generation++;
      await _awaitCurrent();
      if (_disposed) return;
      _consecutiveFailures = 0;
      _retry?.cancel();
      _debounce?.cancel();
      _emit(SyncStatus(lastSyncedAt: db.meta.lastSyncedAt));
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

  /// Wipes all user-scoped local data (entities, outbox, sync meta, image
  /// cache) after an explicit, user-initiated sign-out. Serialized with auth
  /// handling; aborts a running cycle first. No-op if a user is signed in
  /// again by the time it runs.
  Future<void> clearAfterSignOut() {
    final done = _userChain.then((_) async {
      if (_currentUserId() != null) return;
      if (_hasUserStream) _userId = null;
      _generation++;
      await _awaitCurrent();
      await db.clearUserData();
      _rejectedCount = 0;
      _consecutiveFailures = 0;
      _retry?.cancel();
      _debounce?.cancel();
      if (!_disposed) _emit(const SyncStatus());
    });
    _userChain = done.catchError((Object _) {});
    return done;
  }

  void _onConnectivity(bool online) {
    final wasOnline = _online;
    _online = online;
    if (_current != null) {
      // A running cycle may already have checked connectivity (its result is
      // now stale) and would end in the wrong state, e.g. `idle` although we
      // just went offline, or `offline` although we are back online with no
      // further trigger. Run one more cycle; `sync()` callers joining the
      // running cycle also wait for it.
      _rerun = true;
      return;
    }
    if (online && (!wasOnline || _status.state == SyncState.offline)) {
      _requestSync();
    } else if (!online && _user != null) {
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
      final stuck = _countStuck();
      if (stuck > 0) {
        problems.add(
          '$stuck change${stuck == 1 ? '' : 's'} could not be saved yet '
          '(server error). Retrying automatically.',
        );
      }
      _emit(
        _status.copyWith(
          state: problems.isEmpty ? SyncState.idle : SyncState.error,
          lastSyncedAt: now,
          error: problems.isEmpty ? null : problems.join('\n'),
          stuckOps: stuck,
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
          if (e.kind == RemoteErrorKind.conflict && _isPrivateStudyUpsert(op)) {
            // Same (deck, card) / (quiz, question) row exists under another
            // id: re-keyed locally, pushed again in the next pass.
            final adopted = await _adoptExistingKey(op, gen);
            if (adopted != null) {
              deferred.add(adopted);
              progressed = true;
              continue;
            }
          }
          switch (e.kind) {
            case RemoteErrorKind.network:
            case RemoteErrorKind.auth:
              rethrow;
            case RemoteErrorKind.dependency:
              deferred.add(op);
            case RemoteErrorKind.permanent
                when _isPrivateStudyUpsert(op) && e.code == '42501':
              // Deck/quiz no longer readable (share revoked, deleted): the
              // review/mistake can't be saved. Drop it quietly.
              _checkActive(gen);
              await db.outbox.drop(op.id);
              progressed = true;
            case RemoteErrorKind.permanent:
            case RemoteErrorKind.conflict:
              await _reject(op, e, gen, problems);
              progressed = true;
            case RemoteErrorKind.transient:
              // Server trouble (5xx, timeouts, unknown): never drop, keep
              // retrying with capped backoff. Attempts only flag "stuck".
              await db.outbox.recordFailure(op, e.message);
              retryLater = true;
          }
        }
      }
      queue = deferred;
      if (!progressed) break;
    }
    // Ops still blocked on a missing parent: count as failed attempts, unless
    // other ops failed transiently in this cycle (the parent may be one of
    // them; it must not be dropped because of a server outage).
    if (retryLater) return true;
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
        if (op.table == SyncTables.attachments) {
          _ensureAttachmentUploaded(payload);
        }
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
      case OutboxOpType.uploadAttachment:
        final bytes = await db.attachmentFiles.read(op.rowId);
        // Bytes gone (e.g. deleted meanwhile): nothing left to upload.
        if (bytes != null) {
          await db.transfers.track(
            op.rowId,
            () => imageRemote.uploadImage(
              op.rowId,
              bytes,
              contentType: op.payload?['content_type'] as String?,
              bucket: SyncTables.attachmentsBucket,
            ),
          );
        }
      case OutboxOpType.deleteAttachment:
        final id = op.payload?['attachment_id'] as String?;
        if (id != null && db.outbox.hasPendingFor(SyncTables.attachments, id)) {
          // The tombstone must reach the server before the blob goes away.
          throw const RemoteException(
            RemoteErrorKind.dependency,
            'Waiting for the file deletion to be saved.',
          );
        }
        await imageRemote.removeImages([
          op.rowId,
        ], bucket: SyncTables.attachmentsBucket);
      case OutboxOpType.delete:
        // Reserved: entities use soft deletes (upserts with deleted_at).
        break;
    }
    _checkActive(gen);
    await db.outbox.complete(op);
  }

  static bool _isPrivateStudyUpsert(OutboxOp op) =>
      op.op == OutboxOpType.upsert &&
      SyncTables.privateStudy.contains(op.table) &&
      op.payload != null;

  /// Handles a unique-key violation (`23505`) of a `card_reviews` /
  /// `mistakes` upsert: another row already holds the natural key (e.g.
  /// created by a client that did not derive the id). Adopts the server
  /// row's id, re-applies the local change on top of it and queues it.
  /// Returns the new op, or null when no such row is visible (the op is
  /// then rejected).
  Future<OutboxOp?> _adoptExistingKey(OutboxOp op, int gen) async {
    final payload = op.payload!;
    final (parentColumn, keyColumn) = op.table == SyncTables.cardReviews
        ? ('deck_id', 'card_id')
        : ('quiz_id', 'question_id');
    final parentId = payload[parentColumn];
    final key = payload[keyColumn];
    if (parentId is! String || key is! String) return null;
    final rows = await remote.fetchWhere(op.table, parentColumn, parentId);
    _checkActive(gen);
    final existing = rows
        .where(
          (r) =>
              r[keyColumn] == key &&
              r['owner_id'] == payload['owner_id'] &&
              r['id'] != op.rowId,
        )
        .firstOrNull;
    final existingId = existing?['id'];
    if (existingId is! String) return null;
    final table = db.table(op.table);
    final next = {
      ...payload,
      'id': existingId,
      'created_at': existing!['created_at'] ?? payload['created_at'],
    };
    final Syncable row;
    try {
      row = table.decode(next);
    } catch (_) {
      return null;
    }
    await db.outbox.drop(op.id);
    await table.remove(op.rowId);
    final adopted = await db.outbox.enqueueUpsert(
      op.table,
      existingId,
      row.toJson(),
    );
    await table.box.put(existingId, LocalTable.encode(row));
    return adopted;
  }

  /// An attachment row is pushed only after its blob upload (queued before
  /// it) has completed, so recipients rarely see a row without a blob.
  void _ensureAttachmentUploaded(Map<String, dynamic> payload) {
    if (payload['deleted_at'] != null) return;
    final path = payload['storage_path'];
    if (path is! String) return;
    if (db.outbox.pendingFor(
          SyncTables.attachmentsBucket,
          path,
          op: OutboxOpType.uploadAttachment,
        ) !=
        null) {
      throw const RemoteException(
        RemoteErrorKind.dependency,
        'Waiting for the file upload to finish.',
      );
    }
  }

  Future<void> _reject(
    OutboxOp op,
    RemoteException e,
    int gen,
    List<String> problems,
  ) async {
    _checkActive(gen);
    await db.outbox.drop(op.id);
    final what = switch (op.op) {
      OutboxOpType.uploadAttachment ||
      OutboxOpType.deleteAttachment => 'a file upload',
      OutboxOpType.uploadImage || OutboxOpType.deleteImage => 'an image',
      _ => switch (op.table) {
        SyncTables.subjects => 'a subject',
        SyncTables.notes => 'a note',
        SyncTables.quizzes => 'a quiz',
        SyncTables.quizAttempts => 'a quiz attempt',
        SyncTables.attachments => 'a file',
        SyncTables.decks => 'a flashcard deck',
        SyncTables.cardReviews => 'a flashcard review',
        SyncTables.mistakes => 'a mistake',
        _ => 'an item',
      },
    };
    final message = 'The server rejected a change to $what: ${e.message}';
    problems.add(message);
    final at = _clock();
    if (!_rejections.isClosed) {
      _rejections.add(SyncRejection(op: op, message: message, at: at));
    }
    if (op.op == OutboxOpType.upsert && SyncTables.synced.contains(op.table)) {
      // Keep the user's version before the server's replaces it locally.
      await db.meta.addRejectedChange(
        RejectedChange(
          id: op.id,
          table: op.table,
          rowId: op.rowId,
          payload: op.payload,
          message: message,
          at: at,
        ),
      );
      _rejectedCount = db.meta.rejectedChanges.length;
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
    // Blobs of attachments that became tombstones / were purged.
    final deadBlobs = <String>[];
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
        if (row is Attachment) deadBlobs.add(row.storagePath);
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
    await _removeBlobs(deadBlobs);
  }

  Future<void> _removeBlobs(List<String> paths) async {
    for (final path in paths) {
      try {
        await db.attachmentFiles.remove(path);
      } catch (_) {
        // Best effort: a stale cache entry is only wasted space.
      }
    }
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
        await where(db.attachments, 'subject_id');
        await where(db.decks, 'subject_id');
      case ShareResourceType.note:
        await byId(db.notes);
        await where(db.quizzes, 'note_id');
        await where(db.decks, 'note_id');
      case ShareResourceType.quiz:
        await byId(db.quizzes);
      case ShareResourceType.deck:
        await byId(db.decks);
    }
  }

  /// Purges locally cached rows owned by other users that the server no
  /// longer returns (share revoked, item moved out of a shared subject,
  /// tombstone hidden by RLS). Public for tests and manual refresh.
  Future<void> reconcileForeignRows({required String userId, int? gen}) async {
    final g = gen ?? _generation;
    for (final table in [
      db.subjects,
      db.notes,
      db.quizzes,
      db.attachments,
      db.decks,
    ]) {
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
        await _removeBlobs([
          for (final r in gone)
            if (r is Attachment) r.storagePath,
        ]);
      }
    }
    await _purgeOrphanStudyRows(g);
    await db.meta.setLastReconciledAt(_clock());
  }

  /// Own `card_reviews` / `mistakes` whose deck / quiz is not cached are
  /// kept (hidden) while the server still has them (access revoked: the
  /// server keeps them), and purged when the server no longer returns them
  /// (parent hard-deleted: rows cascaded without tombstones).
  Future<void> _purgeOrphanStudyRows(int gen) async {
    Future<void> purge<T extends Syncable>(
      LocalTable<T> table,
      bool Function(T row) orphan,
    ) async {
      final candidates = [
        for (final row in table.all())
          if (orphan(row) && !db.outbox.hasPendingFor(table.name, row.id))
            row.id,
      ];
      for (var i = 0; i < candidates.length; i += _idChunk) {
        final chunk = candidates.sublist(
          i,
          math.min(i + _idChunk, candidates.length),
        );
        _checkActive(gen);
        final visible = await remote.fetchVisibleIds(table.name, chunk);
        _checkActive(gen);
        final gone = chunk.where((id) => !visible.contains(id)).toList();
        if (gone.isNotEmpty) await table.removeAll(gone);
      }
    }

    await purge<CardReview>(db.reviews, (r) => db.decks.raw(r.deckId) == null);
    await purge<Mistake>(db.mistakes, (m) => db.quizzes.raw(m.quizId) == null);
  }

  // -------------------------------------------------------------------------

  void _checkActive(int gen) {
    if (gen != _generation || _disposed) throw const _Aborted();
  }

  int _countStuck() =>
      db.outbox.pending().where((op) => op.attempts >= maxAttempts).length;

  void _emit(SyncStatus next) {
    final withCount = next.copyWith(
      pendingOps: db.outbox.length,
      rejectedChanges: _rejectedCount,
    );
    if (withCount == _status) return;
    _status = withCount;
    if (!_statusController.isClosed) _statusController.add(withCount);
  }
}

/// Thrown internally when the user changed / engine disposed mid-cycle.
class _Aborted implements Exception {
  const _Aborted();
}
