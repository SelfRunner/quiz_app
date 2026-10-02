import '../../core/errors/app_exception.dart';
import '../models/models.dart';
import '../remote/remote_data_source.dart';
import '../sync/connectivity_monitor.dart';
import '../sync/note_image_copy_processor.dart';
import 'repository_support.dart';
import 'share_repository.dart';

/// [ShareRepository] over Supabase (`shares` table + RPCs).
///
/// Every method checks connectivity first and throws [NetworkException]
/// with a clear message when offline, except [sharedWithMe], which falls back
/// to the last list fetched online (persisted in `sync_meta`) or, failing
/// that, a list derived from the share keys and rows cached by sync.
class SupabaseShareRepository implements ShareRepository {
  SupabaseShareRepository({
    required this._ctx,
    required this._remote,
    required this._imageCopies,
    required this._connectivity,
    required this._sync,
  });

  final DataContext _ctx;
  final ShareRemoteDataSource _remote;
  final NoteImageCopyProcessor _imageCopies;
  final ConnectivityMonitor _connectivity;

  /// Runs a sync cycle that starts after the call (`syncFresh`).
  final Future<void> Function() _sync;

  @override
  Future<Profile?> findUserByEmail(String email) async {
    _ctx.requireUserId();
    final trimmed = email.trim();
    if (!trimmed.contains('@') || trimmed.length < 3) {
      throw const ValidationException('Enter a valid email address.');
    }
    await _requireOnline();
    final found = await _call(() => _remote.findUserByEmail(trimmed));
    if (found == null) return null;
    return Profile(
      id: found.id,
      displayName: found.displayName,
      email: found.email,
    );
  }

  @override
  Future<Share> share({
    required ShareResourceType resourceType,
    required String resourceId,
    required String recipientId,
  }) async {
    final userId = _ctx.requireUserId();
    if (recipientId == userId) {
      throw const ValidationException("You can't share with yourself.");
    }
    final resource = _localResource(resourceType, resourceId);
    if (resource == null || resource.isDeleted) {
      throw const NotFoundException('This item no longer exists.');
    }
    _ctx.ensureOwned(resource, userId, resourceType.wireName);
    await _requireOnline();
    // The resource must exist on the server before it can be shared.
    if (_ctx.db.outbox.length > 0) await _sync();

    final Map<String, dynamic> row;
    try {
      row = await _remote.insertShare({
        'id': _ctx.newId(),
        'owner_id': userId,
        'recipient_id': recipientId,
        'resource_type': resourceType.wireName,
        'resource_id': resourceId,
        'created_at': _ctx.clock().toIso8601String(),
      });
    } on RemoteException catch (e) {
      if (e.kind == RemoteErrorKind.conflict) {
        throw AlreadySharedException(
          'This ${resourceType.wireName} is already shared with that person.',
          cause: e,
        );
      }
      if ((e.kind == RemoteErrorKind.permanent ||
              e.kind == RemoteErrorKind.dependency) &&
          _ctx.db.outbox.hasPendingFor(_tableOf(resourceType), resourceId)) {
        // The server doesn't have the resource yet (its upload is still
        // queued), so RLS/FK refuse the share: say so instead of a
        // misleading permission error.
        throw NetworkException(
          "This ${resourceType.wireName} hasn't finished uploading yet. "
          'Check your connection and try again in a moment.',
          cause: e,
        );
      }
      throw remoteToAppException(e);
    }
    final share = Share.fromJson(row);
    if (share.recipient != null) return share;
    final profiles = await _profiles([recipientId]);
    return share.copyWith(recipient: profiles[recipientId]);
  }

  @override
  Future<void> revoke(String shareId) async {
    _ctx.requireUserId();
    await _requireOnline();
    await _call(() => _remote.deleteShare(shareId));
  }

  @override
  Future<List<Share>> listSharesFor(
    ShareResourceType resourceType,
    String resourceId,
  ) async {
    final userId = _ctx.requireUserId();
    await _requireOnline();
    final rows = await _call(
      () => _remote.sharesForResource(
        ownerId: userId,
        type: resourceType,
        resourceId: resourceId,
      ),
    );
    final shares = [for (final r in rows) ?_tryShare(r)];
    final missing = [
      for (final s in shares)
        if (s.recipient == null) s.recipientId,
    ];
    final profiles = await _profiles(missing);
    return [
      for (final s in shares)
        s.recipient == null
            ? s.copyWith(recipient: profiles[s.recipientId])
            : s,
    ];
  }

  @override
  Future<List<Share>> sharedWithMe() async {
    final userId = _ctx.requireUserId();
    try {
      await _requireOnline();
      final rows = await _call(() => _remote.sharesForRecipient(userId));
      // Rows of resource types this build doesn't know are ignored.
      final shares = [for (final r in rows) ?_tryShare(r)];
      final profiles = await _profiles([
        for (final s in shares)
          if (s.owner == null) s.ownerId,
      ]);
      final titles = await Future.wait(shares.map(_titleOf));
      final result = [
        for (var i = 0; i < shares.length; i++)
          shares[i].copyWith(
            owner: shares[i].owner ?? profiles[shares[i].ownerId],
            resourceTitle: titles[i],
          ),
      ];
      await _cacheSharedWithMe(userId, result);
      return result;
    } on NetworkException {
      final cached = _offlineSharedWithMe(userId);
      if (cached == null) rethrow;
      return cached;
    }
  }

  Future<void> _cacheSharedWithMe(String userId, List<Share> shares) async {
    try {
      await _ctx.db.meta.setSharedWithMe((
        userId: userId,
        fetchedAt: _ctx.clock(),
        rows: [
          for (final s in shares)
            {
              ...s.toJson(),
              'owner': s.owner?.toJson(),
              'resource_title': s.resourceTitle,
            },
        ],
      ));
    } catch (_) {
      // Best effort: the online result is still returned.
    }
  }

  /// "Shared with me" from local data only, or null when nothing is known.
  ///
  /// Starts from the last list fetched online. If sync has checked the
  /// user's incoming shares since then (`incomingShareKeys`), revoked shares
  /// are dropped and new ones are derived from the locally cached rows.
  /// Titles come from the local cache when available.
  List<Share>? _offlineSharedWithMe(String userId) {
    final meta = _ctx.db.meta;
    final raw = meta.sharedWithMe;
    final snapshot = raw != null && raw.userId == userId ? raw : null;
    final keys = meta.userId == userId ? meta.incomingShareKeys : null;
    final lastSynced = meta.lastSyncedAt;
    final keysAreNewer =
        snapshot == null ||
        (lastSynced != null && lastSynced.isAfter(snapshot.fetchedAt));
    if (snapshot == null && keys == null) return null;

    var shares = <Share>[
      if (snapshot != null)
        for (final row in snapshot.rows) ?_tryShare(row),
    ];
    if (keys != null && keysAreNewer) {
      shares = [
        for (final s in shares)
          if (keys.contains(_shareKey(s.resourceType, s.resourceId))) s,
      ];
      final known = {
        for (final s in shares) _shareKey(s.resourceType, s.resourceId),
      };
      for (final key in keys.difference(known)) {
        final derived = _deriveShare(key, userId);
        if (derived != null) shares.add(derived);
      }
    }
    return [
      for (final s in shares)
        s.copyWith(resourceTitle: _localTitle(s) ?? s.resourceTitle),
    ];
  }

  static Share? _tryShare(Map<String, dynamic> json) {
    try {
      return Share.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  static String _shareKey(ShareResourceType type, String id) =>
      '${type.wireName}:$id';

  /// A placeholder share for a resource sync knows was shared with the user
  /// (no share row is stored locally), or null if the resource isn't cached.
  Share? _deriveShare(String key, String userId) {
    final i = key.indexOf(':');
    if (i <= 0) return null;
    final type = ShareResourceType.values
        .where((t) => t.wireName == key.substring(0, i))
        .firstOrNull;
    if (type == null) return null;
    final resource = _localResource(type, key.substring(i + 1));
    if (resource == null || resource.isDeleted) return null;
    return Share(
      id: 'local:$key',
      ownerId: resource.ownerId,
      recipientId: userId,
      resourceType: type,
      resourceId: resource.id,
      createdAt: resource.createdAt,
    );
  }

  @override
  Future<String> copyToMyAccount({
    required ShareResourceType resourceType,
    required String resourceId,
    String? targetSubjectId,
    String? targetNoteId,
  }) async {
    final userId = _ctx.requireUserId();
    if (resourceType != ShareResourceType.subject) {
      if (targetSubjectId == null) {
        throw const ValidationException('Choose a subject to copy into.');
      }
      final subject = _ctx.requireLive(
        _ctx.db.subjects,
        targetSubjectId,
        'subject',
      );
      _ctx.ensureOwned(subject, userId, 'subject');
      if (targetNoteId != null) {
        if (resourceType != ShareResourceType.quiz &&
            resourceType != ShareResourceType.deck) {
          throw const ValidationException(
            'Only quizzes and decks can be attached to a note.',
          );
        }
        final note = _ctx.requireLive(_ctx.db.notes, targetNoteId, 'note');
        _ctx.ensureOwned(note, userId, 'note');
        if (note.subjectId != targetSubjectId) {
          throw const ValidationException(
            'The note belongs to a different subject.',
          );
        }
      }
    }
    await _requireOnline();
    // Push local changes first so the target subject/note exists remotely.
    if (_ctx.db.outbox.length > 0) await _sync();
    final newId = await _call(
      () => _remote.copyResource(
        type: resourceType,
        resourceId: resourceId,
        targetSubjectId: targetSubjectId,
        targetNoteId: targetNoteId,
      ),
    );
    // Storage half of the copy (note_image_copies queue). Leftovers are
    // retried by every sync, so failures here are not fatal.
    try {
      await _imageCopies.run();
    } catch (_) {}
    await _sync();
    return newId;
  }

  // -------------------------------------------------------------------------

  Syncable? _localResource(ShareResourceType type, String id) => switch (type) {
    ShareResourceType.subject => _ctx.db.subjects.get(id),
    ShareResourceType.note => _ctx.db.notes.get(id),
    ShareResourceType.quiz => _ctx.db.quizzes.get(id),
    ShareResourceType.deck => _ctx.db.decks.get(id),
  };

  static String _tableOf(ShareResourceType type) => switch (type) {
    ShareResourceType.subject => SyncTables.subjects,
    ShareResourceType.note => SyncTables.notes,
    ShareResourceType.quiz => SyncTables.quizzes,
    ShareResourceType.deck => SyncTables.decks,
  };

  String? _localTitle(Share share) =>
      switch (_localResource(share.resourceType, share.resourceId)) {
        final Subject s => s.title,
        final Note n => n.title,
        final Quiz q => q.title,
        final Deck d => d.title,
        _ => null,
      };

  Future<String?> _titleOf(Share share) async {
    final title = _localTitle(share);
    if (title != null) return title;
    try {
      return await _remote.fetchTitle(
        _tableOf(share.resourceType),
        share.resourceId,
      );
    } on RemoteException {
      return null;
    }
  }

  /// Best-effort profile lookup (RLS may hide some profiles).
  Future<Map<String, Profile>> _profiles(Iterable<String> ids) async {
    final unique = ids.toSet().toList();
    if (unique.isEmpty) return const {};
    try {
      final rows = await _remote.fetchProfiles(unique);
      return {
        for (final r in rows)
          if (r['id'] is String) r['id'] as String: Profile.fromJson(r),
      };
    } catch (_) {
      return const {};
    }
  }

  Future<void> _requireOnline() async {
    if (!await _connectivity.isOnline()) {
      throw const NetworkException(
        "You're offline. Sharing needs an internet connection.",
      );
    }
  }

  static Future<T> _call<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on RemoteException catch (e) {
      throw remoteToAppException(e);
    }
  }
}
