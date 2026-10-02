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
| `Subject` : Syncable | `id, ownerId, title, description?, color? (int ARGB32), pinned (default false), archivedAt?, createdAt, updatedAt, deletedAt?`; ext `isArchived` (pin/archive: Wave 3) |
| `Note` : Syncable | `id, subjectId, ownerId, title, contentMd (default ''), tags (List<String>, default []), pinned (default false), createdAt, updatedAt, deletedAt?` (tags/pinned: Wave 3) |
| `Quiz` : Syncable | `id, subjectId, noteId?, ownerId, title, description?, source? (QuizSource), questions (List<Question>, default []), tags (default []), pinned (default false), createdAt, updatedAt, deletedAt?` |
| `Question` | `id, type (QuestionType), prompt, options (List<String>), correctIndices (List<int>), answerText?, explanation?` |
| `QuestionType` | `mcqSingle 'mcq_single'`, `mcqMulti 'mcq_multi'`, `trueFalse 'true_false'`, `shortAnswer 'short_answer'`; `wireName`, `hasOptions` |
| `QuizSource` | `contextText?, youtubeUrl?, provider? (LlmProviderId.wireName), model?, notes (List<QuizSourceRef{id, name}>, default []), attachments (List<QuizSourceRef>, default [])` (Wave 1: notes/attachments used as AI sources) |
| `QuizAttempt` : Syncable | `id, quizId, ownerId (the attempting user), answers (List<QuestionAnswer>), score (double), total (int), startedAt, completedAt?, mode (AttemptMode, default practice), timeLimitSeconds?, questionIds? (List<String>), durationSeconds?, createdAt, updatedAt, deletedAt?` (exam fields: Wave 2) |
| `AttemptMode` | `practice`, `exam`, `mistakes` (JSON = name; missing/unknown -> practice) |
| `QuestionAnswer` | `questionId, selectedIndices (List<int>), textAnswer?, isCorrect? (null = ungraded)` |
| `Share` | `id, ownerId, recipientId, resourceType (ShareResourceType), resourceId, createdAt`; read-only joins (not in `toJson`): `recipient? (Profile), owner? (Profile), resourceTitle?` |
| `ShareResourceType` | `subject`, `note`, `quiz`, `deck` (JSON = name; `deck` since Wave 2) |
| `Deck` : Syncable | `id, subjectId, noteId?, ownerId, title, description?, source? (QuizSource), cards (List<Flashcard>), tags (default []), pinned (default false), createdAt, updatedAt, deletedAt?` |
| `Chat` : Syncable | `id, ownerId, scopeType (ChatScopeType: subject, note, attachment, general; JSON = name, unknown -> general), scopeId? (null iff general), title (default ''), provider?, model?, createdAt, updatedAt, deletedAt?` (Wave 3, private) |
| `ChatMessage` : Syncable | `id, chatId, ownerId, role (ChatRole: user, assistant, system; unknown -> system), content (default ''), citations (List<ChatCitation{type, id, title (default ''), snippet?}>, default []), createdAt, updatedAt, deletedAt?` |
| Tags (`tags.dart`) | `normalizeTag(s)` / `normalizeTags(list)` (trim, collapse spaces, lowercase, strip `#`, cut to 64, dedupe); `TagRules.maxTags` 50, `maxTagLength` 64 |
| `Flashcard` | `id, front, back, hint?` (`id` stable, unique in the deck, <= 255 chars) |
| `CardReview` : Syncable | `id (uuid v5, CardReview.idFor), ownerId, deckId, cardId, state (CardState), dueAt, stability, difficulty, elapsedDays, scheduledDays, reps, lapses, lastReviewAt?, createdAt, updatedAt, deletedAt?`; `toFsrs()`, `withFsrs(card)` |
| `CardState` / `Rating` | `lib/study/fsrs.dart` (re-exported by `card_review.dart`): `newCard 0, learning 1, review 2, relearning 3` (JSON = int); `again 1, hard 2, good 3, easy 4` |
| `Mistake` : Syncable | `id (uuid v5, Mistake.idFor), ownerId, quizId, questionId, wrongCount, correctStreak, lastWrongAt?, resolvedAt?, createdAt, updatedAt, deletedAt?`; `isOpen`, `resolveAfterCorrect = 2` |
| `OutboxOp` | `id, table (String), op (OutboxOpType), rowId, payload? (Map), createdAt, attempts (default 0), lastError?` |
| `OutboxOpType` | `upsert`, `delete` (hard delete, reserved), `uploadImage 'upload_image'`, `deleteImage 'delete_image'`, `uploadAttachment 'upload_attachment'`, `deleteAttachment 'delete_attachment'` |
| `SyncTables` | `subjects, notes, quizzes, quizAttempts='quiz_attempts', shares, profiles, attachments, decks, cardReviews='card_reviews', mistakes, noteImagesBucket='note-images', attachmentsBucket='attachments'`; `chats`, `chatMessages='chat_messages'` (Wave 3); `synced` = [subjects, notes, quizzes, quiz_attempts, attachments, decks, card_reviews, mistakes, chats, chat_messages]; `privateStudy` = {card_reviews, mistakes}; `privateChats` = {chats, chat_messages} |
| `Attachment` : Syncable | `id, subjectId, ownerId, name, mimeType?, sizeBytes (default 0), kind (AttachmentKind, default other), storagePath, extractedText?, createdAt, updatedAt, deletedAt?`; `fileName` (last path segment); statics `maxSizeBytes` (50 MiB), `maxExtractedTextLength` (200 000), `maxNameLength` (512), `buildStoragePath(...)`, `sanitizeFileName(name)` |
| `AttachmentKind` | `pdf, image, text, docx, audio, video, other` (JSON = name, unknown -> other); `AttachmentKind.detect(fileName:, mimeType?)` (extension first, then MIME). Top-level helpers `fileExtension(name)`, `mimeTypeForFileName(name)` |
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
- `shares(id, owner_id, recipient_id -> profiles, resource_type text check in ('subject','note','quiz','deck'), resource_id uuid, created_at)` (`'deck'` since Wave 2, see *Study*) unique (resource_type, resource_id, recipient_id).
- `owner_id` defaults to `auth.uid()`; `updated_at` is set by a trigger (`now()`) on insert/update and drives the sync cursor; client-provided `id` and `created_at` are accepted.
- RPCs (`lib/data/remote/supabase_api.dart` `SupabaseRpc`):
  `find_user_by_email(p_email text) returns table(id uuid, display_name text, email text)` (confirmed-email users only; shares to unconfirmed users are rejected with `42501`);
  `copy_subject(p_subject_id uuid) returns uuid`;
  `copy_note(p_note_id uuid, p_target_subject_id uuid) returns uuid`;
  `copy_quiz(p_quiz_id uuid, p_target_subject_id uuid, p_target_note_id uuid default null) returns uuid`.
- Storage bucket `note-images`, object path `{owner_id}/{note_id}/{uuid}.{ext}`.
- `attachments(...)` + Storage bucket `attachments`: see *Attachments* below.
- `decks`, `card_reviews`, `mistakes`, `copy_deck`, exam-mode columns on `quiz_attempts`: see *Study (Wave 2)* below.
- `chats`, `chat_messages`, `tags`/`pinned` on notes/quizzes/decks, `pinned`/`archived_at` on subjects: see *Wave 3 schema* below.

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

### Study (Wave 2) (backend: `supabase/migrations/20261005000000_study.sql`)

All three new tables are synced tables with the usual conventions: client
`id` (uuid) + `created_at`; `owner_id` defaults to `auth.uid()` and is
immutable (`42501`); `updated_at` is server `now()` (sync cursor, keyset like
the others); soft delete via `deleted_at`; upsert with `onConflict: 'id'`.

**Table `public.decks`** — flashcard decks. Shared, synced and copied exactly
like `quizzes`.

| Column | Type | Rules |
|---|---|---|
| `id` | uuid pk | client-generated |
| `subject_id` | uuid not null → subjects (on delete cascade) | must exist (`23503`) and be owned by the deck owner (`42501`); **overwritten with the note's subject when `note_id` is set** (moving a note moves its decks) |
| `note_id` | uuid null → notes (on delete cascade) | must exist (`23503`) and be owned by the deck owner (`42501`) |
| `owner_id` | uuid not null default `auth.uid()` | immutable |
| `title` | text not null | |
| `description` | text null | |
| `source` | jsonb null | JSON object or null (`23514`); same shape as `QuizSource` (`context_text`, `youtube_url`, `provider`, `model`) |
| `cards` | jsonb not null default `[]` | array of `{"id": text, "front": text, "back": text, "hint"?: text \| null}`; `id` 1..255 chars and **unique within the deck**; extra keys allowed (`23514` otherwise) |
| `created_at`, `updated_at`, `deleted_at` | timestamptz | as other synced tables |

Card `id`s are stable keys (generate a uuid v4 string per card, keep it when
editing front/back); `card_reviews` reference them. `copy_*` keep card ids.

Read access (`can_read_deck(p_deck_id uuid) returns boolean`): owner
(including own tombstones), or the deck, its subject and (if any) its note
are not soft-deleted and the caller holds a share from the deck owner on the
**deck**, its **subject** or its **note**. Writes: owner only.

**Table `public.card_reviews`** — private per-user spaced-repetition state
(FSRS-ready). Never shared; SELECT/UPDATE/DELETE owner only. INSERT also
requires `can_read_deck(deck_id)` (`42501`), so users review their own decks
and decks shared with them.

| Column | Type | Rules |
|---|---|---|
| `id` | uuid pk | see *Deterministic ids* below |
| `owner_id` | uuid not null default `auth.uid()` | the reviewing user; immutable |
| `deck_id` | uuid not null → decks (on delete cascade) | immutable (`42501`) |
| `card_id` | text not null | 1..255 chars; `cards[].id`; immutable (`42501`) |
| `state` | smallint not null default 0 | 0 new, 1 learning, 2 review, 3 relearning (FSRS `State`), `23514` otherwise |
| `due_at` | timestamptz not null default now() | |
| `stability`, `difficulty` | double precision not null default 0 | ≥ 0 |
| `elapsed_days`, `scheduled_days`, `reps`, `lapses` | integer not null default 0 | ≥ 0 |
| `last_review_at` | timestamptz null | |
| `created_at`, `updated_at`, `deleted_at` | timestamptz | |

Unique `(owner_id, deck_id, card_id)` → `23505` on a second row for the same card.

**Table `public.mistakes`** — private per-user wrong-answer tracking (the
Mistakes practice set). Never shared; owner only; INSERT also requires
`can_read_quiz(quiz_id)` (`42501`).

| Column | Type | Rules |
|---|---|---|
| `id` | uuid pk | see *Deterministic ids* |
| `owner_id` | uuid not null default `auth.uid()` | immutable |
| `quiz_id` | uuid not null → quizzes (on delete cascade) | immutable (`42501`) |
| `question_id` | text not null | 1..255 chars; `questions[].id`; immutable (`42501`) |
| `wrong_count` | integer not null default 0 | ≥ 0 |
| `correct_streak` | integer not null default 0 | ≥ 0 (consecutive correct answers since the last wrong one) |
| `last_wrong_at` | timestamptz null | |
| `resolved_at` | timestamptz null | set when the user masters it (e.g. streak reached); null = still in the set |
| `created_at`, `updated_at`, `deleted_at` | timestamptz | |

Unique `(owner_id, quiz_id, question_id)` → `23505`.

**Exam mode: new `quiz_attempts` columns** (additive; old clients keep working,
an upsert that omits them leaves them untouched):

| Column | Type | Rules |
|---|---|---|
| `mode` | text not null default `'practice'` | `practice`, `exam` or `mistakes` (`23514`) |
| `time_limit_seconds` | integer null | > 0 |
| `question_ids` | jsonb null | JSON array of question ids served (the random subset of a pool, in order); null = all questions |
| `duration_seconds` | integer null | ≥ 0, time actually spent |

A `mistakes`-mode attempt is recorded against a single `quiz_id` (one attempt
per quiz practised in a mixed session, or none: mistakes themselves are
tracked in `mistakes`).

**Sharing**: `ShareResourceType` gains `deck` (JSON `'deck'`). Share a deck
with `shares.insert({recipient_id, resource_type: 'deck', resource_id})`
(owner of a live deck under live parents, confirmed recipient, else `42501`).
`share_details.resource_title` includes deck titles. Soft- or hard-deleting a
deck deletes its shares. Older builds that do not know `deck` must ignore
such share rows instead of failing to parse.

**RPCs**
- `can_read_deck(p_deck_id uuid) returns boolean`.
- `copy_deck(p_deck_id uuid, p_target_subject_id uuid, p_target_note_id uuid default null) returns uuid`
  — same rules as `copy_quiz` (readable, live source → else `P0002`; target
  subject owned and live, optional target note owned, live and in that
  subject → else `42501`). Copies `title, description, source, cards`;
  review state is not copied.
- `copy_subject` now also copies live subject-level decks; `copy_note` (and
  therefore `copy_subject` for each note) also copies the note's live decks
  (`note_id` remapped).
- Fixed: `copy_note` / `copy_quiz` (and `copy_deck`) now work for recipients
  of a direct note/quiz/deck share who cannot see the parent subject (they
  previously returned `P0002`).

**Sync notes for the data layer**
1. *Tables*: add `decks`, `card_reviews`, `mistakes` to `SyncTables.synced`
   (pull by `updated_at` cursor, push via the outbox, `onConflict: 'id'`).
   `decks` is a shared table (same handling as `quizzes`: owned rows +
   rows readable through shares, reconcile ids of non-owned cached decks on
   each sync since recipients never get tombstones). `card_reviews` and
   `mistakes` are private: the server only ever returns the caller's own rows
   (including own tombstones), so no reconciliation is needed.
2. *New shares*: when a `subject`, `note` or `deck` share appears, fetch
   `decks` for that resource (`subject_id` / `note_id` / `id`) without the
   cursor, as for quizzes.
3. *Deterministic ids* (important): because of the unique keys, two devices
   creating the row for the same card/question offline would collide
   (`23505`). Derive the id instead of using v4:
   `card_reviews.id = const Uuid().v5(Namespace.url.value, 'quizapp:card_review:{owner_id}:{deck_id}:{card_id}')`,
   `mistakes.id = const Uuid().v5(Namespace.url.value, 'quizapp:mistake:{owner_id}:{quiz_id}:{question_id}')`
   (package `uuid` 4.x)
   (lowercase uuids). Every device then upserts the same row (last write
   wins on `updated_at`). Should a `23505` still occur, pull the existing row
   by `(deck_id, card_id)` / `(quiz_id, question_id)`, adopt its id and
   re-apply the change; never retry blindly.
4. *Revocation*: when a deck/quiz stops being readable, the user's
   `card_reviews` / `mistakes` rows stay (server keeps them); the client
   should hide rows whose deck/quiz is not in the local cache (not delete
   them). New inserts for an unreadable deck/quiz fail with `42501`: drop the
   outbox op. A hard-deleted deck/quiz cascades on the server, rows vanish
   without tombstones; purge locally when the parent is gone.
5. *Card removal*: deleting a card from `decks.cards` does not touch
   `card_reviews`; ignore reviews whose `card_id` is no longer in the deck
   (optionally soft-delete them).
6. *Due queue*: "due today" = own `card_reviews` with `deleted_at is null`
   and `due_at <= end of today`, joined locally to cached decks (cards
   without a review row are `new`). Server index `(owner_id, due_at)`
   exists if a remote query is ever needed.
7. *Errors*: `42501` (not owner / not readable / immutable key), `23514`
   (bad cards JSON, `state`, `mode`, negative counters), `23505` (duplicate
   review/mistake key, see 3), `23503` (parent not synced yet: defer).

### Study client API (Wave 2, data layer — implemented)

Code: models in `lib/data/models/{deck,card_review,mistake}.dart`; repositories
in `lib/data/repositories/` (`DeckRepository`, `ReviewRepository`,
`MistakeRepository`, `StudyActivityRepository` + `Local*` impls); pure logic
in `lib/study/` (`fsrs.dart`, `due_queue.dart`, `stats.dart`, `exam.dart`,
`local_day.dart`, `study_settings.dart`); dashboard provider in
`lib/study/study_providers.dart`. `lib/study/*.dart` (except the providers
file) is pure Dart, no Flutter/Hive.

```dart
abstract interface class DeckRepository {     // own + shared; shared = read-only
  Stream<List<Deck>> watchBySubject(String subjectId);   // incl. note decks, updatedAt desc
  Stream<List<Deck>> watchByNote(String noteId);
  Stream<List<Deck>> watchAllAccessible();
  Stream<Deck?> watchById(String id);
  Future<Deck?> getById(String id);
  Future<Deck> create({required String subjectId, String? noteId, required String title,
      String? description, List<Flashcard> cards = const [], QuizSource? source});
  Future<Deck> update(Deck deck);               // cards/title/...; same parent rules as quizzes
  Future<void> delete(String id);               // soft; review rows kept (hidden)
}
abstract interface class ReviewRepository {    // private FSRS state of the current user
  Future<CardReview> recordReview({required String deckId, required String cardId, required Rating rating});
  Future<Map<Rating, DateTime>> previewDue({required String deckId, required String cardId}); // button labels
  Stream<DueQueue> watchDue({DateTime? now, String? deckId});   // "Due today"
  Stream<int> watchDueCount({DateTime? now});
  Stream<DeckStats> watchDeckStats(String deckId, {DateTime? now});
  Stream<List<CardReview>> watchAll();          // live rows of readable decks
  Future<void> resetCard({required String deckId, required String cardId});  // back to new
}
abstract interface class MistakeRepository {   // private "Mistakes" set
  Future<Mistake?> recordAnswer({required String quizId, required String questionId, required bool correct});
  Future<void> recordAttempt(QuizAttempt attempt);  // every graded answer of an attempt
  Stream<List<MistakeGroup>> watchOpen();       // grouped by quiz, newest wrong first
  Stream<int> watchOpenCount();
  Future<void> resolve({required String quizId, required String questionId});  // "I know this"
}
// MistakeGroup { Quiz quiz; List<MistakeEntry> entries; List<Question> questions; DateTime? lastWrongAt }
// MistakeEntry { Mistake mistake; Question question }
abstract interface class StudyActivityRepository { Stream<StudySnapshot> watchSnapshot(); }
```

**Flashcards / FSRS** (`lib/study/fsrs.dart`): FSRS-5 (19 default weights,
FSRS-4.5-compatible formulas), desired retention 0.9, learning steps 1m/10m,
relearning step 10m, max interval 36 500 days, optional fuzz. Verified
against py-fsrs 5.1.3 (`test/study/fsrs_reference_data.dart`).
`Fsrs({weights, desiredRetention, learningSteps, relearningSteps,
maximumInterval, enableFuzz = false, random})`, `review(FsrsCard, Rating,
DateTime now) -> FsrsCard`, `preview(card, now)`, `retrievability(card,
now)`, `nextIntervalDays(stability)`, `currentStep(card)`. Never-reviewed
cards are `CardState.newCard`; the (re)learning step is not stored (no
column) but derived from `due - lastReview` (steps must be strictly
increasing). `reps++` per review, `lapses++` on review -> again.
- `recordReview` uses `StudySettings` (`newCardsPerDay` default 20,
  `desiredRetention` 0.9, `fuzz` true; Hive `prefs` key `study_settings`;
  `ref.read(studySettingsProvider.notifier).setNewCardsPerDay(n)` /
  `setDesiredRetention(r)` / `set(settings)`). Works on own and shared decks
  (the row is the user's); `NotFoundException` if the deck or card is gone.
- Row id = `CardReview.idFor(ownerId:, deckId:, cardId:)` (uuid v5 per the
  contract above), so devices converge; an existing row with another id for
  the same card (adopted after a `23505`) is reused.
- `DueQueue { dueNow, newCards, laterToday, newIntroducedToday,
  newRemainingToday, unseenTotal; all, count, next, isEmpty }`: `dueNow` =
  reviewed cards with `dueAt <= now` (oldest first), `newCards` = unseen
  cards in deck order (decks by `createdAt`) limited to `newCardsPerDay`
  minus rows first created today, `laterToday` = due later today (learning
  steps). Study order = `all`; show `next` (null = nothing due right now).
  "Today" = local calendar day (`lib/study/local_day.dart`; repositories
  accept `toLocal` for tests). Reviews of removed cards and of decks that
  aren't live/cached are ignored (rows kept). `DueCard { deck, card,
  review?, isNew, dueAt, state, key }`.
- `DeckStats { total, newCount, learning, review, mature (interval >= 21 d),
  dueToday, lapses }`.

**Mistakes**: `recordAnswer` — wrong: upsert `wrongCount++`,
`correctStreak = 0`, `resolvedAt = null`, `lastWrongAt = now` (creates the
row, id `Mistake.idFor(...)`); correct while open: `correctStreak++`,
resolved after 2 consecutive correct; correct with no open row: no write.
Call `recordAttempt(attempt)` after saving any completed attempt (practice,
exam or mistakes mode). `watchOpen` resolves questions from the cached quiz
(hidden when the quiz isn't cached or the question was removed). A
mistakes-practice session: take `group.questions` and start an attempt per
quiz with `mode: AttemptMode.mistakes, questionIds: [...]`.

**Exam mode** (`lib/study/exam.dart`): `selectQuestionPool(questions,
{count, random})` (random N, seedable) -> `attempts.start(quizId:, total:
pool.length, mode: AttemptMode.exam, timeLimitSeconds:, questionIds: ids)`;
`questionsForAttempt(quiz, attempt)`, `gradeAnswer(question, answer)`,
`scoreExam(questions, answers) -> (answers: graded, score: ExamScore{correct,
total, answered, ungraded, unanswered, fraction, percent})`,
`examTimeRemaining(attempt, now)`, `isExamExpired`, `examDurationSeconds`,
`completeExam(attempt, questions:, answers:, now:)` (sets answers, score,
total, completedAt, durationSeconds) -> `attempts.save(...)`.

**Dashboard** (`dashboardStatsProvider`; pure `computeDashboard(snapshot,
now:, newCardsPerDay:)` in `lib/study/stats.dart`): `DashboardStats { streak
(StreakInfo{current, longest, activeToday}), quizzesTaken, overallAccuracy
(Accuracy{correct, answered, ratio}), accuracyBySubject
(List<SubjectAccuracy{subjectId, title, color, accuracy, attempts}>, by
title), weakestQuestions (List<WeakQuestion{quizId, quizTitle, subjectId,
questionId, prompt, accuracy}>, >= 2 answers, lowest first, max 5),
weakestQuizzes (List<WeakQuiz>), due (DueQueue), dueCards, reviewsToday,
openMistakes, recentActivity (List<ActivityItem>: sealed, QuizActivity{attempt,
quizTitle, subjectId, mode, at} | ReviewActivity{deckId, deckTitle,
subjectId, day, cards, at}, newest first, max 20) }`. Streak days = local
days with a completed attempt (or an answered in-progress one) or a card
review; only the first and last review day of each card is stored, so
review-only streaks can undercount. The individual functions
(`computeStreak`, `activityDays`, `accuracyBySubject`, `weakestQuestions`,
`weakestQuizzes`, `recentActivity`, `quizzesTaken`, `overallAccuracy`) are
public.

**Sync of the new tables** (`DefaultSyncEngine`): `decks`, `card_reviews`,
`mistakes` are pulled/pushed like the others (own keyset cursors). Decks are
shared like quizzes: a subject share backfills decks by `subject_id`, a note
share by `note_id`, a deck share by id; reconciliation covers decks; other
users' tombstones are purged, own ones kept. Soft-deleting a subject/note
cascades to its owned decks; moving a note moves its decks. Private rows: a
`23505` on a `card_reviews`/`mistakes` upsert fetches the row holding the
natural key, re-keys the local row to its id (keeping `created_at`) and
re-pushes; a `42501` (deck/quiz no longer readable) drops the op quietly (no
rejection reported). Reconciliation purges own review/mistake rows whose
deck/quiz is not cached **and** that the server no longer returns (parent
hard-deleted, or the row was never accepted); rows the server keeps (access
revoked) stay hidden. `copyToMyAccount(resourceType: ShareResourceType.deck,
resourceId:, targetSubjectId:, targetNoteId?)` calls `copy_deck`. Share rows
of unknown resource types are ignored by `sharedWithMe` / `listSharesFor`.

### Wave 3 schema (backend: `supabase/migrations/20261006000000_wave3.sql`)

**AI chats** — `chats` and `chat_messages` are synced tables with the usual
conventions (client `id` uuid v4 + `created_at`; `owner_id` defaults to
`auth.uid()`, immutable `42501`; `updated_at` = server `now()`, keyset
cursor; soft delete via `deleted_at`; upsert `onConflict: 'id'`). They are
**private**: every operation is owner-only, they are never shared (no share
resource type), and recipients of a shared subject/note never see the
owner's chats (nor the owner theirs). The server only ever returns the
caller's own rows (including own tombstones), so no reconciliation is needed.

Table `public.chats`:

| Column | Type | Rules |
|---|---|---|
| `id` | uuid pk | client-generated |
| `owner_id` | uuid not null default `auth.uid()` | immutable |
| `scope_type` | text not null default `'general'` | `subject`, `note`, `attachment` or `general`; **immutable** (`42501`) |
| `scope_id` | uuid null | the subject / note / attachment id; **null iff `general`**; **immutable** (`42501`); no FK (the chat survives a hard delete of its scope) |
| `title` | text not null default `''` | ≤ 500 chars |
| `provider` | text null | AI provider name (e.g. `ProviderId` JSON), ≤ 255 chars |
| `model` | text null | model id, ≤ 255 chars |
| `created_at`, `updated_at`, `deleted_at` | timestamptz | as other synced tables |

INSERT also requires the scope to be readable by the caller, else `42501`:
`general` → no scope; `subject` → `can_read_subject(scope_id)`; `note` →
`can_read_note(scope_id)`; `attachment` → `can_read_attachment(scope_id)`
(owner, or a live attachment of a subject the caller can read — subject
shares only). Malformed scopes (unknown type, `general` with an id, scoped
without one) are also `42501` through the API (RLS runs before the CHECK).
Owners may create chats on their own soft-deleted items (offline sync);
recipients only on live, shared ones.

Table `public.chat_messages`:

| Column | Type | Rules |
|---|---|---|
| `id` | uuid pk | client-generated |
| `chat_id` | uuid not null → chats (on delete cascade) | chat must exist (`23503`: push the chat first / defer) and be owned by the caller (`42501`); **immutable** (`42501`) |
| `owner_id` | uuid not null default `auth.uid()` | immutable |
| `role` | text not null | `user`, `assistant` or `system` (`23514`) |
| `content` | text not null default `''` | ≤ 200 000 chars (`23514`) |
| `citations` | jsonb not null default `[]` | array of `{"type": text 1..64, "id": text 1..255, "title": text, "snippet"?: text \| null}`; extra keys allowed (`23514` otherwise) |
| `created_at`, `updated_at`, `deleted_at` | timestamptz | order messages by `created_at` (then `id`) |

Citation `type` is free text; suggested values `subject`, `note`,
`attachment`, `quiz`, `deck`, `web`; `id` is the cited row's uuid (or a URL
for `web`).

Sync / lifecycle notes:
1. Add `chats`, `chat_messages` to the synced tables (own cursors). Push a
   chat before its messages (FIFO outbox).
2. Soft-deleting a chat does **not** cascade on the server: also push
   tombstones for its messages (or ignore/purge messages of a deleted chat
   locally). A hard delete of a chat cascades to its messages.
3. When the scope becomes unreadable (share revoked, scope soft-/hard-deleted)
   the user keeps the chat and may keep adding messages to it; only new chats
   on that scope fail (`42501`: drop the outbox op). Show such chats as
   "source unavailable" (the AI can no longer read the source content).
4. Errors: `42501` (not owner, unreadable scope, immutable column), `23514`
   (bad role / citations / lengths), `23503` (chat not synced yet: defer).

**Organization columns** (additive, defaulted; older clients that omit them
in upserts leave them untouched):

| Table | Column | Type | Rules |
|---|---|---|---|
| `notes`, `quizzes`, `decks` | `tags` | text[] not null default `'{}'` | ≤ 50 tags, each non-blank, ≤ 64 chars, no nulls (`23514`); normalize client-side (trim, lowercase, dedupe) |
| `notes`, `quizzes`, `decks` | `pinned` | boolean not null default false | |
| `subjects` | `pinned` | boolean not null default false | |
| `subjects` | `archived_at` | timestamptz null | null = active; set to archive, null again to unarchive |

Subjects have no `tags`. GIN indexes exist on `tags` (server filters
`tags=cs.{x}` / `tags=ov.{x,y}`), but search/sort/filter is expected to run on
the local cache. These are properties of the row, i.e. the **owner's**
values: only the owner can change them (a recipient's update is a silent
no-op, as for any shared row), and recipients see the owner's tags / pin /
archive state read-only. A personal per-user pin or archive of items shared
with me is **out of scope** (would need a per-user table); the client may
keep such preferences locally only. Archiving does not affect sharing,
access or copying; `deleted_at` stays the only "trash".

**Copies**: `copy_subject`, `copy_note`, `copy_quiz`, `copy_deck` copy
`tags` of every copied note/quiz/deck. `pinned` and `archived_at` are not
copied (copies start unpinned and unarchived). Chats are never copied.

### Wave 3 client API (data layer, search, import/export — implemented)

Code: models `lib/data/models/{chat,tags}.dart` (+ `tags`/`pinned` on
`Note`/`Quiz`/`Deck`, `pinned`/`archivedAt` on `Subject`); repositories
`lib/data/repositories/{chat_repository,local_chat_repository,organization_repository,local_organization_repository}.dart`;
search `lib/search/` (pure Dart except `search_providers.dart`); import /
export `lib/io/` (pure Dart: strings / bytes in and out; saving or picking
files is the UI's job). New model fields are defaulted, so old Hive rows
and server rows without them decode (`tags: []`, `pinned: false`,
`archivedAt: null`) and every upsert now sends them (a server without the
Wave 3 migration keeps those ops queued: see *Server schema out of date*
in *Data layer notes*).

**Chats** (private, never shared):

```dart
abstract interface class ChatRepository {
  Stream<List<Chat>> watchAll();                                   // mine, updatedAt desc (touched on every saved message)
  Stream<List<Chat>> watchByScope(ChatScopeType type, String? scopeId);
  Stream<Chat?> watchById(String id);  Future<Chat?> getById(String id);
  Stream<List<ChatMessage>> watchMessages(String chatId);          // createdAt asc, then id; drafts included
  Future<List<ChatMessage>> getMessages(String chatId);
  Future<Chat> create({required ChatScopeType scopeType, String? scopeId, String title = '',
      String? provider, String? model});
  Future<Chat> rename(String chatId, String title);
  Future<Chat> setModel(String chatId, {String? provider, String? model});
  Future<void> delete(String chatId);                              // tombstones the chat AND every message
  Future<ChatMessage> addMessage({required String chatId, required ChatRole role,
      String content = '', List<ChatCitation> citations = const [], bool draft = false});
  Future<ChatMessage> updateMessage(ChatMessage m, {bool finalize = true}); // content + citations
  Future<void> deleteMessage(String messageId);
  Future<int> finalizeDrafts();                                    // push leftover drafts (app start)
}
```

- `create`: `scopeId` null iff `general` (`ValidationException`); the scope
  must be cached and live (own or shared subject / note / attachment, else
  `NotFoundException`). Title trimmed and cut to 500 chars, provider / model
  to 255; content cut to 200 000; citations with an empty or too long
  `type` (> 64) / `id` (> 255) are dropped. Other users' chats are
  invisible (`getById` null) and read-only (`PermissionDeniedException`).
- **Streaming**: `var m = await repo.addMessage(chatId: id, role:
  ChatRole.assistant, draft: true);` then per chunk `m = await
  repo.updateMessage(m.copyWith(content: m.content + chunk), finalize:
  false)` (Hive write only, **no outbox op**), finally `await
  repo.updateMessage(m.copyWith(citations: ...))` (one upsert + chat touch).
  Draft ids are kept in `sync_meta` (`chat_drafts`) so `finalizeDrafts()`
  can push a draft left behind by a killed app; `deleteMessage` / `delete`
  forget drafts.
- Sync: both tables are pulled / pushed like the others (own cursors, FIFO
  push: chat before its messages; a message whose chat isn't on the server
  yet waits on `23503`). Not reconciled (the server only returns own rows).
  `42501` on a chat insert (scope no longer readable) drops the op
  (recorded in `rejectedChanges`); the chat stays usable locally. Missing
  tables (`PGRST205`) -> ops kept, `serverOutdated` with
  `unavailableTables` `['chat_messages', 'chats']`.
- Providers: `chatRepositoryProvider`, `chatsProvider`,
  `chatsByScopeProvider((type: ChatScopeType.note, id: noteId))`,
  `chatProvider(id)`, `chatMessagesProvider(chatId)`.
- "Source unavailable": check the scope with `subjectProvider` /
  `noteProvider` / `attachmentProvider(chat.scopeId!)` (null = gone).

**Organization** (tags, pin, archive, filtered / sorted lists):

```dart
enum TaggableKind { note, quiz, deck }
enum ItemSort { recent /* updatedAt desc */, name /* title A-Z */, created /* createdAt desc */ }
enum ArchiveFilter { active, archived, all }
class ItemListQuery { String? subjectId; String? noteId; Set<String> tags /* all required */;
  bool pinnedOnly = false; bool includeArchived = false; bool ownedOnly = false;
  ItemSort sort = recent; bool pinnedFirst = true; copyWith(...); }        // value equality
class SubjectListQuery { ArchiveFilter archive = active; bool pinnedOnly = false;
  bool includeShared = false; ItemSort sort = name; bool pinnedFirst = true; }
class TagCount { String tag; int count; }

abstract interface class OrganizationRepository {
  Future<void> setTags(TaggableKind kind, String id, Iterable<String> tags);
  Future<void> addTag(TaggableKind kind, String id, String tag);
  Future<void> removeTag(TaggableKind kind, String id, String tag);
  Future<void> setPinned(TaggableKind kind, String id, bool pinned);
  Future<int> renameTag(String from, String to);   // own items; merges; returns #changed
  Future<int> deleteTag(String tag);
  Future<Subject> setSubjectPinned(String subjectId, bool pinned);
  Future<Subject> archiveSubject(String subjectId);    // archivedAt = now
  Future<Subject> unarchiveSubject(String subjectId);  // archivedAt = null
  Stream<List<Subject>> watchSubjects([SubjectListQuery q]);
  Stream<List<Note>> watchNotes([ItemListQuery q]);
  Stream<List<Quiz>> watchQuizzes([ItemListQuery q]);  // also: every readable quiz
  Stream<List<Deck>> watchDecks([ItemListQuery q]);
  Stream<List<TagCount>> watchTags({TaggableKind? kind, String? subjectId, bool includeArchived = false});
}
```

- Writes are owner-only (`PermissionDeniedException` on shared items),
  `NotFoundException` for missing ones, and **no-ops when nothing changes**
  (no outbox op). Tags are normalized (`normalizeTags`); > 50 ->
  `ValidationException`. `NoteRepository.update` etc. save whatever `tags`
  / `pinned` the passed model carries (edit with `copyWith`, they are kept).
- Lists: `pinnedFirst` puts pinned items first, each group in `sort` order
  (ties by id). Tag filter = item has **every** tag. With `subjectId` set,
  items of an archived subject are listed (the user opened it); without it
  they are hidden unless `includeArchived`. Shared items are included unless
  `ownedOnly`. Tag counts cover live readable items (own + shared),
  most-used first, then by name.
- **Archived subjects**: hidden from `SubjectRepository.watchAll` /
  `subjectsProvider` (now: active only, pinned first, then title), from the
  global study queue (`watchDue()` / `dueQueueProvider` /
  `dueCountProvider`; `watchDue(deckId:)` still works for a deck of an
  archived subject) and from the dashboard snapshot (their subjects /
  quizzes / decks are left out of per-subject accuracy, weakest lists, due
  cards and recent activity; the user's attempts and reviews still count for
  streak and totals). Still reachable by id (`subjectProvider(id)` etc.), in
  search, and via `archivedSubjectsProvider` /
  `SubjectListQuery(archive: ArchiveFilter.archived)`.
- Providers: `organizationRepositoryProvider`,
  `subjectListProvider(SubjectListQuery(...))`, `archivedSubjectsProvider`,
  `noteListProvider(ItemListQuery(...))`, `quizListProvider(...)`,
  `deckListProvider(...)`, `allTagsProvider` (all kinds, outside archived
  subjects), `tagCountsProvider((kind: TaggableKind.note, subjectId: id))`.

**Search** (`lib/search/`):

- `SearchIndex` (pure Dart, in memory): `upsert(SearchDocument)`,
  `remove(type, id)`, `search(query, {filters, limit = 50, now})`.
  Documents: `SearchDocument{type (SearchItemType: subject, note, quiz,
  deck, attachment, chat), id, title, body, tags, subjectId?, noteId?,
  ownerId?, updatedAt, pinned}`, built by `search_documents.dart`:
  subjects (title + description), notes (title + content without Markdown
  syntax, `plainTextFromMarkdown`), quizzes (title + description + prompts
  + options + expected answers), decks (title + description + fronts /
  backs / hints), attachments (name + `extractedText`), chats (title;
  `subjectId` = the scope's subject when known).
- Matching: tokens = Unicode letter / digit runs, lowercased, Latin
  diacritics folded (`é` -> `e`, `ß` -> `ss`), light plural stemming
  (`notes` -> `note`, `studies` -> `study`). **Every** query word must
  match (exact stem, or as a prefix of an indexed word when >= 2 chars:
  results while typing). `"quoted phrase"` = must occur in that order.
- Ranking: field weights (title 4, tag 3, body BM25-like) x smoothed idf;
  exact words beat prefix expansions; bonuses for an exact / leading title
  match, the query as a phrase (title > body), recency (half-life ~6 weeks)
  and pinned; archived items rank lower.
- `SearchFilters{types (empty = all), subjectId, tags (all required),
  includeArchived = true, pinnedOnly = false}`. Empty query + no filters
  -> `[]`; empty query + filters -> matching items, newest first (browse by
  tag / type).
- `SearchResult{document, score, titleHighlights, snippet,
  snippetHighlights (List<HighlightRange{start, end}>, offsets into
  `title` / `snippet`), matchedFields (title / tags / body), subjectTitle?,
  archived}` with `type`, `id`, `title` getters. Snippet: ~180 chars of the
  body around the first match (`…` marks cuts, newlines as spaces), or the
  body's beginning for title / tag-only hits.
- Live index: `LiveSearchIndex.attach(type:, source: stream, id:,
  toDocument:)` diffs each emitted list (by id, `identical` / `==`) and
  re-indexes only changed items. `searchIndexProvider` attaches subjects
  (all, incl. archived and shared), accessible notes, every quiz, every
  deck, every attachment and chats; kept alive 5 min after the last
  listener; rebuilt on account switch. `searchRevisionProvider` is loading
  until every source delivered once.
- UI: `ref.watch(searchProvider((query: text, filters: const
  SearchFilters(types: {SearchItemType.note}))))` ->
  `AsyncValue<List<SearchResult>>` (max 50). Widget tests override the
  repository providers it reads (subject / note / deck / attachment / chat /
  organization) or `searchProvider` itself.
- Performance (debug VM, `test/search/search_index_test.dart`): 10 000
  items index in ~1.5 s, ~20-35 ms per query, ~1 ms per incremental update.

**Import / export** (`lib/io/`, pure Dart):

| Function | Result |
|---|---|
| `noteToMarkdown(note, {subjectTitle, imageUrl})` | Markdown with YAML front matter (`title`, `subject`, `tags` as `["a", "b"]`, `created`, `updated`; strings double-quoted and escaped); `imageUrl(NoteImageRef)` rewrites `note-image://` links |
| `parseMarkdownNote(text, {fileName})` -> `MarkdownNote{title, body, tags, subject?}` | front matter subset (scalars, flow or block tag lists, `tags: a, b`); title fallback: `# heading`, file name, `Untitled` |
| `subjectToZip(subject, notes:, quizzes:, decks:, images:)` -> `Uint8List` | `<subject>/<note>.md`, `<subject>/quizzes/<title>.json`, `<subject>/decks/<title>.csv`, `<subject>/images/<noteId>-<file>` for `images` (keyed by `NoteImageRef.storagePath`; their links become relative); names via `safeFileName`, de-duplicated with ` (2)` |
| `quizToJson(quiz)` | lossless `{"format": "quiz_app.quiz", "version": 1, "quiz": Quiz.toJson() minus owner_id / subject_id / note_id / deleted_at}` |
| `quizToCsv(quiz)` | `type,prompt,options,correct,answer,explanation`; options `\|`-separated (escapes `\\|`, `\\\\`); `correct` = **1-based** option numbers, `\|`-separated |
| `importQuizJson(text, {newId, newIds = false})` | envelope, bare quiz object or bare question list (snake_case or camelCase); keeps unique question ids unless `newIds` |
| `importQuizCsv(text, {newId})` | header optional / any order (aliases `question`, `choices`, `correct_answer`, `answer_text`, ...); `,` `;` or tab detected; `correct` as 1-based numbers, letters (`A\|C`), option text or `true` / `false`; a `0` means 0-based (warning); type aliases (`single`, `multi`, `tf`, `short`, ...) or inferred |
| `deckToCsv(deck)` / `deckToAnkiTsv(deck)` | `front,back,hint` CSV / Anki "Notes in Plain Text" (`#separator:tab`, `#html:true`, `#columns:Front Back Hint`, `#tags:` from the deck's tags; HTML-escaped, newline -> `<br>`) |
| `importDeckText(text)` / `importDeckCsv` / `importDeckTsv` | auto-detects TSV (`#separator:` / `#html:` headers or tabs); optional `front,back[,hint]` header; Anki HTML -> text |
| `markdownToBlocks(md)` -> `List<MdBlock>` | for a UI-level PDF export: `MdHeading{level, spans}`, `MdParagraph`, `MdListItem{spans, depth, ordered, number?, checked?}`, `MdCode{text, language?}`, `MdQuote{children}`, `MdTable{header, rows}`, `MdRule`, `MdImage{url, alt}`, `MdMath{tex}`; `MdSpan{text, bold, italic, code, strike, link?, imageUrl?}` |

Imports return `ImportResult<T>{items, errors, warnings, title?,
description?, tags}` (`hasErrors`, `isEmpty`, `report` = one line per
issue). `ImportIssue{message, line? (1-based physical line where the row
starts; also for JSON syntax errors), field? (column or JSON path such as
`questions[2]`)}`. Invalid rows are skipped and reported; valid ones come
back with fresh ids (`newId`, default uuid v4). Validation follows the
question rules (prompt required; single / multi choice: 2..8 distinct,
non-empty options, exactly one / at least one correct index in range;
true/false options `True|False`; short answer needs an answer). Then create
the quiz / deck with the repositories (`create(..., questions:
result.items)`, `organization.setTags(...)` for `result.tags`).
Lower level: `encodeCsv` / `decodeCsv` (`CsvRow{line, fields}`,
`CsvFormatException{line}`) in `csv.dart`.

## Local storage (`lib/data/local/hive_boxes.dart`)

`HiveBoxes.init()` (called from bootstrap) runs `Hive.initFlutter('quiz_app')`,
`registerAdapters()` (intentionally empty) and opens every box as
`Box<String>`. **Values are `jsonEncode(model.toJson())` keyed by id** — no
TypeAdapters, so model changes never need Hive type-id migrations. Boxes:
`subjects`, `notes`, `quizzes`, `quiz_attempts`, `outbox` (OutboxOp JSON by op
id, FIFO by `createdAt`), `sync_meta` (cursors e.g. `cursor:{table}`), `prefs`
(non-secret prefs). `HiveBoxes.clearAll()` on sign-out. The data agent may add
boxes (e.g. image bytes cache) in `init()`. Added: `note_image_bytes`
(`Box<Uint8List>`, web image cache), `attachments` (`Box<String>`, user
scoped) and `attachment_bytes` (`LazyBox<Uint8List>`, web attachment cache;
native uses files under `{app support}/attachments`); Wave 2: `decks`,
`card_reviews`, `mistakes` (`Box<String>`, user scoped); `prefs` key
`study_settings`; Wave 3: `chats`, `chat_messages` (`Box<String>`, user
scoped), `sync_meta` key `chat_drafts` (local-only streaming drafts). Sign-out clearing is done by the sync engine (see Data
layer notes).

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
  Stream<List<Subject>> watchAll();             // own, active (not archived), pinned first, then title
  Stream<Subject?> watchById(String id);        // own or shared
  Future<Subject?> getById(String id);
  Future<Subject> create({required String title, String? description, int? color});
  Future<Subject> update(Subject subject);
  Future<void> delete(String id);               // soft, cascades to notes/quizzes
}

abstract interface class NoteRepository {
  Stream<List<Note>> watchBySubject(String subjectId);   // updatedAt desc
  Stream<List<Note>> watchAllAccessible();     // own + shared, live, updatedAt desc (note picker; added Wave 1)
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
  Future<QuizAttempt> start({required String quizId, required int total,
      AttemptMode mode = AttemptMode.practice, int? timeLimitSeconds,
      List<String>? questionIds});                      // exam params: Wave 2
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
}   // decks: like quizzes (targetSubjectId required, optional targetNoteId), see "Study client API"

abstract interface class AttachmentRepository {   // added Wave 1, see "Attachments (client)"
  static const int maxSizeBytes;                 // 50 MiB
  Stream<List<Attachment>> watchBySubject(String subjectId);   // own or shared, newest first
  Stream<List<Attachment>> watchAllAccessible();               // own + shared subjects (pickers)
  Stream<Attachment?> watchById(String id);
  Future<Attachment?> getById(String id);
  Future<Attachment> add({required String subjectId, required String name, String? mimeType,
      required Uint8List bytes, String? extractedText});
  Future<Attachment> update(Attachment a);       // name, mimeType, kind, extractedText only
  Future<Attachment> rename(String id, String name);
  Future<void> delete(String id);                // soft; blob removed after the tombstone is pushed
  Future<Uint8List> getBytes(Attachment a);      // local cache, else download (throws)
  Future<bool> isCached(Attachment a);
  Stream<AttachmentUploadState> watchUpload(Attachment a);
}
// AttachmentUploadState { AttachmentUploadPhase phase (queued|uploading|retrying|done);
//   String? error; int attempts; bool isPending }

abstract interface class ImageStore {
  Future<NoteImageRef> saveNoteImage({required String noteId, required Uint8List bytes, required String extension});
  Future<Uint8List?> load(NoteImageRef ref);   // local cache, else download
  Future<void> delete(NoteImageRef ref);
}

enum SyncState { idle, syncing, offline, error }
class SyncStatus { SyncState state; DateTime? lastSyncedAt; int pendingOps; String? error;
  int stuckOps; int rejectedChanges;          // freezed (added in Phase 3)
  bool serverOutdated; List<String> unavailableTables; } // server schema behind the app
const String serverOutdatedMessage;           // lib/data/sync/sync_engine.dart
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
| `attachmentRepositoryProvider` | same | `Provider<AttachmentRepository>` |
| `attachmentsForSubjectProvider(subjectId)` | same | `StreamProvider.autoDispose.family<List<Attachment>, String>` |
| `accessibleAttachmentsProvider` | same | `StreamProvider.autoDispose<List<Attachment>>` (own + shared subjects) |
| `attachmentProvider(id)` | same | `StreamProvider.autoDispose.family<Attachment?, String>` |
| `attachmentUploadProvider(attachmentId)` | same | `StreamProvider.autoDispose.family<AttachmentUploadState, String>` |
| `accessibleNotesProvider` | same | `StreamProvider.autoDispose<List<Note>>` (own + shared, updatedAt desc) |
| `deckRepositoryProvider`, `reviewRepositoryProvider`, `mistakeRepositoryProvider`, `studyActivityRepositoryProvider` | same | `Provider<...>` (Wave 2, see *Study client API*) |
| `studySettingsProvider` | same | `NotifierProvider<StudySettingsController, StudySettings>` |
| `decksBySubjectProvider(subjectId)`, `decksByNoteProvider(noteId)` | same | `StreamProvider.autoDispose.family<List<Deck>, String>` |
| `accessibleDecksProvider` / `deckProvider(id)` | same | `StreamProvider.autoDispose<List<Deck>>` / `.family<Deck?, String>` |
| `dueQueueProvider` / `deckDueQueueProvider(deckId)` | same | `StreamProvider.autoDispose<DueQueue>` / `.family<DueQueue, String>` |
| `dueCountProvider`, `openMistakeCountProvider` | same | `StreamProvider.autoDispose<int>` |
| `deckStatsProvider(deckId)` | same | `StreamProvider.autoDispose.family<DeckStats, String>` |
| `openMistakesProvider` | same | `StreamProvider.autoDispose<List<MistakeGroup>>` |
| `dashboardStatsProvider` | `lib/study/study_providers.dart` | `StreamProvider.autoDispose<DashboardStats>` |
| `noteSearchProvider(query)` | same | `Provider.autoDispose.family<AsyncValue<List<Note>>, String>` (filtered `accessibleNotesProvider`) |
| `chatRepositoryProvider`, `organizationRepositoryProvider` | `lib/data/data_providers.dart` | `Provider<...>` (Wave 3, see *Wave 3 client API*) |
| `chatsProvider` / `chatsByScopeProvider((type:, id:))` / `chatProvider(id)` / `chatMessagesProvider(chatId)` | same | `StreamProvider.autoDispose(.family)` |
| `subjectListProvider(SubjectListQuery)`, `archivedSubjectsProvider`, `noteListProvider` / `quizListProvider` / `deckListProvider(ItemListQuery)` | same | `StreamProvider.autoDispose(.family)` |
| `allTagsProvider` / `tagCountsProvider((kind:, subjectId:))` | same | `StreamProvider.autoDispose<List<TagCount>>` (`.family`) |
| `searchIndexProvider`, `searchRevisionProvider`, `searchProvider((query:, filters:))` | `lib/search/search_providers.dart` | `Provider<LiveSearchIndex>`, `StreamProvider<int>`, `Provider.family<AsyncValue<List<SearchResult>>, SearchRequest>` |
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
signed in on `/login|/signup` -> `/home` (also the initial location). "New note/quiz" flows: create via the
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
  snackbar). **Every** dropped op (row upserts and Storage ops) is kept in
  `sync_meta` (max 100, oldest `card_reviews`/`mistakes` entries evicted
  first): `engine.rejectedChanges` (`RejectedChange{id, table, rowId, op,
  payload, message, at}`; `op` = `OutboxOpType` wire name, `table` = bucket
  and `rowId` = path for file ops), count in `status.rejectedChanges`,
  `engine.dismissRejectedChange(id)`. The one quiet drop (a review/mistake
  whose deck/quiz is no longer readable, `42501`) is recorded and counted
  too, but does not set `state: error` or emit a `SyncRejection`.
- **Server schema out of date** (the Supabase project is behind the app's
  migrations): PostgREST schema-cache errors `PGRST204` (missing column),
  `PGRST205` (missing table), `PGRST202` (missing function), `PGRST200`
  (missing relationship), Postgres `42703`/`42P01`/`42883`, any message
  "... in the schema cache", or Storage "Bucket not found" are classified
  `RemoteErrorKind.schemaOutdated`. Such ops are **never dropped** and never
  count as failed attempts (not "stuck"): they stay queued (`lastError` set)
  until the migration is applied. Status: `state: error`,
  `serverOutdated: true`, `unavailableTables` (sorted table / bucket names,
  e.g. `['quiz_attempts']` or `['card_reviews', 'decks']`), and `error`
  starts with `serverOutdatedMessage` ("The server database needs an update
  (run the latest Supabase migration). Your changes are kept on this
  device."). **UI**: when `status.serverOutdated`, show a specific banner
  with `serverOutdatedMessage` (not the generic "Sync problem"); pending ops
  remain in `status.pendingOps`. Everything else keeps syncing; affected
  tables are retried on every sync (capped backoff 5 s .. 5 min plus the
  periodic trigger) and the flags clear on the first cycle after the
  migration. Repositories map it to `UnknownException` with a similar
  message.
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
  (3 passes); schema out of date (see above) -> kept, no attempt counted,
  the table's later ops are skipped for this cycle (per-row order kept)
  while other tables' ops continue; permanent (`42501`, `23xxx`, `22xxx`,
  `P0001/P0002`, other 4xx) -> dropped + reported (op recorded in
  `rejectedChanges`, see above); transient (5xx/unknown, 408/429) ->
  retried with capped backoff, never dropped (FK-blocked ops are not
  counted while other ops fail transiently or are schema-blocked).
- After push, pending `note_image_copies` rows are processed (Storage copy
  `from_path` -> `to_path` within the row's `bucket`, then the row is
  deleted; also deleted when the source is gone/unreadable or the target
  exists).
- Pull: per table, isolated (a table failing with a non-network error,
  e.g. `PGRST205` missing table, is skipped and listed in
  `status.unavailableTables` / `status.error`; the other tables still pull;
  it is retried every sync from its unchanged cursor), keyset pages
  `(updated_at, id) > cursor` ascending, 500 rows. Cursor = raw server `updated_at` string + id of the last row
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
  targeted fetch without cursor (subject: the subject + notes/quizzes/
  attachments by `subject_id`; note: the note + quizzes by `note_id`; quiz: the quiz). A
  revoked share (or every 30 min) -> reconciliation: ids of locally cached
  rows owned by others are checked with `select id where id in (...)` and
  rows no longer visible are purged (plus their cached images).
  Schema-outdated tables are skipped in both (nothing is purged on a failed
  check); a new share whose backfill was incomplete is not remembered, so
  it is backfilled again, and an incomplete reconciliation reruns next sync.

**Repositories**: local-first; writes set `ownerId` = current user, client
UUID, `createdAt/updatedAt` = now (server overwrites `updated_at`), then
enqueue + write Hive. Non-owned rows -> `PermissionDeniedException` (also
creating notes/quizzes under a shared subject/note). Deletes are soft and
cascade locally: subject -> notes (+ their quizzes and own images) and
quizzes and attachments (+ blobs); note -> its quizzes + own images. A quiz with `noteId` must use the
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

**Attachments (client, Wave 1).** Protocol: *Attachments* above.
- Add: `ref.read(attachmentRepositoryProvider).add(subjectId:, name:
  originalFileName, mimeType: picked?.mimeType, bytes:, extractedText:
  textFromTextExtractor)` (owned subject only; works offline). The name's
  extension drives `kind` (`AttachmentKind.detect`); `mimeType` defaults to
  `mimeTypeForFileName(name)`. `extractedText` is supplied by the caller
  (the data layer never depends on `lib/ai`) and truncated to 200 000 chars.
  Errors: `ValidationException` (empty, > 50 MB: message names the file and
  the limit), `PermissionDeniedException` (shared subject),
  `NotFoundException` (missing subject), `StorageException` (local write).
- Pipeline: bytes are written to the local attachment cache (files under
  `{app support}/attachments/{storage path}` on native, lazy Hive box
  `attachment_bytes` on web), then the outbox gets `upload_attachment`
  (rowId = storage path) **before** the row upsert. The engine uploads to
  bucket `attachments` (`upsert: true`, content type from the row) and does
  not push an attachment row while its upload op is pending (treated like
  an FK wait), so recipients never see a row before its blob unless the
  upload was rejected. Byte-level progress is not available from the Storage
  client: `watchUpload` / `attachmentUploadProvider(id)` report `queued`
  (waiting/offline) -> `uploading` (request in flight) -> `retrying` (last
  attempt failed, retried automatically) -> `done`.
- Delete (owner only): tombstone upsert first, then `delete_attachment`
  (Storage `remove`), which waits while the tombstone is still queued; local
  bytes and a not-yet-run upload are dropped immediately (an offline add +
  delete never uploads). Soft-deleting a subject cascades to its own
  attachments + blobs.
- Read: `getBytes(a)` = local cache, else download (cached afterwards; one
  download per path at a time). Throws `NetworkException` (offline, not
  cached), `NotFoundException` (403/404: revoked, deleted, not uploaded or
  copied yet), `AppAuthException`, `UnknownException` (5xx). `isCached(a)`
  for an "available offline" hint. Shared attachments are read-only
  (`update`/`rename`/`delete` -> `PermissionDeniedException`); UI checks
  `a.isOwnedBy(currentUserId)`.
- Sync: `attachments` is pulled like the other tables (keyset cursor). A new
  **subject** share also fetches `attachments` by `subject_id`;
  reconciliation covers attachments (revoked rows + their cached bytes are
  purged); own tombstones pulled from other devices drop the cached bytes.
- Copy queue: `NoteImageCopyProcessor` selects `id, bucket, from_path,
  to_path` and calls `storage.from(bucket).copy(...)` (missing bucket =
  `note-images`), copying cached bytes in that bucket's local cache.
- **CDN cache busting**: every Storage download (note images and
  attachments) adds a unique `cacheNonce` query parameter, because the
  Storage CDN caches authenticated GETs by URL + token and would keep
  serving users whose access was revoked.

**Note picker (Wave 1).** `accessibleNotesProvider` (own + shared notes, live,
`updatedAt` desc) and `noteSearchProvider(query)` (or
`searchNotes(notes, query)` from `lib/data/repositories/note_search.dart`):
case-insensitive, every whitespace-separated term must occur in title or
content, title matches first, empty query = all; lowercased text is
memoized per note so per-keystroke filtering of thousands of notes is cheap.
Shared notes have `ownerId != currentUserId`.

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

**Sources (Wave 1).** Requests take `sources: List<AiSource>`
(`lib/ai/ai_source.dart`, re-exported by `ai_service.dart`); the legacy
`contextText` / `youtubeUrl` fields still work and are listed first.

```dart
QuizGenerationRequest(questionCount: 10, sources: [
  TextSource(text: pasted),                         // label defaults to 'Pasted text'
  NoteSource(title: note.title, markdown: note.contentMarkdown),
  FileSource(name: 'lecture.pdf', mimeType: 'application/pdf', bytes: bytes),
  YoutubeSource(url),
]);
```

* Text-like files (.txt/.md/.csv/.json/`text/*`, .docx) are converted to
  text in-app and work with every model. `TextExtractor.extract(name, mime,
  bytes)` (`lib/ai/text_extractor.dart`) returns the text or null (not a
  text type), throws `ValidationException` for a corrupt .docx; the data
  layer can store the result as `extracted_text`. `TextExtractor.canExtract`
  / `AiInputKind.ofFile(name, mime)` classify a file (null = unsupported).
* PDF / image / audio / video are sent as attachments if the selected model
  supports the kind (see capabilities), otherwise `AiException(unsupported)`
  naming model + limitation (nothing is sent). Unknown types (zip, .doc, ...)
  -> `AiException(unsupported)`. Size limits (`ProviderLimits`,
  `lib/ai/providers/attachment_support.dart`) -> `ValidationException`:
  Gemini 2 GB/file (inline base64 up to 15 MB per request, larger via the
  Files API: resumable upload, polled until `ACTIVE`); OpenAI 50 MB/file and
  per request; Anthropic 24 MB per request, images 5 MB (png/jpeg/webp/gif);
  OpenAI-compatible 20 MB/file, 30 MB per request.
* Wire formats: Gemini `inlineData` / `fileData{mimeType, fileUri}`; OpenAI
  Responses `input_file{filename, file_data: data URL}` / `input_image`;
  Anthropic `document` (base64 PDF, `title`) / `image`; OpenAI-compatible
  `image_url` data URL / `file{filename, file_data}` (OpenRouter PDF format).
  Each attachment is preceded by a text part `Attachment N: <name>`.
* The prompt lists every source as `[Source N] <kind> "<label>"` (text
  inside `<source id="N">`), refers to attachments by number and tells the
  model to ground everything in the sources. Text sources share the 100k
  char budget fairly (long ones are cut with a note).
* Generic generation (future decks): `AiService.generateStructured<T>(
  StructuredGenerationRequest(sources:, task:, systemPrompt:, schema:,
  schemaName:, ...), validate: (json) => DraftValidation(...))` — same
  source handling and one repair retry (on the interface since Wave 1;
  `DraftValidation` is re-exported by `ai_service.dart`).

**Readiness / gating.** `aiReadinessProvider` (`FutureProvider<AiReadiness>`,
never errors) drives locked AI entry points:

```dart
final r = ref.watch(aiReadinessProvider).value;      // null while first loading
if (r == null || !r.isConfigured) { /* lock icon; sheet shows r?.reason -> Settings */ }
r.providerId; r.model;                               // what will be used
r.capabilities.pdf / .image / .audio / .video / .youtube / .youtubeNative
```

Ready = a provider (selected, else the first with a key) with an API key and
a model (stored or `defaultModel`). OpenAI-compatible endpoints other than
OpenRouter (Ollama, LM Studio) may have no key: a stored base URL + stored
model suffice (generation and `resolveSelection` accept them too).
`issue` is one of `noProvider` (also signed out), `missingApiKey`,
`missingModel`, `invalidBaseUrl`, `storageError`. It recomputes on user
change and on every write through `apiKeyStoreProvider` (the store is
wrapped in `NotifyingApiKeyStore`, which bumps `aiSettingsRevisionProvider`;
if you write through some other store instance, call
`ref.read(aiSettingsRevisionProvider.notifier).bump()`). Tests overriding
`apiKeyStoreProvider` with a plain fake get no automatic refresh.

**Capabilities** (`lib/ai/ai_capabilities.dart`).
`AiCapabilities.forModel(provider, model)` (static) and
`aiCapabilityResolverProvider` (`AiCapabilityResolver.resolve(provider:,
model:, baseUrl:, manualOverride:)`):

| Provider | text | pdf | image | audio | video | youtube |
|---|---|---|---|---|---|---|
| Gemini `gemini-*` | ✓ | ✓ | ✓ | ✓ | ✓ | native |
| OpenAI gpt-4o*/4.1*/4.5*/5*/o1/o3/o4* (not o1-mini/o3-mini) | ✓ | ✓ | ✓ | - | - | transcript |
| OpenAI other | ✓ | - | - | - | - | transcript |
| Anthropic `claude-*` (3+) | ✓ | ✓ | ✓ | - | - | transcript |
| OpenRouter | ✓ | `file` in `input_modalities` | `image` in it | - | - | transcript |
| other OpenAI-compatible | ✓ | override | override | - | - | transcript |

"transcript" = not on web (YouTube blocks it); a YouTube source there throws
`TranscriptUnavailableException`. OpenRouter metadata comes from the public
`GET {base}/models` (no key), cached 6 h per base URL; failures/unknown
models = text only. Manual override (Settings: "This model supports images /
PDF", OpenAI-compatible only): part of `ApiKeyStore` (no cast) —
`store.setInputOverride(p, model, {AiInputKind.image, AiInputKind.pdf})` /
`getInputOverride(p, model)` (per provider + model; empty set clears).

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
| `AiException(unsupported)` | file kind the model can't take (message names model + kind), unknown file type, wrong image format | pick another model / remove file |
| `TranscriptUnavailableException` | no captions, private video, YouTube blocked (always on web) | suggest Gemini or pasting text |
| `ValidationException` | no input, bad YouTube URL, count out of range, file too large, empty/corrupt text file | inline field error |
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

## Wave 2 UI entry points (routes + placeholders)

Routes (in `AppRoutes`): `home` `/home` (shell, `DashboardScreen`), `study`
`/study` (shell, `StudyQueueScreen` — due cards across decks), `mistakes`
`/mistakes` (`MistakesScreen`), `deck(id)` `/decks/:id` (`DeckDetailScreen`),
`deckEdit(id)` (`DeckEditScreen`), `deckStudy(id)` (`DeckStudyScreen`),
`quizPlay(id, mode: null|'exam'|'mistakes')` (`QuizPlayScreen(quizId, mode)`),
`generate(kind: AiGenerateKind.deck, ...)`.

| Entry point | File | Owner |
|---|---|---|
| `DeckListSection(subjectId:, noteId?, readOnly)` | `lib/features/decks/widgets/deck_list_section.dart` | decks |
| Deck screens | `lib/features/decks/presentation/` | decks |
| `StudyQueueScreen`, `MistakesScreen` | `lib/features/study/presentation/` | study |
| `DashboardScreen` | `lib/features/dashboard/presentation/` | dashboard |

Owners replace placeholder bodies keeping class names/constructors, so
`app_router.dart` needs no further edits.
