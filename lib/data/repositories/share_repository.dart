import '../models/profile.dart';
import '../models/share.dart';

/// Sharing (online-only; throws `NetworkException` when offline).
///
/// Shares are view-only. Sharing a subject grants live access to all its
/// current and future notes/quizzes. Shared rows are pulled into Hive by sync,
/// so `NoteRepository.watchBySubject` etc. also work for shared subjects.
abstract interface class ShareRepository {
  /// Exact email lookup via RPC. Returns null if no such user. Returned
  /// profile has no email (only id + displayName).
  Future<Profile?> findUserByEmail(String email);

  /// Shares a resource owned by the current user with [recipientId].
  /// Idempotent per (type, id, recipient). Throws `ValidationException` when
  /// sharing with yourself.
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
  /// and `resourceTitle` filled when available.
  Future<List<Share>> sharedWithMe();

  /// Deep-copies a shared resource into the current user's account (via the
  /// `copy_*` RPCs) and triggers a sync. Returns the new resource id.
  /// [targetSubjectId] is required for notes and quizzes;
  /// [targetNoteId] optionally attaches a copied quiz to a note.
  Future<String> copyToMyAccount({
    required ShareResourceType resourceType,
    required String resourceId,
    String? targetSubjectId,
    String? targetNoteId,
  });
}
