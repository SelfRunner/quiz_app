import '../models/profile.dart';
import '../models/share.dart';

/// Sharing (online-only; throws `NetworkException` when offline), except
/// [sharedWithMe], which serves the last list cached in Hive when offline.
///
/// Shares are view-only. Sharing a subject grants live access to all its
/// current and future notes/quizzes. Shared rows are pulled into Hive by sync,
/// so `NoteRepository.watchBySubject` etc. also work for shared subjects.
abstract interface class ShareRepository {
  /// Exact (case-insensitive, trimmed) email lookup via RPC. Returns null if
  /// no such user. The profile has id, displayName and email.
  Future<Profile?> findUserByEmail(String email);

  /// Shares a resource owned by the current user with [recipientId].
  /// Throws `AlreadySharedException` (a `ValidationException`) when it is
  /// already shared with that user, `ValidationException` when sharing with
  /// yourself, and `NetworkException` when the resource hasn't been uploaded
  /// yet (its create is still queued).
  Future<Share> share({
    required ShareResourceType resourceType,
    required String resourceId,
    required String recipientId,
  });

  /// Deletes the share (owner only).
  Future<void> revoke(String shareId);

  /// Shares the current user created for one resource, with `recipient`
  /// profiles joined.
  Future<List<Share>> listSharesFor(
    ShareResourceType resourceType,
    String resourceId,
  );

  /// Shares where the current user is the recipient, with `owner` profiles
  /// and `resourceTitle` filled when available. Offline (or when the request
  /// fails in transit) returns the last list fetched online, persisted in
  /// Hive, adjusted to shares seen by later syncs; throws `NetworkException`
  /// only when nothing is cached.
  Future<List<Share>> sharedWithMe();

  /// Deep-copies a shared resource into the current user's account (via the
  /// `copy_*` RPCs) and triggers a sync. Returns the new resource id.
  /// [targetSubjectId] is required for notes, quizzes and decks;
  /// [targetNoteId] optionally attaches a copied quiz or deck to a note
  /// (which must be in [targetSubjectId]). Copying a subject or note also
  /// copies its decks (`copy_subject` / `copy_note`).
  Future<String> copyToMyAccount({
    required ShareResourceType resourceType,
    required String resourceId,
    String? targetSubjectId,
    String? targetNoteId,
  });
}
