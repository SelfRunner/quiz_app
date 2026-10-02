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
  `PermissionDeniedException`, `ValidationException` (subclass
  `AlreadySharedException`: share already exists), `StorageException`,
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
  `find_user_by_email(p_email text) returns table(id uuid, display_name text, email text)` (confirmed-email users only; shares to unconfirmed users are rejected with `42501`);
  `copy_subject(p_subject_id uuid) returns uuid`;
  `copy_note(p_note_id uuid, p_target_subject_id uuid) returns uuid`;
  `copy_quiz(p_quiz_id uuid, p_target_subject_id uuid, p_target_note_id uuid default null) returns uuid`.
- Storage bucket `note-images`, object path `{owner_id}/{note_id}/{uuid}.{ext}`.
- `attachments(...)` + Storage bucket `attachments`: see *Attachments* below.

### Attachments (backend: `supabase/migrations/20261004000000_attachments.sql`)

Files attached to a **subject** ("Files" library). Shared together with the
subject (subject shares only — note/quiz shares never expose them), copied by
`copy_subject` (not by `copy_note`/`copy_quiz`).

**Table `public.attachments`** — synced table, same conventions as `notes`
(client `id` uuid v4 + `created_at`; `owner_id` defaults to `auth.uid()` and
is immutable; `updated_at` is server `now()` = sync cursor; soft delete via
`deleted_at`; upsert with `onConflict: 'id'`).

| Column | Type | Rules |
|---|---|---|
| `id` | uuid pk | client-generated |
| `subject_id` | uuid not null → subjects (on delete cascade) | subject must exist (`23503`) and be owned by the same user (`42501`); **immutable** (`42501`) |
| `owner_id` | uuid not null default `auth.uid()` | immutable |
| `name` | text not null | display name (original file name), 1..512 chars |
| `mime_type` | text null | ≤ 255 chars |
| `size_bytes` | bigint not null default 0 | ≥ 0 |
| `kind` | text not null default `'other'` | one of `pdf`, `image`, `text`, `docx`, `audio`, `video`, `other` (`23514`) |
| `storage_path` | text not null unique | exactly `{owner_id}/{subject_id}/{id}/{file}` (`23514` otherwise); **immutable** (`42501`) |
| `extracted_text` | text null | client-extracted text (txt/md/docx), ≤ 200 000 chars (`23514`); truncate before saving |
| `created_at`, `updated_at`, `deleted_at` | timestamptz | as other synced tables |

Suggested model: `Attachment : Syncable` with `id, subjectId, ownerId, name,
mimeType?, sizeBytes, kind (AttachmentKind, JSON = name), storagePath,
extractedText?, createdAt, updatedAt, deletedAt?`. Kind by extension:
`pdf`→pdf; `png/jpg/jpeg/gif/webp/heic/bmp`→image; `txt/md`→text;
`docx`→docx; `mp3/wav/m4a/aac/ogg/flac`→audio; `mp4/mov/webm/mkv/avi`→video;
else other.

**Storage**: private bucket `attachments` (50 MiB per file, any MIME type).
Object path = the row's `storage_path`:
`{owner_id}/{subject_id}/{attachment_id}/{file}`, uuids lowercase (as Dart's
`uuid` package and Postgres print them). `{file}` is one path segment: use a
sanitized file name (keep `[A-Za-z0-9._-]`, replace anything else with `_`,
≤ 100 chars, keep the extension, fallback `file`); the original name goes in
`name`. Writes only in your own folder; reads: own folder, or a live
attachment row with exactly that `storage_path` whose subject you can read.
Download with `storage.from('attachments').download(storagePath)` (or a
signed URL); 403/404 = unavailable (revoked, deleted, or blob not uploaded
yet / never copied).

**Visibility for recipients**: an attachment is readable while the attachment
and its subject are not soft-deleted and the caller has a share on that
subject. Recipients never receive attachment tombstones; revocation and soft
deletes make rows silently disappear (same as notes: reconcile ids of
non-owned cached attachments, and purge their cached bytes).

**Client protocol**
1. *Sync*: add `attachments` to the pulled/pushed tables (keyset cursor like
   the others). When a new **subject** share appears, also fetch
   `attachments` by `subject_id` without the cursor. Note/quiz shares never
   need it.
2. *Upload* (owner of the subject only): generate `id`, build
   `storage_path`, store bytes locally, queue the blob upload
   (`storage.from('attachments').uploadBinary(storagePath, bytes,
   fileOptions: FileOptions(contentType: mimeType, upsert: true))`) **before**
   the row upsert in the FIFO outbox, so recipients rarely see a row whose
   blob is not there yet (handle 404 anyway). Text/docx: extract text in-app,
   truncate to 200 000 chars, set `extracted_text`.
3. *Update*: only `name` (and `extracted_text`, `mime_type`, `kind`,
   `size_bytes`) may change; never `subject_id`/`storage_path`. Moving to
   another subject is not supported.
4. *Delete*: soft delete the row (push the tombstone), then remove the blob
   with `storage.from('attachments').remove([storagePath])`. Soft-deleting a
   subject should cascade locally to its attachments (and their blobs).
   Hard-deleting a subject on the server cascades the rows but never the
   blobs.
5. *Copy* (`copy_subject`): the RPC copies live attachment rows to the caller
   (new ids, `storage_path = {me}/{new_subject}/{new_id}/{same file}`) and
   queues one `note_image_copies` row per blob with **`bucket =
   'attachments'`** (note images keep `bucket = 'note-images'`, the default).
   The copy processor must select `id, bucket, from_path, to_path` and call
   `storage.from(row.bucket).copy(fromPath, toPath)`, with the existing
   rules (delete the row on success / 409 / permanent error; keep it on
   network/transient errors). Copy any locally cached bytes for the source
   path to the new path. Until processed the copied attachment's blob is
   missing. (Older builds that ignore `bucket` try `note-images`, fail and
   drop such rows; the copied attachment then has no blob.)
6. *Errors*: `42501` (not owner, subject not owned, immutable column),
   `23514` (bad `kind`, path shape, text too long), `23503` (subject not
   synced yet: defer like notes).

## Local storage (`lib/data/local/hive_boxes.dart`)

`HiveBoxes.init()` (called from bootstrap) runs `Hive.initFlutter('quiz_app')`,
`registerAdapters()` (intentionally empty) and opens every box as
`Box<String>`. **Values are `jsonEncode(model.toJson())` keyed by id** — no
TypeAdapters, so model changes never need Hive type-id migrations. Boxes:
`subjects`, `notes`, `quizzes`, `quiz_attempts`, `outbox` (OutboxOp JSON by op
id, FIFO by `createdAt`), `sync_meta` (cursors e.g. `cursor:{table}`), `prefs`
(non-secret prefs). `HiveBoxes.clearAll()` on sign-out. The data agent may add
boxes (e.g. image bytes cache) in `init()`. Added: `note_image_bytes`
(`Box<Uint8List>`, web image cache); sign-out clearing is done by the sync
engine (see Data layer notes).

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

abstract interface class ShareRepository {    // online-only (sharedWithMe: offline cache)
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
class SyncStatus { SyncState state; DateTime? lastSyncedAt; int pendingOps; String? error;
  int stuckOps; int rejectedChanges; } // freezed (last two added in Phase 3)
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
  // displayName, supportsYoutubeUrl (gemini only), requiresBaseUrl, fromWireName(),
  // defaultModel, defaultBaseUrl (openai_compatible: https://openrouter.ai/api/v1)
class LlmConfig { LlmProviderId providerId; String apiKey; String model; String? baseUrl;
  Map<String, String> extraHeaders = const {}; }   // toString() never prints the key

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
  Future<Map<String, String>> getExtraHeaders(LlmProviderId p);              // added (Phase 1C)
  Future<void> setExtraHeaders(LlmProviderId p, Map<String, String> headers); // added (Phase 1C)
  Future<Set<LlmProviderId>> configuredProviders();
}

class VideoTranscript { String videoId; String? title; String text; String? languageCode;
  bool isAutoGenerated = false; bool truncated = false; }
abstract interface class TranscriptService { Future<VideoTranscript> fetchTranscript(String url); }

enum Difficulty { easy, medium, hard }
// freezed, no JSON:
QuizGenerationRequest { String? contextText; String? youtubeUrl; int questionCount = 10;
  Set<QuestionType> questionTypes = all; Difficulty difficulty = medium; String? language;
  String? extraInstructions; String? topic; LlmProviderId? providerId; String? model; }   // null = ApiKeyStore selection
NoteGenerationRequest { String? contextText; String? youtubeUrl; String? language;
  String? extraInstructions; String? topic; LlmProviderId? providerId; String? model; }

class AiSelection { LlmProviderId providerId; String model; }   // value equality

abstract interface class AiService {
  Future<QuizDraft> generateQuiz(QuizGenerationRequest request);
  Future<NoteDraft> generateNote(NoteGenerationRequest request);
  Future<AiSelection> resolveSelection({LlmProviderId? providerId, String? model});        // added
  Future<List<String>> listModels(LlmProviderId p, {String? apiKey, String? baseUrl,
      Map<String, String>? extraHeaders});                                                 // added
  Future<void> testConnection(LlmProviderId p, {String? apiKey, String? baseUrl,
      Map<String, String>? extraHeaders});                                                 // added
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
| `apiKeyStoreProvider`, `llmProviderFactoryProvider`, `transcriptServiceProvider`, `aiServiceProvider` | `lib/ai/ai_providers.dart` | `Provider<...>` (implemented) |
| `aiHttpClientProvider` | `lib/ai/ai_providers.dart` | `Provider<http.Client>` (override with `MockClient` in tests) |

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

## Data layer notes (Phase 1B, implemented)

Implementation: `lib/data/local/` (Hive tables, outbox, sync meta, image
cache), `lib/data/remote/` (`*RemoteDataSource` interfaces +
`SupabaseRemoteDataSource`), `lib/data/sync/` (`DefaultSyncEngine`,
`ConnectivityMonitor`, `NoteImageCopyProcessor`), `lib/data/repositories/`
(`Local*Repository`, `LocalImageStore`, `SupabaseShareRepository`).

**Using it from the UI**
- Just use the repositories/providers above. Any repository read creates and
  starts the sync engine (`dataContextProvider` watches `syncEngineProvider`),
  so triggers are active as soon as the app shows data. The app shell may also
  `ref.watch(syncStatusProvider)` for an indicator.
- Sync status: `syncStatusProvider` -> `SyncStatus{state: idle|syncing|
  offline|error, lastSyncedAt, pendingOps, error}`. `error` is a user-safe
  message (may list several lines) and stays until the next successful cycle.
- Manual sync / pull-to-refresh: `await ref.read(syncEngineProvider).sync()`
  (never throws; concurrent calls join the running cycle).
- Rejected changes (server refused an outbox op permanently, e.g. RLS
  `42501`, CHECK `23514`): the op is dropped, the server version of the row
  is restored locally, `status.error` is set, and
  `(engine as DefaultSyncEngine).rejections` emits a `SyncRejection` (for a
  snackbar). The user's rejected row JSON is kept in `sync_meta` (max 50):
  `engine.rejectedChanges` (`RejectedChange{id, table, rowId, payload,
  message, at}`), count in `status.rejectedChanges`,
  `engine.dismissRejectedChange(id)`.
- Stuck changes: ops that keep failing with server errors (5xx/unknown) are
  **never dropped**; after 8 attempts they count in `status.stuckOps` (state
  `error`, message "... Retrying automatically.") and keep retrying.
- Widget tests: override the repository providers (or `syncEngineProvider`
  + `localDatabaseProvider` + `*RemoteDataSourceProvider`s) — the real
  providers need Supabase and opened Hive boxes.

**Sync triggers**: sign-in (and app start with a session), connectivity
regained (`connectivity_plus`; a connectivity change during a running cycle
queues one more cycle, and `sync()` callers joining it wait for that too), app resumed/shown, every 5 min while
foregrounded, 2 s after any local write (debounced), manual `sync()`, plus
exponential backoff retries (5 s .. 5 min) after network/transient errors.
`SupabaseAuthRepository.signOut` first tries a final push (max 10 s).

**Sign-out / account switch**: all user-scoped boxes (entities, outbox,
`sync_meta`, image cache) are wiped only on an **explicit** sign-out
(`AuthRepository.signOut` -> `SupabaseAuthRepository.afterSignOut` ->
`DefaultSyncEngine.clearAfterSignOut()`) or when a **different** user signs
in (`prefs` is kept). Unpushed changes are lost after the best-effort final
push. An involuntary sign-out (session expired / refresh token revoked) only
stops syncing; local data and the outbox are kept and pushed when the same
user signs back in.

**Sync algorithm**
- Push: outbox FIFO; upserts of the same row coalesce in place. Network error
  -> stop, `offline`; JWT error -> `error`; FK `23503` -> deferred and retried
  (3 passes); permanent (`42501`, `23xxx`, `22xxx`, `P0001/P0002`, 4xx) ->
  dropped + reported (payload kept, see above); transient (5xx/unknown,
  408/429) -> retried with capped backoff, never dropped (FK-blocked ops are
  not counted while other ops fail transiently).
- After push, pending `note_image_copies` rows are processed (Storage copy
  `from_path` -> `to_path`, then the row is deleted; also deleted when the
  source is gone/unreadable or the target exists).
- Pull: per table, keyset pages `(updated_at, id) > cursor` ascending, 500
  rows. Cursor = raw server `updated_at` string + id of the last row
  (`sync_meta` `cursor:{table}`), never the client clock; each sync starts
  5 s before the cursor (transaction-start `now()` skew) and merges
  idempotently.
- Merge = last-write-wins: a pulled row replaces the local one unless the
  outbox still has an op for that row. Other users' tombstones are purged
  locally; own tombstones are kept (hidden from streams); unknown tombstones
  are ignored. The server never returns other users' tombstones: for a
  recipient, a soft-deleted row (or one under a soft-deleted parent) just
  stops being visible and soft-deleting a shared resource deletes its shares,
  so such rows are removed by the reconciliation below. The server may normalize rows (e.g. `quiz.subject_id` follows
  its note); the next pull corrects the local copy.
- Shares: each sync lists `shares` where `recipient_id = me`. A new share ->
  targeted fetch without cursor (subject: the subject + notes/quizzes by
  `subject_id`; note: the note + quizzes by `note_id`; quiz: the quiz). A
  revoked share (or every 30 min) -> reconciliation: ids of locally cached
  rows owned by others are checked with `select id where id in (...)` and
  rows no longer visible are purged (plus their cached images).

**Repositories**: local-first; writes set `ownerId` = current user, client
UUID, `createdAt/updatedAt` = now (server overwrites `updated_at`), then
enqueue + write Hive. Non-owned rows -> `PermissionDeniedException` (also
creating notes/quizzes under a shared subject/note). Deletes are soft and
cascade locally: subject -> notes (+ their quizzes and own images) and
quizzes; note -> its quizzes + own images. A quiz with `noteId` must use the
note's subject (`ValidationException` otherwise); moving a note moves its
quizzes. Attempts are always owned by the taker (allowed on shared quizzes).
Signed out -> `AppAuthException`.

**ShareRepository** (online-only): offline -> `NetworkException("You're
offline. Sharing needs an internet connection.")`. `share()` pushes pending
local changes first; unique violation (`23505`/409) ->
`AlreadySharedException` (a `ValidationException`; the share sheet shows
"Already shared with X." and refreshes its list); resource still queued for
upload (server refuses with RLS/FK) -> `NetworkException("... hasn't finished
uploading yet ...")`; self-share -> `ValidationException`.
`sharedWithMe()` works offline: every online fetch is persisted in
`sync_meta` (`shared_with_me`, with owner profile + title, per user); offline
or on a network error it returns that list (titles refreshed from Hive),
minus shares revoked / plus shares added according to later syncs'
`incoming_shares` keys (added ones are derived from the cached rows). Throws
`NetworkException` only when nothing is known. Lists embed profiles via
`profiles!shares_recipient_id_fkey` / `profiles!shares_owner_id_fkey`;
`sharedWithMe()` fills `resourceTitle` from local cache, else the table.
`findUserByEmail` returns `Profile(id, displayName, email)`.
`copyToMyAccount` validates the target (note/quiz need an owned
`targetSubjectId`; `targetNoteId` only for quizzes and must be in that
subject), pushes pending changes, calls `copy_*` (returns the new root id),
runs the image-copy queue, then waits for a fresh sync so the copy is in
Hive when it returns.

**Images**: Markdown uses `![alt](note-image://{ownerId}/{noteId}/{uuid}.{ext})`
(`NoteImageRef.markdownUrl`). `ImageStore.saveNoteImage` (owned note only)
stores bytes locally (files under app support dir on native, Hive box
`note_image_bytes` on web) and queues `upload_image`; insert the returned
`ref.markdownUrl`. Render with a markdown image builder:
`NoteImageRef.tryParse(uri.toString())` -> `ref.watch(imageStoreProvider)
.load(ref)` -> `Image.memory` (bytes come from memory/disk cache, else are
downloaded and cached; null = unavailable/offline). `LocalImageStore
.signedUrl(ref)` gives a 1 h signed URL if a network URL is needed.
`ImageStore.delete` removes the local copy and queues `delete_image`.

**Errors** (all `AppException`, `message` is user-safe): `AppAuthException`
(signed out / session expired), `PermissionDeniedException` (read-only shared
item, RLS), `NotFoundException` (missing row, RPC `P0002`),
`ValidationException` (bad input, server CHECK/constraint, `P0001` with the
SQL message), `NetworkException` (offline/unreachable; share ops only —
local writes never fail offline), `StorageException` (Hive write failed),
`UnknownException` (server 5xx).

## Platform notes

- Markdown rendering: `flutter_markdown_plus` (maintained fork of the
  discontinued `flutter_markdown`) + `markdown`. Resolve `note-image://` URLs
  with a custom image builder that calls `ImageStore.load`.
- Web: YouTube transcripts are likely CORS-blocked; surface
  `TranscriptUnavailableException` and suggest Gemini.
- Android `INTERNET`/`ACCESS_NETWORK_STATE` permissions and macOS
  `network.client` + user-selected file entitlements are already added.

## AI layer notes (Phase 1C)

**Generating (UI: ai_generate).** Read `aiServiceProvider` and call it from a
button handler; it never writes to the DB.

```dart
final ai = ref.read(aiServiceProvider);
final selection = await ai.resolveSelection();          // show "Using OpenAI · gpt-5.4-mini"
final draft = await ai.generateQuiz(QuizGenerationRequest(
  contextText: text, youtubeUrl: url, questionCount: 10,
  questionTypes: {QuestionType.mcqSingle, QuestionType.trueFalse},
  difficulty: Difficulty.medium, language: null /* = source language */,
  topic: subject.title, extraInstructions: null,
  providerId: selection.providerId, model: selection.model,   // pin what you displayed
));
// preview/edit draft, then save:
quizRepo.create(subjectId: .., noteId: .., title: draft.title, description: draft.description,
  questions: draft.toQuestions(ref.read(idGeneratorProvider)),
  source: QuizSource(contextText: text, youtubeUrl: url,
      provider: selection.providerId.wireName, model: selection.model));
```

`generateNote(NoteGenerationRequest(...))` returns `NoteDraft(title,
contentMarkdown)` -> `noteRepo.create(...)`. Expect 10-120 s for a call (one
automatic repair retry may double it); show progress and disable the button.
Limits: 1-50 questions; pasted text over 100k chars and transcripts over 60k
chars are truncated with a note.

**YouTube.** Gemini receives the URL natively (any form: watch, youtu.be,
shorts, embed, live; public videos only). Other providers get the captions via
`transcriptServiceProvider` (manual English > auto English > first track).
`YoutubeUrl.parseVideoId/normalize` (`lib/ai/youtube_url.dart`) can validate
the input field client-side.

**Settings (UI: settings).** `apiKeyStoreProvider` for persistence
(`setApiKey`, `deleteApiKey`, `setSelectedProvider`, `setSelectedModel`,
`setBaseUrl` (throws `ValidationException` on a malformed URL),
`setExtraHeaders` e.g. `{'HTTP-Referer': .., 'X-Title': ..}` for OpenRouter,
`configuredProviders`, `clearForUser(id)`, `clearAll()`). Model picker: `aiService.listModels(p, apiKey:
unsavedKey?, baseUrl: ..)`, falling back to free text +
`p.defaultModel` on error. "Test" button: `aiService.testConnection(p,
apiKey: unsavedKey?)` completes or throws. Base URL / headers fields only for
`p.requiresBaseUrl`. On web, warn that keys are stored in browser storage
(weaker than OS keychains).

**Per-user scoping.** The store is rebuilt from `currentUserIdProvider` and
keys every entry as `ai.u.<userId>.<entry>`, so another account on the same
device never sees (or pays with) the previous user's key. Signed out: reads
return nothing, writes throw `AppAuthException`. Sign-out deletes nothing
(the same user gets their keys back); Settings has "Remove all saved keys"
(`clearForUser`). Pre-namespacing entries (`ai.<entry>`) are moved once to
the first signed-in user that touches the store, then deleted. Tests override
`aiSecureStorageProvider` with `InMemoryKeyValueStore`.

**Base URL policy** (`lib/ai/base_url_policy.dart`): `https://` only, except
`http://` to loopback/private hosts (`localhost`, `*.localhost`, `*.local`,
`127/8`, `::1`, `10/8`, `172.16/12`, `192.168/16`) for Ollama/LM Studio.
Enforced by `setBaseUrl`, by `DefaultAiService` before any request (including
unsaved Settings input and previously stored values), and by the Settings
field validator (`baseUrlProblem`).

**Errors** (all `AppException`, show `message`):

| Type / kind | When | Suggested UI |
|---|---|---|
| `AiException(missingApiKey)` | no key for the provider | button "Open Settings" |
| `AiException(invalidApiKey)` | 401/403, Gemini `API_KEY_INVALID` | "Open Settings" |
| `AiException(rateLimited)` | 429, quota/credits exhausted (402) | retry later |
| `AiException(invalidOutput)` | bad JSON/validation twice, or output cut off | retry / fewer questions / other model |
| `AiException(provider)` | refusal, safety block, 404 model, 5xx | show message |
| `AiException(unsupported)` | internal (YouTube URL to non-Gemini) | n/a |
| `TranscriptUnavailableException` | no captions, private video, YouTube blocked (always on web) | suggest Gemini or pasting text |
| `ValidationException` | no input, bad YouTube URL, count out of range | inline field error |
| `NetworkException` | offline, timeout (5 min), CORS (web) | retry |

**Endpoints.** Gemini `v1beta/models/{m}:generateContent`
(`generationConfig.responseFormat.text{mimeType: APPLICATION_JSON, schema}`,
auto-fallback to legacy `responseMimeType`+`responseJsonSchema`), OpenAI
Responses API `/v1/responses` (`text.format` json_schema strict, `store:
false`), Anthropic `/v1/messages` (`anthropic-version: 2023-06-01`,
`output_config.format` json_schema; fallback forced tool use), OpenAI-compatible
`{base}/chat/completions` (json_schema -> json_object -> prompt-only).
Web CORS: Gemini, OpenAI, Anthropic (via
`anthropic-dangerous-direct-browser-access`) and OpenRouter allow browser
calls; self-hosted endpoints (Ollama etc.) need CORS configured; YouTube
captions are blocked in browsers.

## Cross-feature UI entry points (Phase 2)

Stubs exist so the three UI agents can depend on each other without touching
each other's folders. Owners replace the bodies, keeping signatures.

| Entry point | File | Owner | Used by |
|---|---|---|---|
| `showShareSheet(context, type:, resourceId:, title:)` | `lib/features/sharing/widgets/share_actions.dart` | sharing | subject/note/quiz screens (owner only) |
| `CopyToAccountButton(type:, resourceId:, compact = false)` | same file | sharing | subject/note/quiz screens when not owned (`compact: true` = app-bar icon button). Notes/quizzes ask for an owned target subject (or create one); snackbar "Open" pushes the copy's route |
| `copySharedToMyAccount(context, type:, resourceId:)` → `Future<String?>` | same file | sharing | popup-menu items (same flow as the button; returns the new id) |
| `SharedByChip(ownerId:, ownerName?)` | `lib/features/sharing/widgets/shared_by_chip.dart` | sharing | subject/note/quiz screens when not owned ("Shared by Alice"; resolves the name via `sharedOwnerNamesProvider`, best effort, falls back to "Shared with you"; tests should override `shareRepositoryProvider` or pass `ownerName`) |
| `QuizListSection(subjectId:, noteId?, readOnly)` | `lib/features/quizzes/widgets/quiz_list_section.dart` | quizzes | `SubjectDetailScreen` (noteId null = subject-level quizzes), `NoteViewScreen` |

AI note generation result is saved by the ai_generate feature (creates the note
via `NoteRepository`, then navigates to `AppRoutes.noteEdit`). Subjects/notes
screens only link to `AppRoutes.generate(...)`.

## Design system (Wave 1)

Look: minimal & clean (Notion/Obsidian-like). Neutral warm-gray surfaces
(off-white `#FBFBFA` light, true dark gray `#191919` dark), near-black text,
one restrained accent (indigo `AppPalette.accent`), hairline borders instead of
shadows, flat app bars. Subject colors are **only** small accents: a
`SubjectColorDot`, an `AppCard(accentColor:)` left border, or an icon tint -
never large fills. Platform default font (works offline everywhere) with a
tuned `AppTypography` text theme: semibold headings with slight negative
tracking, body 16/14 with 1.6/1.55 line height.

Import everything from one barrel:

```dart
import '../../../core/widgets/design_system.dart';
```

(`lib/core/theme/app_theme.dart` also re-exports the tokens and `AppColors`.)
Note: `lib/features/quizzes/widgets/quiz_format.dart` has its own `MaxWidth`;
a file importing both needs `hide MaxWidth` (prefer `ContentContainer`).

**Tokens** (`lib/core/theme/tokens.dart`)
- `Insets`: `xxs 2, xs 4, sm 8, md 12, lg 16, xl 24, xxl 32, xxxl 48`;
  `gutter`/`gutterWide`, `card`, `row`, `page`, `pageWide` (EdgeInsets).
- `Gaps`: `Gaps.h8`, `Gaps.w12`, ... (const `SizedBox`es).
- `Radii`: `xs 4, sm 6, md 8 (default: inputs/buttons/rows), lg 10 (cards),
  xl 14 (dialogs/sheets)`, plus `Radii.mdAll` etc.
- `ContentWidth`: `form 640`, `readable 880` (notes, quiz play), `wide 1200`
  (grids/lists). `Motion.fast/medium/slow`.
- `AppColors.of(context)`: `sidebar, card, hairline, border, hover, pressed,
  focusRing, mutedText, faintText, skeleton` and `info/success/warning/danger`
  (+ `...Container`, `on...Container`). Use these rather than raw colors.

**Component defaults from the theme**: outlined thin inputs (not filled);
`FilledButton` for the one primary action per view, otherwise
`FilledButton.tonal` (neutral gray), `OutlinedButton`, `TextButton`; all
buttons radius 8, 40px min height, 2px focus ring on keyboard focus; flat
outlined cards (`Card` has no shadow even with `elevation:`); neutral chips;
dialogs/sheets/menus on `AppColors.card` with a hairline; floating inverse
snackbars; desktop scrollbars thin and quiet; rail/bottom bar on
`AppColors.sidebar` with a neutral indicator.

**Widgets** (`lib/core/widgets/`)

| Widget | Use |
|---|---|
| `SectionHeader(title:, count?, subtitle?, trailing?)` | Quiet heading above a group; `trailing` is usually a `TextButton`/`IconButton` |
| `EmptyState(icon:, title:, message?, action?, compact = false)` | Line icon + text; `compact` for inline use inside sections |
| `ErrorView`, `NotFoundView`, `AsyncValueView(value:, data:, onRetry?, loading?)` | As before; `loading:` e.g. `const LoadingSkeleton()` |
| `AppCard(child:, onTap?, onLongPress?, accentColor?, selected, padding = Insets.card, margin)` | Flat outlined card; hover darkens border, focus ring |
| `ListRowTile(title:, leading?, subtitle?, trailing?, actions = [], onTap?, selected, dense)` | Compact row; `actions` appear on hover/focus on desktop/web, always on touch |
| `SubjectColorDot(color: subject.color, fallback?, size = 10, semanticLabel?)` | Subject accent (null color = hollow ring) |
| `InfoBanner(message:, title?, kind: InfoBannerKind.info/success/warning/error, action?, onDismiss?)` | Inline callout |
| `LockedFeature(child:, locked = true, onTap?, tooltip?)` | Wrap AI entry points: dims + disables child, lock badge (`LockedFeature.badgeKey`), whole area taps `onTap` (e.g. open the "Set up AI" sheet). `locked: false` returns `child` untouched |
| `ContentContainer(child:, maxWidth = ContentWidth.readable, padding?)` | Top-centered capped column with responsive gutter (16 / 24) |
| `ResponsiveScaffold(body:, appBar?, maxWidth, scrollable = false, padding?, floatingActionButton?)` | Scaffold + ContentContainer; `scrollable` scrolls full-width with page padding |
| `KeyboardShortcutHint(keys: ['Ctrl','K'], label?)` / `.activator(SingleActivator(...))` | Keycaps; `.activator` shows `⌘ ⇧` on Apple, `Ctrl Shift` elsewhere |
| `LoadingSkeleton(rows = 3, leading, subtitle, animate = true)`, `SkeletonBox` | Pulsing placeholder rows. Tests: use `pump()` or `animate: false` (pulse never settles) |
| `Breakpoints.medium 720 / expanded 1000`, `Breakpoints.gutter(context)`, `MaxWidth` | As before |
| `SyncStatusButton`, `SyncStatusTile`, `SyncStatusBanner` | Sync indicator (icon button / sidebar row / phone strip) |

```dart
ResponsiveScaffold(
  appBar: AppBar(title: Text(subject.title)),
  maxWidth: ContentWidth.wide,
  scrollable: true,
  body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    SectionHeader(
      title: 'Notes', count: notes.length,
      trailing: TextButton.icon(onPressed: newNote,
          icon: const Icon(Icons.add, size: 18), label: const Text('New')),
    ),
    if (notes.isEmpty)
      const EmptyState(compact: true, icon: Icons.description_outlined,
          title: 'No notes yet')
    else
      for (final n in notes)
        ListRowTile(
          leading: SubjectColorDot(color: subject.color),
          title: Text(n.title),
          subtitle: Text('Edited ${formatRelativeTime(n.updatedAt)}'),
          onTap: () => context.push(AppRoutes.note(n.id)),
          actions: [IconButton(tooltip: 'More', icon: const Icon(Icons.more_horiz), onPressed: () {})],
        ),
    Gaps.h16,
    LockedFeature(
      locked: !aiReady,
      tooltip: 'Set up AI to generate',
      onTap: () => showSetUpAiSheet(context),
      child: FilledButton.tonalIcon(onPressed: generate,
          icon: const Icon(Icons.auto_awesome_outlined), label: const Text('Generate quiz')),
    ),
  ]),
)
```

**AppShell**: phones (< 720) use a bottom `NavigationBar` (hairline top
border) plus the offline/error `SyncStatusBanner`; >= 720 a sidebar-style
`NavigationRail` (app mark, destinations, sync status + sign-out pinned at the
bottom), extended with the app name and labels from 1000px. Feature screens
should not add their own outer navigation; use a flat `AppBar` (no tint) and
`ResponsiveScaffold`/`ContentContainer` for width.
