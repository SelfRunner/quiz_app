import '../../core/errors/app_exception.dart';
import '../../core/utils/clock.dart';
import '../local/local_database.dart';
import '../local/local_table.dart';
import '../models/models.dart';
import '../remote/remote_data_source.dart';

/// Shared plumbing for the local-first repositories.
class DataContext {
  DataContext({
    required this.db,
    required this.clock,
    required this.newId,
    required this._currentUserId,
  });

  final LocalDatabase db;
  final Clock clock;
  final IdGenerator newId;
  final String? Function() _currentUserId;

  String? get currentUserId => _currentUserId();

  /// Current user id, or throws [AppAuthException].
  String requireUserId() {
    final id = _currentUserId();
    if (id == null) {
      throw const AppAuthException('You are signed out. Sign in to continue.');
    }
    return id;
  }

  /// Throws [PermissionDeniedException] unless [row] is owned by [userId].
  void ensureOwned(Syncable row, String userId, String noun) {
    if (!row.isOwnedBy(userId)) {
      throw PermissionDeniedException(
        'This $noun was shared with you and is read-only.',
      );
    }
  }

  /// Live (non-deleted) row or [NotFoundException].
  T requireLive<T extends Syncable>(
    LocalTable<T> table,
    String id,
    String noun,
  ) {
    final row = table.getLive(id);
    if (row == null) throw NotFoundException('This $noun no longer exists.');
    return row;
  }

  /// Writes locally and queues the upsert.
  Future<void> save<T extends Syncable>(LocalTable<T> table, T row) async {
    try {
      await db.saveAndEnqueue(table, row);
    } on AppException {
      rethrow;
    } catch (e, st) {
      throw StorageException(
        'Could not save changes on this device.',
        cause: e,
        stackTrace: st,
      );
    }
  }

  /// Removes the local copy of an image and queues its deletion from
  /// Storage (dropping a pending upload of the same path).
  Future<void> queueImageDeletion(NoteImageRef ref) async {
    final path = ref.storagePath;
    await db.outbox.removeFor(
      SyncTables.noteImagesBucket,
      path,
      OutboxOpType.uploadImage,
    );
    await db.images.remove(path);
    if (db.outbox.pendingFor(
          SyncTables.noteImagesBucket,
          path,
          op: OutboxOpType.deleteImage,
        ) ==
        null) {
      await db.outbox.enqueue(
        table: SyncTables.noteImagesBucket,
        op: OutboxOpType.deleteImage,
        rowId: path,
      );
    }
  }
}

extension AttachmentDeletion on DataContext {
  /// Soft-deletes [attachment] (tombstone upsert), then queues removal of
  /// its blob (after the tombstone in the FIFO outbox) and drops the local
  /// bytes and any pending upload.
  Future<void> deleteAttachment(Attachment attachment, {DateTime? now}) async {
    final at = now ?? clock();
    final path = attachment.storagePath;
    await db.outbox.removeFor(
      SyncTables.attachmentsBucket,
      path,
      OutboxOpType.uploadAttachment,
    );
    await save(
      db.attachments,
      attachment.copyWith(deletedAt: at, updatedAt: at),
    );
    if (db.outbox.pendingFor(
          SyncTables.attachmentsBucket,
          path,
          op: OutboxOpType.deleteAttachment,
        ) ==
        null) {
      await db.outbox.enqueue(
        table: SyncTables.attachmentsBucket,
        op: OutboxOpType.deleteAttachment,
        rowId: path,
        payload: {'attachment_id': attachment.id},
      );
    }
    try {
      await db.attachmentFiles.remove(path);
    } catch (_) {
      // Best effort: a stale cache entry is only wasted space.
    }
  }
}

/// `note-image://` references in a Markdown body (deduplicated, in order).
List<NoteImageRef> noteImageRefsIn(String markdown) {
  final seen = <NoteImageRef>{};
  for (final match in _noteImagePattern.allMatches(markdown)) {
    final ref = NoteImageRef.tryParse(match.group(0)!);
    if (ref != null) seen.add(ref);
  }
  return seen.toList();
}

final RegExp _noteImagePattern = RegExp(
  '${NoteImageRef.scheme}://[^\\s)"\'<>\\]]+',
);

/// Soft-delete cascades (tombstones are upserted through the outbox).
///
/// - subject -> its notes (and their quizzes/decks/images), its quizzes, its
///   decks and its attachments (and their blobs)
/// - note -> quizzes and decks attached to it, images owned by the user in it
class CascadeDeleter {
  CascadeDeleter(this.ctx);

  final DataContext ctx;
  LocalDatabase get _db => ctx.db;

  Future<void> deleteSubject(Subject subject, String userId) async {
    final now = ctx.clock();
    for (final note in _db.notes.where((n) => n.subjectId == subject.id)) {
      if (note.isOwnedBy(userId)) await deleteNote(note, userId, now: now);
    }
    for (final quiz in _db.quizzes.where((q) => q.subjectId == subject.id)) {
      if (quiz.isOwnedBy(userId)) await deleteQuiz(quiz, now: now);
    }
    for (final deck in _db.decks.where((d) => d.subjectId == subject.id)) {
      if (deck.isOwnedBy(userId)) await deleteDeck(deck, now: now);
    }
    for (final file in _db.attachments.where(
      (a) => a.subjectId == subject.id,
    )) {
      if (file.isOwnedBy(userId)) await ctx.deleteAttachment(file, now: now);
    }
    await ctx.save(
      _db.subjects,
      subject.copyWith(deletedAt: now, updatedAt: now),
    );
  }

  Future<void> deleteNote(Note note, String userId, {DateTime? now}) async {
    final at = now ?? ctx.clock();
    for (final quiz in _db.quizzes.where((q) => q.noteId == note.id)) {
      if (quiz.isOwnedBy(userId)) await deleteQuiz(quiz, now: at);
    }
    for (final deck in _db.decks.where((d) => d.noteId == note.id)) {
      if (deck.isOwnedBy(userId)) await deleteDeck(deck, now: at);
    }
    for (final ref in noteImageRefsIn(note.contentMd)) {
      if (ref.ownerId == userId && ref.noteId == note.id) {
        await ctx.queueImageDeletion(ref);
      }
    }
    await ctx.save(_db.notes, note.copyWith(deletedAt: at, updatedAt: at));
  }

  Future<void> deleteQuiz(Quiz quiz, {DateTime? now}) async {
    final at = now ?? ctx.clock();
    await ctx.save(_db.quizzes, quiz.copyWith(deletedAt: at, updatedAt: at));
  }

  /// Soft-deletes a deck. The user's `card_reviews` for it stay (hidden
  /// while the deck is not live), as on the server.
  Future<void> deleteDeck(Deck deck, {DateTime? now}) async {
    final at = now ?? ctx.clock();
    await ctx.save(_db.decks, deck.copyWith(deletedAt: at, updatedAt: at));
  }
}

/// Converts a remote failure into a user-facing [AppException].
AppException remoteToAppException(RemoteException e) {
  switch (e.kind) {
    case RemoteErrorKind.network:
      return NetworkException(
        'You appear to be offline. Check your connection and try again.',
        cause: e,
      );
    case RemoteErrorKind.auth:
      return AppAuthException(
        'Your session has expired. Please sign in again.',
        cause: e,
      );
    case RemoteErrorKind.conflict:
      return ValidationException('That already exists.', cause: e);
    case RemoteErrorKind.permanent:
    case RemoteErrorKind.dependency:
      final code = e.code;
      if (code == '42501' || code == '403') {
        return PermissionDeniedException(
          "You don't have permission to do that.",
          cause: e,
        );
      }
      if (code == '404' || code == 'PGRST116') {
        return NotFoundException('That item could not be found.', cause: e);
      }
      if (code == 'P0001' && e.message.isNotEmpty) {
        // Raised explicitly by our SQL functions with a readable message.
        return ValidationException(e.message, cause: e);
      }
      return ValidationException('The server rejected the request.', cause: e);
    case RemoteErrorKind.schemaOutdated:
      return UnknownException(
        'The server database needs an update (run the latest Supabase '
        'migration).',
        cause: e,
      );
    case RemoteErrorKind.transient:
      return UnknownException(
        'Something went wrong on the server. Please try again.',
        cause: e,
      );
  }
}
