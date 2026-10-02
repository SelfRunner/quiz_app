// In-memory fakes for UI widget tests (auth/subjects/notes/settings).
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/misc.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quiz_app/ai/ai_providers.dart';
import 'package:quiz_app/ai/ai_service.dart';
import 'package:quiz_app/ai/api_key_store.dart';
import 'package:quiz_app/ai/llm_provider.dart';
import 'package:quiz_app/core/errors/app_exception.dart';
import 'package:quiz_app/data/data_providers.dart';
import 'package:quiz_app/data/models/models.dart';
import 'package:quiz_app/data/repositories/attachment_repository.dart';
import 'package:quiz_app/data/repositories/auth_repository.dart';
import 'package:quiz_app/data/repositories/image_store.dart';
import 'package:quiz_app/data/repositories/note_repository.dart';
import 'package:quiz_app/data/repositories/quiz_repository.dart';
import 'package:quiz_app/data/repositories/subject_repository.dart';
import 'package:quiz_app/data/sync/sync_engine.dart';

const String kUserId = 'user-1';
final DateTime kNow = DateTime.utc(2026, 1, 1, 12);

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository([this._user]);

  AppUser? _user;
  final _changes = StreamController<AppUser?>.broadcast();

  /// Error thrown by signIn/signUp/resetPassword when set.
  Object? error;

  /// Whether signUp yields a session (false = email confirmation needed).
  bool signUpCreatesSession = false;

  final List<String> calls = [];

  @override
  AppUser? get currentUser => _user;

  @override
  Stream<AppUser?> authStateChanges() async* {
    yield _user;
    yield* _changes.stream;
  }

  @override
  Future<void> signIn({required String email, required String password}) async {
    calls.add('signIn:$email');
    if (error != null) throw error!;
    _user = AppUser(id: kUserId, email: email);
    _changes.add(_user);
  }

  @override
  Future<void> signUp({
    required String email,
    required String password,
    String? displayName,
  }) async {
    calls.add('signUp:$email:$displayName');
    if (error != null) throw error!;
    if (signUpCreatesSession) {
      _user = AppUser(id: kUserId, email: email, displayName: displayName);
      _changes.add(_user);
    }
  }

  @override
  Future<void> signOut() async {
    calls.add('signOut');
    _user = null;
    _changes.add(null);
  }

  @override
  Future<void> resetPassword(String email) async {
    calls.add('reset:$email');
    if (error != null) throw error!;
  }
}

/// Minimal reactive in-memory table.
class _Table<T> {
  final Map<String, T> rows = {};
  final _changes = StreamController<void>.broadcast();

  Stream<R> watch<R>(R Function() read) async* {
    yield read();
    yield* _changes.stream.map((_) => read());
  }

  void put(String id, T row) {
    rows[id] = row;
    _changes.add(null);
  }

  void remove(String id) {
    rows.remove(id);
    _changes.add(null);
  }
}

class FakeSubjectRepository implements SubjectRepository {
  final _t = _Table<Subject>();
  int _n = 0;
  final List<Subject> created = [];

  Subject seed({
    String? id,
    String title = 'Biology',
    String? description,
    int? color,
    String ownerId = kUserId,
  }) {
    final s = Subject(
      id: id ?? 's${++_n}',
      ownerId: ownerId,
      title: title,
      description: description,
      color: color,
      createdAt: kNow,
      updatedAt: kNow,
    );
    _t.put(s.id, s);
    return s;
  }

  List<Subject> get _own =>
      _t.rows.values.where((s) => s.ownerId == kUserId).toList()
        ..sort((a, b) => a.title.compareTo(b.title));

  @override
  Stream<List<Subject>> watchAll() => _t.watch(() => _own);

  @override
  Stream<Subject?> watchById(String id) => _t.watch(() => _t.rows[id]);

  @override
  Future<Subject?> getById(String id) async => _t.rows[id];

  @override
  Future<Subject> create({
    required String title,
    String? description,
    int? color,
  }) async {
    final s = seed(title: title, description: description, color: color);
    created.add(s);
    return s;
  }

  @override
  Future<Subject> update(Subject subject) async {
    _t.put(subject.id, subject);
    return subject;
  }

  @override
  Future<void> delete(String id) async => _t.remove(id);
}

class FakeNoteRepository implements NoteRepository {
  final _t = _Table<Note>();
  int _n = 0;
  final List<Note> updates = [];
  final List<String> deleted = [];

  Note seed({
    String? id,
    String subjectId = 's1',
    String title = 'Cells',
    String contentMd = '',
    String ownerId = kUserId,
    DateTime? updatedAt,
  }) {
    final n = Note(
      id: id ?? 'n${++_n}',
      subjectId: subjectId,
      ownerId: ownerId,
      title: title,
      contentMd: contentMd,
      createdAt: kNow,
      updatedAt: updatedAt ?? kNow,
    );
    _t.put(n.id, n);
    return n;
  }

  @override
  Stream<List<Note>> watchBySubject(String subjectId) => _t.watch(
    () => _t.rows.values.where((n) => n.subjectId == subjectId).toList(),
  );

  @override
  Stream<List<Note>> watchAllAccessible() =>
      _t.watch(() => _t.rows.values.toList());

  @override
  Stream<Note?> watchById(String id) => _t.watch(() => _t.rows[id]);

  @override
  Future<Note?> getById(String id) async => _t.rows[id];

  @override
  Future<Note> create({
    required String subjectId,
    required String title,
    String contentMd = '',
  }) async => seed(subjectId: subjectId, title: title, contentMd: contentMd);

  @override
  Future<Note> update(Note note) async {
    final saved = note.copyWith(
      updatedAt: note.updatedAt.add(const Duration(seconds: 1)),
    );
    updates.add(saved);
    _t.put(note.id, saved);
    return saved;
  }

  @override
  Future<void> delete(String id) async {
    deleted.add(id);
    _t.remove(id);
  }
}

class FakeQuizRepository implements QuizRepository {
  @override
  Stream<List<Quiz>> watchBySubject(String subjectId) => Stream.value([]);

  @override
  Stream<List<Quiz>> watchByNote(String noteId) => Stream.value([]);

  @override
  Stream<Quiz?> watchById(String id) => Stream.value(null);

  @override
  Future<Quiz?> getById(String id) async => null;

  @override
  Future<Quiz> create({
    required String subjectId,
    String? noteId,
    required String title,
    String? description,
    List<Question> questions = const [],
    QuizSource? source,
  }) => throw UnimplementedError();

  @override
  Future<Quiz> update(Quiz quiz) => throw UnimplementedError();

  @override
  Future<void> delete(String id) async {}
}

class FakeSyncEngine implements SyncEngine {
  int syncCalls = 0;

  @override
  SyncStatus currentStatus = SyncStatus(lastSyncedAt: kNow);

  @override
  Stream<SyncStatus> get status => Stream.value(currentStatus);

  @override
  void start() {}

  @override
  Future<void> sync() async => syncCalls++;

  @override
  Future<void> dispose() async {}
}

class FakeImageStore implements ImageStore {
  final Map<String, Uint8List> saved = {};

  @override
  Future<NoteImageRef> saveNoteImage({
    required String noteId,
    required Uint8List bytes,
    required String extension,
  }) async {
    final ref = NoteImageRef(
      ownerId: kUserId,
      noteId: noteId,
      fileName: 'img${saved.length + 1}.$extension',
    );
    saved[ref.storagePath] = bytes;
    return ref;
  }

  @override
  Future<Uint8List?> load(NoteImageRef ref) async => saved[ref.storagePath];

  @override
  Future<void> delete(NoteImageRef ref) async => saved.remove(ref.storagePath);
}

class FakeApiKeyStore implements ApiKeyStore {
  final Map<LlmProviderId, String> keys = {};

  /// Manual capability overrides by `'{provider.wireName}/{model}'`.
  final Map<String, Set<AiInputKind>> overrides = {};

  @override
  Future<Set<AiInputKind>> getInputOverride(
    LlmProviderId provider,
    String model,
  ) async => overrides['${provider.wireName}/$model'] ?? const {};

  @override
  Future<void> setInputOverride(
    LlmProviderId provider,
    String model,
    Set<AiInputKind> kinds,
  ) async {
    final key = '${provider.wireName}/$model';
    if (kinds.isEmpty) {
      overrides.remove(key);
    } else {
      overrides[key] = {...kinds};
    }
  }

  final Map<LlmProviderId, String> models = {};
  final Map<LlmProviderId, String> baseUrls = {};
  final Map<LlmProviderId, Map<String, String>> headers = {};
  LlmProviderId? selected;

  @override
  Future<String?> getApiKey(LlmProviderId provider) async => keys[provider];

  @override
  Future<void> setApiKey(LlmProviderId provider, String apiKey) async {
    if (apiKey.trim().isEmpty) {
      keys.remove(provider);
    } else {
      keys[provider] = apiKey.trim();
    }
  }

  @override
  Future<void> deleteApiKey(LlmProviderId provider) async =>
      keys.remove(provider);

  @override
  Future<String?> getBaseUrl(LlmProviderId provider) async =>
      baseUrls[provider];

  @override
  Future<void> setBaseUrl(LlmProviderId provider, String? baseUrl) async {
    if (baseUrl == null || baseUrl.isEmpty) {
      baseUrls.remove(provider);
    } else {
      baseUrls[provider] = baseUrl;
    }
  }

  @override
  Future<LlmProviderId?> getSelectedProvider() async => selected;

  @override
  Future<void> setSelectedProvider(LlmProviderId provider) async =>
      selected = provider;

  @override
  Future<String?> getSelectedModel(LlmProviderId provider) async =>
      models[provider];

  @override
  Future<void> setSelectedModel(LlmProviderId provider, String model) async =>
      models[provider] = model;

  @override
  Future<Map<String, String>> getExtraHeaders(LlmProviderId provider) async =>
      headers[provider] ?? const {};

  @override
  Future<void> setExtraHeaders(
    LlmProviderId provider,
    Map<String, String> value,
  ) async => headers[provider] = value;


  @override
  Future<Set<LlmProviderId>> configuredProviders() async => keys.keys.toSet();

  final List<String> clearedUsers = [];

  void _clear() {
    keys.clear();
    models.clear();
    baseUrls.clear();
    headers.clear();
    overrides.clear();
    selected = null;
  }

  @override
  Future<void> clearForUser(String userId) async {
    clearedUsers.add(userId);
    _clear();
  }

  @override
  Future<void> clearAll() async => _clear();
}

class FakeAiService implements AiService {
  List<String> models = ['model-a', 'model-b'];
  Object? testError;
  final List<String?> testedKeys = [];

  @override
  Future<List<String>> listModels(
    LlmProviderId provider, {
    String? apiKey,
    String? baseUrl,
    Map<String, String>? extraHeaders,
  }) async => models;

  @override
  Future<void> testConnection(
    LlmProviderId provider, {
    String? apiKey,
    String? baseUrl,
    Map<String, String>? extraHeaders,
  }) async {
    testedKeys.add(apiKey);
    if (testError != null) throw testError!;
  }

  @override
  Future<AiSelection> resolveSelection({
    LlmProviderId? providerId,
    String? model,
  }) async => AiSelection(
    providerId: providerId ?? LlmProviderId.gemini,
    model: model ?? 'model-a',
  );

  @override
  Future<QuizDraft> generateQuiz(QuizGenerationRequest request) =>
      throw UnimplementedError();

  @override
  Future<NoteDraft> generateNote(NoteGenerationRequest request) =>
      throw UnimplementedError();

  @override
  Future<T> generateStructured<T>(
    StructuredGenerationRequest request, {
    required DraftValidation<T> Function(Map<String, dynamic> json) validate,
    String what = 'result',
  }) => throw UnimplementedError();
}

class FakeAttachmentRepository implements AttachmentRepository {
  final _t = _Table<Attachment>();
  final Map<String, Uint8List> bytes = {};
  final Map<String, AttachmentUploadState> uploads = {};
  final List<Attachment> added = [];
  final List<String> deleted = [];
  int _n = 0;

  /// Thrown by [add] when set.
  Object? addError;

  Attachment seed({
    String? id,
    String subjectId = 's1',
    String name = 'slides.pdf',
    int sizeBytes = 2048,
    String ownerId = kUserId,
    String? extractedText,
    Uint8List? data,
  }) {
    final aid = id ?? 'a${++_n}';
    final a = Attachment(
      id: aid,
      subjectId: subjectId,
      ownerId: ownerId,
      name: name,
      mimeType: mimeTypeForFileName(name),
      sizeBytes: sizeBytes,
      kind: AttachmentKind.detect(fileName: name),
      storagePath: Attachment.buildStoragePath(
        ownerId: ownerId,
        subjectId: subjectId,
        id: aid,
        fileName: name,
      ),
      extractedText: extractedText,
      createdAt: kNow,
      updatedAt: kNow,
    );
    if (data != null) bytes[aid] = data;
    _t.put(aid, a);
    return a;
  }

  @override
  Stream<List<Attachment>> watchBySubject(String subjectId) => _t.watch(
    () => _t.rows.values.where((a) => a.subjectId == subjectId).toList(),
  );

  @override
  Stream<List<Attachment>> watchAllAccessible() =>
      _t.watch(() => _t.rows.values.toList());

  @override
  Stream<Attachment?> watchById(String id) => _t.watch(() => _t.rows[id]);

  @override
  Future<Attachment?> getById(String id) async => _t.rows[id];

  @override
  Future<Attachment> add({
    required String subjectId,
    required String name,
    String? mimeType,
    required Uint8List bytes,
    String? extractedText,
  }) async {
    if (addError != null) throw addError!;
    final a = seed(
      subjectId: subjectId,
      name: name,
      sizeBytes: bytes.lengthInBytes,
      extractedText: extractedText,
      data: bytes,
    );
    added.add(a);
    return a;
  }

  @override
  Future<Attachment> update(Attachment attachment) async {
    _t.put(attachment.id, attachment);
    return attachment;
  }

  @override
  Future<Attachment> rename(String id, String name) async {
    final a = _t.rows[id]!.copyWith(name: name);
    _t.put(id, a);
    return a;
  }

  @override
  Future<void> delete(String id) async {
    deleted.add(id);
    _t.remove(id);
  }

  @override
  Future<Uint8List> getBytes(Attachment attachment) async {
    final data = bytes[attachment.id];
    if (data == null) {
      throw const NotFoundException('This file is not available.');
    }
    return data;
  }

  @override
  Future<bool> isCached(Attachment attachment) async =>
      bytes.containsKey(attachment.id);

  @override
  Stream<AttachmentUploadState> watchUpload(Attachment attachment) =>
      Stream.value(uploads[attachment.id] ?? AttachmentUploadState.done);
}

/// Answers every AI HTTP call (e.g. OpenRouter `/models`) with
/// [FakeAiHttp.models] or 404.
class FakeAiHttp {
  /// OpenRouter model id -> `input_modalities`.
  final Map<String, List<String>> models = {};

  http.Client get client => MockClient((request) async {
    if (request.url.path.endsWith('/models') && models.isNotEmpty) {
      return http.Response(
        jsonEncode({
          'data': [
            for (final e in models.entries)
              {
                'id': e.key,
                'architecture': {'input_modalities': e.value},
              },
          ],
        }),
        200,
      );
    }
    return http.Response('not found', 404);
  });
}

/// Bundle of fakes + the matching provider overrides.
class TestDeps {
  TestDeps({AppUser? user})
    : auth = FakeAuthRepository(user ?? const AppUser(id: kUserId));

  final FakeAuthRepository auth;
  final subjects = FakeSubjectRepository();
  final notes = FakeNoteRepository();
  final quizzes = FakeQuizRepository();
  final sync = FakeSyncEngine();
  final images = FakeImageStore();
  final keys = FakeApiKeyStore();
  final ai = FakeAiService();
  final attachments = FakeAttachmentRepository();
  final aiHttp = FakeAiHttp();
  final List<Share> shares = [];

  /// Stores a Gemini key so AI entry points are unlocked.
  void configureAi() => keys
    ..keys[LlmProviderId.gemini] = 'test-key'
    ..selected = LlmProviderId.gemini;

  List<Override> get overrides => [
    authRepositoryProvider.overrideWithValue(auth),
    subjectRepositoryProvider.overrideWithValue(subjects),
    noteRepositoryProvider.overrideWithValue(notes),
    quizRepositoryProvider.overrideWithValue(quizzes),
    syncEngineProvider.overrideWithValue(sync),
    imageStoreProvider.overrideWithValue(images),
    apiKeyStoreProvider.overrideWithValue(keys),
    aiServiceProvider.overrideWithValue(ai),
    aiHttpClientProvider.overrideWithValue(aiHttp.client),
    attachmentRepositoryProvider.overrideWithValue(attachments),
    sharedWithMeProvider.overrideWith((ref) async => shares),
  ];
}
