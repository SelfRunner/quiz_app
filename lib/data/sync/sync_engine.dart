import 'package:freezed_annotation/freezed_annotation.dart';

part 'sync_engine.freezed.dart';

enum SyncState { idle, syncing, offline, error }

@freezed
abstract class SyncStatus with _$SyncStatus {
  const factory SyncStatus({
    @Default(SyncState.idle) SyncState state,
    DateTime? lastSyncedAt,

    /// Number of ops waiting in the outbox.
    @Default(0) int pendingOps,

    /// Message of the last error when [state] is [SyncState.error].
    String? error,
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
