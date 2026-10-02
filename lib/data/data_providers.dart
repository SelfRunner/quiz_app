import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import 'models/models.dart';
import 'repositories/attempt_repository.dart';
import 'repositories/auth_repository.dart';
import 'repositories/image_store.dart';
import 'repositories/note_repository.dart';
import 'repositories/quiz_repository.dart';
import 'repositories/share_repository.dart';
import 'repositories/subject_repository.dart';
import 'repositories/supabase_auth_repository.dart';
import 'sync/sync_engine.dart';

// ---------------------------------------------------------------------------
// Service providers. The data/sync agent replaces the `throw` bodies with real
// implementations; features only depend on the interfaces.
// ---------------------------------------------------------------------------

Never _unimplemented(String name) =>
    throw UnimplementedError('$name is not implemented yet (data layer).');

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => SupabaseAuthRepository(ref.watch(supabaseClientProvider)),
);

final subjectRepositoryProvider = Provider<SubjectRepository>(
  (ref) => _unimplemented('SubjectRepository'),
);

final noteRepositoryProvider = Provider<NoteRepository>(
  (ref) => _unimplemented('NoteRepository'),
);

final quizRepositoryProvider = Provider<QuizRepository>(
  (ref) => _unimplemented('QuizRepository'),
);

final attemptRepositoryProvider = Provider<AttemptRepository>(
  (ref) => _unimplemented('AttemptRepository'),
);

final shareRepositoryProvider = Provider<ShareRepository>(
  (ref) => _unimplemented('ShareRepository'),
);

final imageStoreProvider = Provider<ImageStore>(
  (ref) => _unimplemented('ImageStore'),
);

final syncEngineProvider = Provider<SyncEngine>(
  (ref) => _unimplemented('SyncEngine'),
);

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
