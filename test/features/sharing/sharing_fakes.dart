import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:quiz_app/core/errors/app_exception.dart';
import 'package:quiz_app/data/data_providers.dart';
import 'package:quiz_app/data/models/models.dart';
import 'package:quiz_app/data/repositories/auth_repository.dart';
import 'package:quiz_app/data/repositories/note_repository.dart';
import 'package:quiz_app/data/repositories/quiz_repository.dart';
import 'package:quiz_app/data/repositories/share_repository.dart';
import 'package:quiz_app/data/repositories/subject_repository.dart';
import 'package:quiz_app/data/sync/sync_engine.dart';

const meId = 'me';
const meEmail = 'me@example.com';
final t0 = DateTime.utc(2026, 9, 1, 12);

Profile profile(String id, {String? name, String? email}) =>
    Profile(id: id, displayName: name, email: email ?? '$id@example.com');

Share makeShare({
  required String id,
  required ShareResourceType type,
  required String resourceId,
  String ownerId = 'alice',
  String recipientId = meId,
  Profile? owner,
  Profile? recipient,
  String? title,
  DateTime? createdAt,
}) => Share(
  id: id,
  ownerId: ownerId,
  recipientId: recipientId,
  resourceType: type,
  resourceId: resourceId,
  createdAt: createdAt ?? t0,
  owner: owner,
  recipient: recipient,
  resourceTitle: title,
);

Subject makeSubject(String id, String title, {String ownerId = meId}) =>
    Subject(
      id: id,
      ownerId: ownerId,
      title: title,
      createdAt: t0,
      updatedAt: t0,
    );

Note makeNote(String id, String subjectId, {String ownerId = 'alice'}) => Note(
  id: id,
  subjectId: subjectId,
  ownerId: ownerId,
  title: 'Note $id',
  createdAt: t0,
  updatedAt: t0,
);

Quiz makeQuiz(
  String id,
  String subjectId, {
  String? noteId,
  String ownerId = 'alice',
  int questions = 0,
}) => Quiz(
  id: id,
  subjectId: subjectId,
  noteId: noteId,
  ownerId: ownerId,
  title: 'Quiz $id',
  questions: [
    for (var i = 0; i < questions; i++)
      Question(
        id: 'q$i',
        type: QuestionType.trueFalse,
        prompt: 'P$i',
        options: const ['True', 'False'],
        correctIndices: const [0],
      ),
  ],
  createdAt: t0,
  updatedAt: t0,
);

class FakeShareRepository implements ShareRepository {
  final Map<String, Profile> usersByEmail = {};
  final Map<String, List<Share>> sharesByResource = {};
  List<Share> received = [];
  Object? listError;
  Object? sharedWithMeError;
  Object? copyError;
  String copyResultId = 'copy-1';

  final List<String> revoked = [];
  final List<({ShareResourceType type, String id, String? subjectId})> copies =
      [];
  int sharedWithMeCalls = 0;
  int _seq = 0;

  @override
  Future<Profile?> findUserByEmail(String email) async =>
      usersByEmail[email.trim().toLowerCase()];

  @override
  Future<Share> share({
    required ShareResourceType resourceType,
    required String resourceId,
    required String recipientId,
  }) async {
    if (recipientId == meId) {
      throw const ValidationException("You can't share with yourself.");
    }
    if ((sharesByResource[resourceId] ?? const <Share>[]).any(
      (s) => s.recipientId == recipientId,
    )) {
      // Mirrors the unique violation (23505) mapping of the real repository.
      throw const AlreadySharedException(
        'This item is already shared with that person.',
      );
    }
    final recipient = usersByEmail.values.firstWhere(
      (p) => p.id == recipientId,
    );
    final share = makeShare(
      id: 'share-${++_seq}',
      type: resourceType,
      resourceId: resourceId,
      ownerId: meId,
      recipientId: recipientId,
      recipient: recipient,
    );
    sharesByResource.putIfAbsent(resourceId, () => []).add(share);
    return share;
  }

  @override
  Future<void> revoke(String shareId) async {
    revoked.add(shareId);
    for (final list in sharesByResource.values) {
      list.removeWhere((s) => s.id == shareId);
    }
  }

  @override
  Future<List<Share>> listSharesFor(
    ShareResourceType resourceType,
    String resourceId,
  ) async {
    if (listError != null) throw listError!;
    return [...?sharesByResource[resourceId]];
  }

  @override
  Future<List<Share>> sharedWithMe() async {
    sharedWithMeCalls++;
    if (sharedWithMeError != null) throw sharedWithMeError!;
    return received;
  }

  @override
  Future<String> copyToMyAccount({
    required ShareResourceType resourceType,
    required String resourceId,
    String? targetSubjectId,
    String? targetNoteId,
  }) async {
    copies.add((
      type: resourceType,
      id: resourceId,
      subjectId: targetSubjectId,
    ));
    if (copyError != null) throw copyError!;
    return copyResultId;
  }
}

class FakeAuthRepository implements AuthRepository {
  @override
  AppUser? get currentUser => const AppUser(id: meId, email: meEmail);

  @override
  Stream<AppUser?> authStateChanges() => Stream.value(currentUser);

  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSubjectRepository implements SubjectRepository {
  FakeSubjectRepository(List<Subject> initial) : _subjects = [...initial];

  final List<Subject> _subjects;
  final _changes = StreamController<void>.broadcast();
  final List<String> created = [];

  @override
  Stream<List<Subject>> watchAll() async* {
    yield [..._subjects.where((s) => s.ownerId == meId)];
    await for (final _ in _changes.stream) {
      yield [..._subjects.where((s) => s.ownerId == meId)];
    }
  }

  @override
  Stream<Subject?> watchById(String id) => Stream.value(_find(id));

  @override
  Future<Subject?> getById(String id) async => _find(id);

  Subject? _find(String id) {
    for (final s in _subjects) {
      if (s.id == id) return s;
    }
    return null;
  }

  @override
  Future<Subject> create({
    required String title,
    String? description,
    int? color,
  }) async {
    final s = makeSubject('new-subject', title);
    _subjects.add(s);
    created.add(title);
    _changes.add(null);
    return s;
  }

  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeNoteRepository implements NoteRepository {
  FakeNoteRepository(this.notes);

  final List<Note> notes;

  @override
  Stream<List<Note>> watchBySubject(String subjectId) =>
      Stream.value(notes.where((n) => n.subjectId == subjectId).toList());

  @override
  Stream<Note?> watchById(String id) => Stream.value(_find(id));

  @override
  Future<Note?> getById(String id) async => _find(id);

  Note? _find(String id) {
    for (final n in notes) {
      if (n.id == id) return n;
    }
    return null;
  }

  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeQuizRepository implements QuizRepository {
  FakeQuizRepository(this.quizzes);

  final List<Quiz> quizzes;

  @override
  Stream<List<Quiz>> watchBySubject(String subjectId) =>
      Stream.value(quizzes.where((q) => q.subjectId == subjectId).toList());

  @override
  Stream<List<Quiz>> watchByNote(String noteId) =>
      Stream.value(quizzes.where((q) => q.noteId == noteId).toList());

  @override
  Stream<Quiz?> watchById(String id) => Stream.value(_find(id));

  @override
  Future<Quiz?> getById(String id) async => _find(id);

  Quiz? _find(String id) {
    for (final q in quizzes) {
      if (q.id == id) return q;
    }
    return null;
  }

  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSyncEngine implements SyncEngine {
  FakeSyncEngine([this._status = const SyncStatus()]);

  final SyncStatus _status;
  int syncCalls = 0;

  @override
  Stream<SyncStatus> get status => Stream.value(_status);

  @override
  SyncStatus get currentStatus => _status;

  @override
  void start() {}

  @override
  Future<void> sync() async => syncCalls++;

  @override
  Future<void> dispose() async {}
}

/// App harness with a minimal router: `/` shows [home]; detail routes show
/// `subject:<id>`, `note:<id>`, `quiz:<id>` texts.
Widget harness({
  required Widget home,
  FakeShareRepository? shares,
  FakeSubjectRepository? subjects,
  FakeNoteRepository? notes,
  FakeQuizRepository? quizzes,
  FakeSyncEngine? engine,
}) {
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => home),
      GoRoute(
        path: '/subjects/:id',
        builder: (_, s) =>
            Scaffold(body: Text('subject:${s.pathParameters['id']}')),
      ),
      GoRoute(
        path: '/notes/:id',
        builder: (_, s) =>
            Scaffold(body: Text('note:${s.pathParameters['id']}')),
      ),
      GoRoute(
        path: '/quizzes/:id',
        builder: (_, s) =>
            Scaffold(body: Text('quiz:${s.pathParameters['id']}')),
      ),
    ],
  );
  return ProviderScope(
    retry: (_, _) => null,
    overrides: [
      authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
      shareRepositoryProvider.overrideWithValue(
        shares ?? FakeShareRepository(),
      ),
      subjectRepositoryProvider.overrideWithValue(
        subjects ?? FakeSubjectRepository(const []),
      ),
      noteRepositoryProvider.overrideWithValue(
        notes ?? FakeNoteRepository(const []),
      ),
      quizRepositoryProvider.overrideWithValue(
        quizzes ?? FakeQuizRepository(const []),
      ),
      syncEngineProvider.overrideWithValue(engine ?? FakeSyncEngine()),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}
