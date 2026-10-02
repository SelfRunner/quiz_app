import '../../core/errors/app_exception.dart';
import '../models/models.dart';
import '../remote/remote_data_source.dart';
import '../sync/connectivity_monitor.dart';
import '../sync/note_image_copy_processor.dart';
import 'repository_support.dart';
import 'share_repository.dart';

/// Online-only [ShareRepository] over Supabase (`shares` table + RPCs).
///
/// Every method checks connectivity first and throws [NetworkException]
/// with a clear message when offline.
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

    Map<String, dynamic> row;
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
      if (e.kind != RemoteErrorKind.conflict) throw remoteToAppException(e);
      // Already shared with this user: idempotent.
      final existing = await _call(
        () => _remote.findShare(
          type: resourceType,
          resourceId: resourceId,
          recipientId: recipientId,
        ),
      );
      if (existing == null) throw remoteToAppException(e);
      row = existing;
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
    final shares = rows.map(Share.fromJson).toList();
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
    await _requireOnline();
    final rows = await _call(() => _remote.sharesForRecipient(userId));
    final shares = rows.map(Share.fromJson).toList();
    final profiles = await _profiles([
      for (final s in shares)
        if (s.owner == null) s.ownerId,
    ]);
    final titles = await Future.wait(shares.map(_titleOf));
    return [
      for (var i = 0; i < shares.length; i++)
        shares[i].copyWith(
          owner: shares[i].owner ?? profiles[shares[i].ownerId],
          resourceTitle: titles[i],
        ),
    ];
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
        if (resourceType != ShareResourceType.quiz) {
          throw const ValidationException(
            'Only quizzes can be attached to a note.',
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
  };

  Future<String?> _titleOf(Share share) async {
    final local = _localResource(share.resourceType, share.resourceId);
    final title = switch (local) {
      final Subject s => s.title,
      final Note n => n.title,
      final Quiz q => q.title,
      _ => null,
    };
    if (title != null) return title;
    final table = switch (share.resourceType) {
      ShareResourceType.subject => SyncTables.subjects,
      ShareResourceType.note => SyncTables.notes,
      ShareResourceType.quiz => SyncTables.quizzes,
    };
    try {
      return await _remote.fetchTitle(table, share.resourceId);
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
