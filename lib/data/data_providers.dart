import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import 'local/local_database.dart';
import 'models/models.dart';
import 'remote/remote_data_source.dart';
import 'remote/supabase_remote_data_source.dart';
import 'repositories/attachment_repository.dart';
import 'repositories/attempt_repository.dart';
import 'repositories/auth_repository.dart';
import 'repositories/image_store.dart';
import 'repositories/local_attachment_repository.dart';
import 'repositories/local_attempt_repository.dart';
import 'repositories/local_image_store.dart';
import 'repositories/local_note_repository.dart';
import 'repositories/local_quiz_repository.dart';
import 'repositories/local_subject_repository.dart';
import 'repositories/note_repository.dart';
import 'repositories/note_search.dart';
import 'repositories/quiz_repository.dart';
import 'repositories/repository_support.dart';
import 'repositories/share_repository.dart';
import 'repositories/subject_repository.dart';
import 'repositories/supabase_auth_repository.dart';
import 'repositories/supabase_share_repository.dart';
import 'sync/connectivity_monitor.dart';
import 'sync/default_sync_engine.dart';
import 'sync/note_image_copy_processor.dart';
import 'sync/sync_engine.dart';

// ---------------------------------------------------------------------------
// Infrastructure (data layer internals; override these in tests).
// ---------------------------------------------------------------------------

/// Hive-backed local database (boxes opened by `HiveBoxes.init`).
final localDatabaseProvider = Provider<LocalDatabase>(
  (ref) => LocalDatabase.fromOpenBoxes(
    clock: ref.watch(clockProvider),
    newId: ref.watch(idGeneratorProvider),
  ),
);

final supabaseRemoteDataSourceProvider = Provider<SupabaseRemoteDataSource>(
  (ref) => SupabaseRemoteDataSource(ref.watch(supabaseClientProvider)),
);

final syncRemoteDataSourceProvider = Provider<SyncRemoteDataSource>(
  (ref) => ref.watch(supabaseRemoteDataSourceProvider),
);

final imageRemoteDataSourceProvider = Provider<ImageRemoteDataSource>(
  (ref) => ref.watch(supabaseRemoteDataSourceProvider),
);

final shareRemoteDataSourceProvider = Provider<ShareRemoteDataSource>(
  (ref) => ref.watch(supabaseRemoteDataSourceProvider),
);

final connectivityMonitorProvider = Provider<ConnectivityMonitor>(
  (ref) => ConnectivityPlusMonitor(),
);

/// Shared repository plumbing. Watching it also creates (and starts) the
/// sync engine, so using any repository activates sync triggers.
final dataContextProvider = Provider<DataContext>((ref) {
  ref.watch(syncEngineProvider);
  final auth = ref.watch(authRepositoryProvider);
  return DataContext(
    db: ref.watch(localDatabaseProvider),
    clock: ref.watch(clockProvider),
    newId: ref.watch(idGeneratorProvider),
    currentUserId: () => auth.currentUser?.id,
  );
});

// ---------------------------------------------------------------------------
// Service providers (features only depend on the interfaces).
// ---------------------------------------------------------------------------

final Provider<AuthRepository> authRepositoryProvider =
    Provider<AuthRepository>(
      (ref) => SupabaseAuthRepository(
        ref.watch(supabaseClientProvider),
        // Push pending changes before local data is wiped on sign-out.
        beforeSignOut: () => ref.read(syncEngineProvider).sync(),
        // Explicit sign-out only: wipe user-scoped local data. Involuntary
        // sign-outs (expired/revoked session) keep it for the same user.
        afterSignOut: () {
          final engine = ref.read(syncEngineProvider);
          return engine is DefaultSyncEngine
              ? engine.clearAfterSignOut()
              : ref.read(localDatabaseProvider).clearUserData();
        },
      ),
    );

final subjectRepositoryProvider = Provider<SubjectRepository>(
  (ref) => LocalSubjectRepository(ref.watch(dataContextProvider)),
);

final noteRepositoryProvider = Provider<NoteRepository>(
  (ref) => LocalNoteRepository(ref.watch(dataContextProvider)),
);

final quizRepositoryProvider = Provider<QuizRepository>(
  (ref) => LocalQuizRepository(ref.watch(dataContextProvider)),
);

final attemptRepositoryProvider = Provider<AttemptRepository>(
  (ref) => LocalAttemptRepository(ref.watch(dataContextProvider)),
);

final shareRepositoryProvider = Provider<ShareRepository>((ref) {
  final engine = ref.watch(syncEngineProvider);
  final imageCopies = engine is DefaultSyncEngine
      ? engine.imageCopies
      : NoteImageCopyProcessor(
          ref.watch(imageRemoteDataSourceProvider),
          ref.watch(localDatabaseProvider).images,
          attachmentCache: ref.watch(localDatabaseProvider).attachmentFiles,
        );
  return SupabaseShareRepository(
    ctx: ref.watch(dataContextProvider),
    remote: ref.watch(shareRemoteDataSourceProvider),
    imageCopies: imageCopies,
    connectivity: ref.watch(connectivityMonitorProvider),
    sync: engine is DefaultSyncEngine ? engine.syncFresh : engine.sync,
  );
});

final imageStoreProvider = Provider<ImageStore>(
  (ref) => LocalImageStore(
    ref.watch(dataContextProvider),
    ref.watch(imageRemoteDataSourceProvider),
  ),
);

/// Subject attachments ("Files" library).
final attachmentRepositoryProvider = Provider<AttachmentRepository>(
  (ref) => LocalAttachmentRepository(
    ref.watch(dataContextProvider),
    ref.watch(imageRemoteDataSourceProvider),
  ),
);

/// The sync engine, created and started on first read (also by any
/// repository). Lives for the app's lifetime.
final Provider<SyncEngine> syncEngineProvider = Provider<SyncEngine>((ref) {
  final auth = ref.watch(authRepositoryProvider);
  final engine = DefaultSyncEngine(
    db: ref.watch(localDatabaseProvider),
    remote: ref.watch(syncRemoteDataSourceProvider),
    imageRemote: ref.watch(imageRemoteDataSourceProvider),
    currentUserId: () => auth.currentUser?.id,
    userChanges: auth.authStateChanges().map((u) => u?.id),
    connectivity: ref.watch(connectivityMonitorProvider),
    foregroundChanges: appForegroundChanges(),
    clock: ref.watch(clockProvider),
  )..start();
  ref.onDispose(() => unawaited(engine.dispose()));
  return engine;
});

// ---------------------------------------------------------------------------
// Auth state
// ---------------------------------------------------------------------------

/// Signed-in user (null when signed out).
final authStateProvider = StreamProvider<AppUser?>(
  (ref) => ref.watch(authRepositoryProvider).authStateChanges(),
);

/// Current user id, or null. Synchronous convenience for ownership checks.
final currentUserIdProvider = Provider<String?>(
  (ref) =>
      ref.watch(authStateProvider).value?.id ??
      ref.watch(authRepositoryProvider).currentUser?.id,
);

// ---------------------------------------------------------------------------
// Query providers (thin wrappers around repository streams) for features.
// ---------------------------------------------------------------------------

final subjectsProvider = StreamProvider.autoDispose<List<Subject>>(
  (ref) => ref.watch(subjectRepositoryProvider).watchAll(),
);

final subjectProvider = StreamProvider.autoDispose.family<Subject?, String>(
  (ref, id) => ref.watch(subjectRepositoryProvider).watchById(id),
);

final notesBySubjectProvider = StreamProvider.autoDispose
    .family<List<Note>, String>(
      (ref, subjectId) =>
          ref.watch(noteRepositoryProvider).watchBySubject(subjectId),
    );

final noteProvider = StreamProvider.autoDispose.family<Note?, String>(
  (ref, id) => ref.watch(noteRepositoryProvider).watchById(id),
);

final quizzesBySubjectProvider = StreamProvider.autoDispose
    .family<List<Quiz>, String>(
      (ref, subjectId) =>
          ref.watch(quizRepositoryProvider).watchBySubject(subjectId),
    );

final quizzesByNoteProvider = StreamProvider.autoDispose
    .family<List<Quiz>, String>(
      (ref, noteId) => ref.watch(quizRepositoryProvider).watchByNote(noteId),
    );

final quizProvider = StreamProvider.autoDispose.family<Quiz?, String>(
  (ref, id) => ref.watch(quizRepositoryProvider).watchById(id),
);

final attemptsByQuizProvider = StreamProvider.autoDispose
    .family<List<QuizAttempt>, String>(
      (ref, quizId) => ref.watch(attemptRepositoryProvider).watchByQuiz(quizId),
    );

/// Every note the user can read (own + shared), `updatedAt` desc. For the
/// note picker.
final accessibleNotesProvider = StreamProvider.autoDispose<List<Note>>(
  (ref) => ref.watch(noteRepositoryProvider).watchAllAccessible(),
);

/// [accessibleNotesProvider] filtered by a search query (title + content,
/// case-insensitive, all whitespace-separated terms; title hits first).
final noteSearchProvider = Provider.autoDispose
    .family<AsyncValue<List<Note>>, String>(
      (ref, query) => ref
          .watch(accessibleNotesProvider)
          .whenData((notes) => searchNotes(notes, query)),
    );

/// Live attachments of a subject (own or shared), newest first.
final attachmentsForSubjectProvider = StreamProvider.autoDispose
    .family<List<Attachment>, String>(
      (ref, subjectId) =>
          ref.watch(attachmentRepositoryProvider).watchBySubject(subjectId),
    );

/// Every attachment the user can read (own + shared subjects), newest first.
final accessibleAttachmentsProvider =
    StreamProvider.autoDispose<List<Attachment>>(
      (ref) => ref.watch(attachmentRepositoryProvider).watchAllAccessible(),
    );

final attachmentProvider = StreamProvider.autoDispose
    .family<Attachment?, String>(
      (ref, id) => ref.watch(attachmentRepositoryProvider).watchById(id),
    );

/// Upload state of an attachment's blob by attachment id (queued /
/// uploading / retrying / done; `done` for unknown ids).
final attachmentUploadProvider = StreamProvider.autoDispose
    .family<AttachmentUploadState, String>((ref, id) async* {
      final repo = ref.watch(attachmentRepositoryProvider);
      final attachment = await repo.getById(id);
      if (attachment == null) {
        yield AttachmentUploadState.done;
        return;
      }
      yield* repo.watchUpload(attachment);
    });

/// Shares the current user received. `ref.invalidate` to refresh.
final sharedWithMeProvider = FutureProvider.autoDispose<List<Share>>(
  (ref) => ref.watch(shareRepositoryProvider).sharedWithMe(),
);

/// Shares the current user created for one resource.
final sharesForResourceProvider = FutureProvider.autoDispose
    .family<List<Share>, ({ShareResourceType type, String id})>(
      (ref, key) =>
          ref.watch(shareRepositoryProvider).listSharesFor(key.type, key.id),
    );

/// Sync status for UI indicators.
final syncStatusProvider = StreamProvider<SyncStatus>(
  (ref) => ref.watch(syncEngineProvider).status,
);
