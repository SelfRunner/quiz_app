# Contracts (Phase 0 foundation)

This is the stable contract every later agent builds on. Change a contract only
in coordination with the orchestrator. Paths are relative to the repo root.

## Toolchain and conventions

- Flutter stable 3.47.x / Dart 3.13 (`environment: sdk: ^3.13.5`).
- State: **Riverpod 3** (`flutter_riverpod`, plain providers, no codegen).
  Riverpod 3 retries failing providers automatically by default; tests that
  expect errors may need `retry: (_, _) => null` on the `ProviderScope`/container.
- Navigation: **go_router 18**. Always navigate with `AppRoutes` helpers.
- Models: **freezed 4** + **json_serializable**. Classes are declared
  `abstract class X with _$X`. `build.yaml` sets `field_rename: snake`,
  `explicit_to_json: true`, `include_if_null: true` globally, so JSON keys equal
  Supabase column names and nulls are always written (needed to clear columns).
- All timestamps are **UTC** (`clockProvider` returns `DateTime.now().toUtc()`).
  All ids are client-generated **UUID v4** (`idGeneratorProvider`).
- Imports: relative inside `lib/`, `package:quiz_app/...` in `test/`.
- Lints: `flutter_lints` + strict-casts/inference/raw-types and extra rules in
  `analysis_options.yaml`. `flutter analyze` must stay clean.

### Code generation

```sh
dart run build_runner build --delete-conflicting-outputs
```

Generated `*.g.dart` / `*.freezed.dart` files **are committed** so parallel
worktrees compile without running the generator. If you change an annotated
file, regenerate and commit the outputs. When merging conflicting generated
files, take either side and rerun build_runner.

### Errors (`lib/core/errors/`)

- `app_exception.dart`: `sealed class AppException implements Exception
  { String message; Object? cause; StackTrace? stackTrace; }` with subclasses
  `NetworkException`, `AppAuthException`, `NotFoundException`,
  `PermissionDeniedException`, `ValidationException`, `StorageException`,
  `AiException { AiErrorKind kind; int? statusCode; }`
  (`AiErrorKind`: missingApiKey, invalidApiKey, rateLimited, invalidOutput,
  unsupported, provider), `TranscriptUnavailableException`, `UnknownException`.
- `result.dart`: `sealed class Result<T>` = `Ok<T>(value)` | `Err<T>(AppException)`,
  plus `Future<Result<T>> runCatching<T>(Future<T> Function())`.
- Rule: repositories/services **throw** `AppException` subclasses (wrap
  Supabase/Hive/HTTP errors; `message` is user-safe). UI shows
  `AsyncValue.error` / `Result` errors via `message`. Never leak API keys in
  messages or logs.

## Models (`lib/data/models/`, barrel `models.dart`)

JSON keys are snake_case versions of the field names. `?` = nullable.

| Model | Fields |
|---|---|
| `Syncable` (interface) | `id, ownerId, createdAt, updatedAt, deletedAt?, toJson()`; ext `isDeleted`, `isOwnedBy(userId)` |
| `Profile` | `id, email?, displayName?` |
| `AppUser` (no JSON) | `id, email?, displayName?` |
| `Subject` : Syncable | `id, ownerId, title, description?, color? (int ARGB32), createdAt, updatedAt, deletedAt?` |
| `Note` : Syncable | `id, subjectId, ownerId, title, contentMd (default ''), createdAt, updatedAt, deletedAt?` |
| `Quiz` : Syncable | `id, subjectId, noteId?, ownerId, title, description?, source? (QuizSource), questions (List<Question>, default []), createdAt, updatedAt, deletedAt?` |
| `Question` | `id, type (QuestionType), prompt, options (List<String>), correctIndices (List<int>), answerText?, explanation?` |
| `QuestionType` | `mcqSingle 'mcq_single'`, `mcqMulti 'mcq_multi'`, `trueFalse 'true_false'`, `shortAnswer 'short_answer'`; `wireName`, `hasOptions` |
| `QuizSource` | `contextText?, youtubeUrl?, provider? (LlmProviderId.wireName), model?` |
| `QuizAttempt` : Syncable | `id, quizId, ownerId (the attempting user), answers (List<QuestionAnswer>), score (double), total (int), startedAt, completedAt?, createdAt, updatedAt, deletedAt?` |
| `QuestionAnswer` | `questionId, selectedIndices (List<int>), textAnswer?, isCorrect? (null = ungraded)` |
| `Share` | `id, ownerId, recipientId, resourceType (ShareResourceType), resourceId, createdAt`; read-only joins (not in `toJson`): `recipient? (Profile), owner? (Profile), resourceTitle?` |
| `ShareResourceType` | `subject`, `note`, `quiz` (JSON = name) |
| `OutboxOp` | `id, table (String), op (OutboxOpType), rowId, payload? (Map), createdAt, attempts (default 0), lastError?` |
| `OutboxOpType` | `upsert`, `delete` (hard delete, reserved), `uploadImage 'upload_image'`, `deleteImage 'delete_image'` |
| `SyncTables` | `subjects, notes, quizzes, quizAttempts='quiz_attempts', shares, profiles, noteImagesBucket='note-images'`; `synced` = [subjects, notes, quizzes, quiz_attempts] |
| `NoteImageRef` (plain) | `ownerId, noteId, fileName`; `storagePath = '{owner}/{note}/{file}'`, `markdownUrl = 'note-image://{storagePath}'`, `tryParse(String)` |
| `QuestionDraft` | as `Question` without `id`; `toQuestion(id)` |
| `QuizDraft` | `title, description?, questions (List<QuestionDraft>)`; `toQuestions(newId)` |
| `NoteDraft` | `title, contentMarkdown` (JSON `content_markdown`) |

Question rules: `mcqSingle` and `trueFalse` have exactly one correct index;
`trueFalse` options are `['True', 'False']`; `mcqMulti` has >= 1; `shortAnswer`
has empty `options`/`correctIndices` and uses `answerText`, self-graded.

AI output JSON Schemas (Dart `const Map<String, Object?>` in `drafts.dart`):
`quizDraftJsonSchema`, `noteDraftJsonSchema`. Strict-mode friendly (all
properties required, nullables as `type: [x, 'null']`,
`additionalProperties: false`). Providers adapt as needed (e.g. Gemini).

### Supabase schema implied by the models (for the backend agent)

- `profiles(id uuid pk references auth.users on delete cascade, email text, display_name text)`; row created by trigger on signup from `raw_user_meta_data->>'display_name'`.
- `subjects(id uuid pk, owner_id uuid, title text not null, description text, color bigint, created_at, updated_at, deleted_at timestamptz)`
- `notes(id, subject_id uuid -> subjects, owner_id, title, content_md text not null default '', created_at, updated_at, deleted_at)`
- `quizzes(id, subject_id -> subjects, note_id uuid null -> notes, owner_id, title, description, source jsonb, questions jsonb not null default '[]', created_at, updated_at, deleted_at)`
- `quiz_attempts(id, quiz_id -> quizzes, owner_id, answers jsonb not null default '[]', score double precision, total int, started_at, completed_at, created_at, updated_at, deleted_at)` — note: the column is `owner_id` (not `user_id`) so all synced tables are uniform.
- `shares(id, owner_id, recipient_id -> profiles, resource_type text check in ('subject','note','quiz'), resource_id uuid, created_at)` unique (resource_type, resource_id, recipient_id).
- `owner_id` defaults to `auth.uid()`; `updated_at` is set by a trigger (`now()`) on insert/update and drives the sync cursor; client-provided `id` and `created_at` are accepted.
- RPCs (`lib/data/remote/supabase_api.dart` `SupabaseRpc`):
  `find_user_by_email(p_email text) returns table(id uuid, display_name text)`;
  `copy_subject(p_subject_id uuid) returns uuid`;
  `copy_note(p_note_id uuid, p_target_subject_id uuid) returns uuid`;
  `copy_quiz(p_quiz_id uuid, p_target_subject_id uuid, p_target_note_id uuid default null) returns uuid`.
- Storage bucket `note-images`, object path `{owner_id}/{note_id}/{uuid}.{ext}`.

## Local storage (`lib/data/local/hive_boxes.dart`)

`HiveBoxes.init()` (called from bootstrap) runs `Hive.initFlutter('quiz_app')`,
`registerAdapters()` (intentionally empty) and opens every box as
`Box<String>`. **Values are `jsonEncode(model.toJson())` keyed by id** — no
TypeAdapters, so model changes never need Hive type-id migrations. Boxes:
`subjects`, `notes`, `quizzes`, `quiz_attempts`, `outbox` (OutboxOp JSON by op
id, FIFO by `createdAt`), `sync_meta` (cursors e.g. `cursor:{table}`), `prefs`
(non-secret prefs). `HiveBoxes.clearAll()` on sign-out. The data agent may add
boxes (e.g. image bytes cache) in `init()`.

## Interfaces

### Data (`lib/data/repositories/`, `lib/data/sync/`)

All repositories are local-first: reads from Hive, writes to Hive + outbox.
Streams emit the current value on listen and on every change; soft-deleted rows
are excluded. Updates bump `updatedAt`; editing a row not owned by the current
user throws `PermissionDeniedException`.

```dart
abstract interface class AuthRepository {
  AppUser? get currentUser;
  Stream<AppUser?> authStateChanges();          // emits current first
  Future<void> signUp({required String email, required String password, String? displayName});
  Future<void> signIn({required String email, required String password});
  Future<void> signOut();
  Future<void> resetPassword(String email);
}                                               // impl: SupabaseAuthRepository (done)

abstract interface class SubjectRepository {
  Stream<List<Subject>> watchAll();             // own, sorted by title
  Stream<Subject?> watchById(String id);        // own or shared
  Future<Subject?> getById(String id);
  Future<Subject> create({required String title, String? description, int? color});
  Future<Subject> update(Subject subject);
  Future<void> delete(String id);               // soft, cascades to notes/quizzes
}

abstract interface class NoteRepository {
  Stream<List<Note>> watchBySubject(String subjectId);   // updatedAt desc
  Stream<Note?> watchById(String id);
  Future<Note?> getById(String id);
  Future<Note> create({required String subjectId, required String title, String contentMd = ''});
  Future<Note> update(Note note);
  Future<void> delete(String id);               // soft, cascades to its quizzes
}

abstract interface class QuizRepository {
  Stream<List<Quiz>> watchBySubject(String subjectId);   // incl. note quizzes
  Stream<List<Quiz>> watchByNote(String noteId);
  Stream<Quiz?> watchById(String id);
  Future<Quiz?> getById(String id);
  Future<Quiz> create({required String subjectId, String? noteId, required String title,
      String? description, List<Question> questions = const [], QuizSource? source});
  Future<Quiz> update(Quiz quiz);
  Future<void> delete(String id);
}

abstract interface class AttemptRepository {
  Stream<List<QuizAttempt>> watchByQuiz(String quizId);  // current user, newest first
  Stream<QuizAttempt?> watchById(String id);
  Future<QuizAttempt?> getById(String id);
  Future<QuizAttempt> start({required String quizId, required int total});
  Future<QuizAttempt> save(QuizAttempt attempt);
  Future<void> delete(String id);
}

abstract interface class ShareRepository {    // online-only
  Future<Profile?> findUserByEmail(String email);
  Future<Share> share({required ShareResourceType resourceType, required String resourceId, required String recipientId});
  Future<void> revoke(String shareId);
  Future<List<Share>> listSharesFor(ShareResourceType resourceType, String resourceId);
  Future<List<Share>> sharedWithMe();
  Future<String> copyToMyAccount({required ShareResourceType resourceType, required String resourceId,
      String? targetSubjectId, String? targetNoteId});   // returns new id, triggers sync
}

abstract interface class ImageStore {
  Future<NoteImageRef> saveNoteImage({required String noteId, required Uint8List bytes, required String extension});
  Future<Uint8List?> load(NoteImageRef ref);   // local cache, else download
  Future<void> delete(NoteImageRef ref);
}

enum SyncState { idle, syncing, offline, error }
class SyncStatus { SyncState state; DateTime? lastSyncedAt; int pendingOps; String? error; } // freezed
abstract interface class SyncEngine {
  Stream<SyncStatus> get status;
  SyncStatus get currentStatus;
  void start();                // connectivity / sign-in / resume / local-write triggers
  Future<void> sync();         // push outbox FIFO then pull per table; never throws on network errors
  Future<void> dispose();
}
```

Shared content: sync pulls own **and** shared rows into the same boxes, so
`NoteRepository.watchBySubject(sharedSubjectId)` works. UI decides read-only
via `entity.isOwnedBy(ref.watch(currentUserIdProvider))`.

### AI (`lib/ai/`)

```dart
enum LlmProviderId { gemini, openai, anthropic, openaiCompatible }
  // wireName: 'gemini' | 'openai' | 'anthropic' | 'openai_compatible'
  // displayName, supportsYoutubeUrl (gemini only), requiresBaseUrl, fromWireName()
class LlmConfig { LlmProviderId providerId; String apiKey; String model; String? baseUrl; }

abstract interface class LlmProvider {
  LlmProviderId get id;
  Future<List<String>> listModels();
  Future<Map<String, dynamic>> generateJson({required String prompt, required Map<String, Object?> schema,
      String? schemaName, String? youtubeUrl, String? systemPrompt});
}
abstract interface class LlmProviderFactory { LlmProvider create(LlmConfig config); }

abstract interface class ApiKeyStore {        // flutter_secure_storage, never synced
  Future<String?> getApiKey(LlmProviderId p);  Future<void> setApiKey(LlmProviderId p, String key);
  Future<void> deleteApiKey(LlmProviderId p);
  Future<String?> getBaseUrl(LlmProviderId p); Future<void> setBaseUrl(LlmProviderId p, String? url);
  Future<LlmProviderId?> getSelectedProvider(); Future<void> setSelectedProvider(LlmProviderId p);
  Future<String?> getSelectedModel(LlmProviderId p); Future<void> setSelectedModel(LlmProviderId p, String model);
  Future<Set<LlmProviderId>> configuredProviders();
}

class VideoTranscript { String videoId; String? title; String text; String? languageCode; }
abstract interface class TranscriptService { Future<VideoTranscript> fetchTranscript(String url); }

enum Difficulty { easy, medium, hard }
// freezed, no JSON:
QuizGenerationRequest { String? contextText; String? youtubeUrl; int questionCount = 10;
  Set<QuestionType> questionTypes = all; Difficulty difficulty = medium; String? language;
  String? extraInstructions; LlmProviderId? providerId; String? model; }   // null = ApiKeyStore selection
NoteGenerationRequest { String? contextText; String? youtubeUrl; String? language;
  String? extraInstructions; LlmProviderId? providerId; String? model; }

abstract interface class AiService {
  Future<QuizDraft> generateQuiz(QuizGenerationRequest request);
  Future<NoteDraft> generateNote(NoteGenerationRequest request);
}
```

`AiService` resolves provider/key/model, fetches a transcript when the provider
cannot take YouTube URLs, validates output against the schema with one repair
retry, and throws `AiException(kind: missingApiKey)` when no key is stored.
The UI fills `QuizSource` (provider wireName + model) when saving a draft; it
should resolve the provider/model before calling so it knows what was used.

## Providers

| Provider | File | Type |
|---|---|---|
| `supabaseClientProvider` | `lib/core/providers.dart` | `Provider<SupabaseClient>` |
| `clockProvider`, `idGeneratorProvider` | `lib/core/providers.dart` | `Provider<Clock>`, `Provider<IdGenerator>` |
| `themeModeProvider` | `lib/core/theme/app_theme.dart` | `NotifierProvider<ThemeModeController, ThemeMode>` |
| `routerProvider` | `lib/core/router/app_router.dart` | `Provider<GoRouter>` |
| `authRepositoryProvider` | `lib/data/data_providers.dart` | `Provider<AuthRepository>` (implemented) |
| `subjectRepositoryProvider`, `noteRepositoryProvider`, `quizRepositoryProvider`, `attemptRepositoryProvider`, `shareRepositoryProvider`, `imageStoreProvider`, `syncEngineProvider` | `lib/data/data_providers.dart` | `Provider<...>` (stubs throw `UnimplementedError`) |
| `authStateProvider` | same | `StreamProvider<AppUser?>` |
| `currentUserIdProvider` | same | `Provider<String?>` |
| `subjectsProvider` | same | `StreamProvider.autoDispose<List<Subject>>` |
| `subjectProvider(id)`, `noteProvider(id)`, `quizProvider(id)` | same | `StreamProvider.autoDispose.family<T?, String>` |
| `notesBySubjectProvider(subjectId)`, `quizzesBySubjectProvider(subjectId)`, `quizzesByNoteProvider(noteId)`, `attemptsByQuizProvider(quizId)` | same | `StreamProvider.autoDispose.family<List<T>, String>` |
| `sharedWithMeProvider` | same | `FutureProvider.autoDispose<List<Share>>` |
| `sharesForResourceProvider((type: t, id: id))` | same | `FutureProvider.autoDispose.family<List<Share>, ({ShareResourceType type, String id})>` |
| `syncStatusProvider` | same | `StreamProvider<SyncStatus>` |
| `apiKeyStoreProvider`, `llmProviderFactoryProvider`, `transcriptServiceProvider`, `aiServiceProvider` | `lib/ai/ai_providers.dart` | `Provider<...>` (stubs) |

Implementers replace the stub provider **bodies** in place (keep names/types).
Tests override them: `ProviderScope(overrides: [subjectRepositoryProvider.overrideWithValue(fake)])`.

## Routes (`lib/core/router/`)

`AppRoutes`: `/login`, `/signup`, `/` (subjects), `/shared`, `/settings` (these
three inside `AppShell` ShellRoute with NavigationBar / NavigationRail >= 720px),
`subject(id)` `/subjects/:id`, `note(id)` `/notes/:id`, `noteEdit(id)`
`/notes/:id/edit`, `quiz(id)` `/quizzes/:id`, `quizEdit(id)` `/quizzes/:id/edit`,
`quizPlay(id)` `/quizzes/:id/play`,
`generate(kind: AiGenerateKind.quiz|note, subjectId?, noteId?)`
`/ai/generate?kind=&subjectId=&noteId=`. Redirect: signed out -> `/login`;
signed in on `/login|/signup` -> `/`. "New note/quiz" flows: create via the
repository, then `push(AppRoutes.noteEdit(id))` / `quizEdit(id)`.

Each route builds a screen class from `lib/features/<feature>/presentation/`
(`LoginScreen`, `SignupScreen`, `SubjectsScreen`, `SubjectDetailScreen(subjectId)`,
`NoteViewScreen(noteId)`, `NoteEditScreen(noteId)`, `QuizDetailScreen(quizId)`,
`QuizEditScreen(quizId)`, `QuizPlayScreen(quizId)`,
`AiGenerateScreen(kind, subjectId?, noteId?)`, `SharedWithMeScreen`,
`SettingsScreen`). Feature agents replace those files' contents and keep the
class names/constructors, so `app_router.dart` needs no edits.

## Ownership for later agents

| Agent | Owns |
|---|---|
| Backend | `supabase/migrations/*.sql` (timestamped, e.g. `20260101000000_init.sql`), `supabase/tests/*.sql` (pgTAP), `supabase/config.toml` |
| Data & sync | `lib/data/local/`, `lib/data/remote/`, `lib/data/sync/` (impl files), `lib/data/repositories/*_impl.dart` or `local_*`, stub bodies in `lib/data/data_providers.dart`, tests in `test/data/` |
| AI | `lib/ai/**` implementations (`lib/ai/providers/`, `prompts.dart`, `draft_validator.dart`, ...), stub bodies in `lib/ai/ai_providers.dart`, tests in `test/ai/` |
| UI: auth/subjects/notes/settings | `lib/features/{auth,subjects,notes,settings}/`, `lib/core/router/app_shell.dart` |
| UI: quizzes + AI generate | `lib/features/{quizzes,ai_generate}/` |
| UI: sharing | `lib/features/sharing/` (share sheet widget usable from subject/note/quiz screens) |

Shared widgets used by several features go in `lib/core/widgets/`. Feature
code may only depend on interfaces + providers listed above.

## Platform notes

- Markdown rendering: `flutter_markdown_plus` (maintained fork of the
  discontinued `flutter_markdown`) + `markdown`. Resolve `note-image://` URLs
  with a custom image builder that calls `ImageStore.load`.
- Web: YouTube transcripts are likely CORS-blocked; surface
  `TranscriptUnavailableException` and suggest Gemini.
- Android `INTERNET`/`ACCESS_NETWORK_STATE` permissions and macOS
  `network.client` + user-selected file entitlements are already added.
