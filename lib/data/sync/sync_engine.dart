import 'package:freezed_annotation/freezed_annotation.dart';

part 'sync_engine.freezed.dart';

enum SyncState { idle, syncing, offline, error }

/// User-facing explanation shown when [SyncStatus.serverOutdated] is set.
const String serverOutdatedMessage =
    'The server database needs an update (run the latest Supabase '
    'migration). Your changes are kept on this device.';

@freezed
abstract class SyncStatus with _$SyncStatus {
  const factory SyncStatus({
    @Default(SyncState.idle) SyncState state,
    DateTime? lastSyncedAt,

    /// Number of ops waiting in the outbox.
    @Default(0) int pendingOps,

    /// Message of the last error when [state] is [SyncState.error].
    String? error,

    /// Outbox ops that keep failing with transient (5xx/unknown) errors and
    /// have reached the attempt threshold. They are never dropped; sync keeps
    /// retrying them with capped backoff.
    @Default(0) int stuckOps,

    /// Changes the server rejected permanently whose content is kept locally
    /// (`DefaultSyncEngine.rejectedChanges`) until dismissed.
    @Default(0) int rejectedChanges,

    /// The server database is older than the app (schema-cache errors such
    /// as PGRST204/PGRST205: missing column/table/function). Affected
    /// changes stay queued (never dropped) and affected tables are retried
    /// on every sync until the migration has been applied. [state] is
    /// [SyncState.error] and [error] contains [serverOutdatedMessage].
    @Default(false) bool serverOutdated,

    /// Tables (or Storage buckets / RPCs) the server could not serve in the
    /// last cycle because its schema is out of date, sorted. Other tables
    /// still sync normally.
    @Default(<String>[]) List<String> unavailableTables,
  }) = _SyncStatus;
}

/// Pushes the outbox and pulls remote changes.
///
/// Push: outbox ops FIFO (upsert / soft-delete / image upload).
/// Pull: per table in `SyncTables.synced`, rows with `updated_at > cursor`
/// (own + shared), last-write-wins into Hive; cursor = max server
/// `updated_at` seen.
abstract interface class SyncEngine {
  Stream<SyncStatus> get status;

  SyncStatus get currentStatus;

  /// Starts automatic triggers (connectivity regained, sign-in, app resume,
  /// local writes). Safe to call more than once.
  void start();

  /// Runs one push+pull cycle. Concurrent calls join the running cycle.
  /// Never throws for network errors (reported via [status]).
  Future<void> sync();

  Future<void> dispose();
}
