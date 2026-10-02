# Supabase backend

Schema, Row Level Security, RPCs and Storage policies for the Quiz & Notes app.
The contract the Dart code relies on is in `docs/CONTRACTS.md`; this file
documents how to apply/test the backend and the design decisions behind it.

```
supabase/
  config.toml                         CLI config (local stack)
  migrations/
    20261002000000_init.sql           tables, triggers, RLS, helpers, RPCs, grants
    20261002000100_storage.sql        note-images bucket + storage.objects policies
    20261003000000_hardening.sql      confirmed-email sharing, soft-delete hardening
    20261004000000_attachments.sql    subject attachments (table, RLS, bucket, copy_subject)
    20261005000000_study.sql          decks, card_reviews, mistakes, exam-mode attempt columns
    20261006000000_wave3.sql          AI chats (private), tags / pinned / archived_at, copy_* keep tags
  tests/
    01_rls.sql  02_rpc.sql  03_storage.sql  04_hardening.sql  05_attachments.sql
    06_study.sql  07_wave3.sql        pgTAP tests (419 assertions)
    local_stubs/                      LOCAL VALIDATION ONLY (plain Postgres)
```

## Applying

**Supabase CLI (recommended)**

```sh
supabase login
supabase link --project-ref <your-project-ref>
supabase db push            # applies supabase/migrations in order
```

**SQL editor (no CLI)**: open the project's SQL editor and run
`migrations/20261002000000_init.sql`, then `migrations/20261002000100_storage.sql`,
then `migrations/20261003000000_hardening.sql`, then
`migrations/20261004000000_attachments.sql`, then
`migrations/20261005000000_study.sql`, then
`migrations/20261006000000_wave3.sql`, each as one script, in that
order. A project that already ran some of them only needs the later ones
(the hardening, attachments, study and wave3 migrations are safe to run more
than once; the study and wave3 migrations also work when the editor runs
them as a single transaction, see *Study*).

After applying, in the dashboard:
- Authentication → Providers → Email: enabled (email/password).
- Authentication → **"Confirm email" MUST be enabled in production.** Sharing
  only resolves users whose `auth.users.email_confirmed_at` is set. With
  confirmation off, GoTrue auto-confirms every signup, so anyone could
  register someone else's address and receive the shares addressed to it.
  (Turning it off is fine for local/dev testing: sign-ups are confirmed
  immediately and sharing works.)
- API settings: exposed schemas stay `public` (do **not** expose `private`).
- Realtime is not used (sync is pull-based), so no publication is configured.

## Testing

```sh
supabase start      # needs Docker
supabase test db    # runs supabase/tests/*.sql with pg_prove
```

Without Docker, on any PostgreSQL 15+ server with pgTAP installed
(`apt install postgresql-16-pgtap`) and a superuser connection:

```sh
PGHOST=... PGPORT=... PGUSER=postgres ./supabase/tests/local_stubs/run_local.sh
```

That script creates a throwaway database, loads
`tests/local_stubs/supabase_stubs.psql` (a minimal imitation of Supabase's
`auth`/`storage` schemas, roles and default grants), applies the migrations and
runs the tests. The stubs file uses a `.psql` extension so `supabase test db`
never picks it up, and it refuses to run if an `auth` schema already exists.
**Never run it against a Supabase project.**

The tests impersonate users with `set local role authenticated` +
`set local request.jwt.claims to '{"sub": "..."}'`, exactly as PostgREST does.
`03_storage.sql` inserts rows into `storage.objects` directly to exercise the
policies; recent Supabase Storage versions add triggers on that table (e.g.
blocking direct deletes), which the test tolerates by asserting the end state.

## Live smoke test

`scripts/supabase_smoke_test.dart` exercises the deployed project end to end
over HTTP (Auth, PostgREST, Storage) with three throwaway users: profile
trigger, RLS (owner/recipient/anon), shares (subject and note), duplicate
share, quiz attempts privacy, `copy_subject` + `note_image_copies` + Storage
copy, revocation, then best-effort cleanup.

Prerequisites: migrations applied, Email provider enabled with **"Confirm
email" OFF**, and `env.json` (repo root) with `SUPABASE_URL` and
`SUPABASE_ANON_KEY`.

```sh
flutter pub get                                   # once (package:http)
dart run scripts/supabase_smoke_test.dart         # or: ... path/to/env.json
dart run scripts/supabase_smoke_test.dart --email-domain=yourdomain.dev   # if example.com is rejected
```

It prints a PASS/FAIL line per check and a summary, and exits 1 on any
failure. Keys, passwords and JWTs are never printed. The test users cannot be
deleted with the anon key; their emails are printed at the end so you can
delete them under Authentication -> Users.

## Data model summary

| Table | Notes |
|---|---|
| `profiles` | `id` = `auth.users.id`; `email`, `display_name`. Created by trigger on signup (`raw_user_meta_data->>'display_name'`, fallback: email local part); email kept in sync. Only `display_name` is client-updatable. |
| `subjects`, `notes`, `quizzes`, `quiz_attempts` | Synced tables: client `id`/`created_at` accepted, `owner_id` defaults to `auth.uid()`, `updated_at` forced to server `now()`, soft delete via `deleted_at`. |
| `decks` | Flashcard decks; synced, shared and copied exactly like `quizzes` (subject + optional note). See *Study*. |
| `card_reviews`, `mistakes` | Private per-user study state (spaced repetition per card, wrong answers per question). Synced, never shared. See *Study*. |
| `chats`, `chat_messages` | Private per-user AI chats about a subject / note / attachment (or general). Synced, never shared. See *Wave 3*. |
| `shares` | `(resource_type, resource_id, recipient_id)` unique; `resource_type` is the enum `share_resource_type` (`subject`/`note`/`quiz`/`deck`, same JSON strings as a text column). FKs `shares_owner_id_fkey` / `shares_recipient_id_fkey` → `profiles`. |
| `attachments` | Files attached to a subject ("Files" library). Synced table like `notes`; blob in bucket `attachments` at `storage_path`. See *Attachments*. |
| `note_image_copies` | Per-user queue of Storage copies produced by `copy_*` (see below); `bucket` says which bucket (`note-images` default, or `attachments`). |
| `share_details` (view) | `shares` + `resource_title`, `security_invoker` (caller's RLS applies). |

Constraints enforced server-side (rejected with SQLSTATE `42501` unless noted):
- `owner_id` can never change (trigger, applies even to `service_role`).
- A note's subject, a quiz's subject and a quiz's note must have the same owner
  as the row (blocks attaching rows to someone else's subject/note).
  A missing parent raises `23503`.
- `quizzes.subject_id` is **normalized** to the note's subject when `note_id`
  is set, and moving a note to another subject moves its quizzes. The server
  may therefore return a different `subject_id` than the client sent; it bumps
  `updated_at`, so the next pull corrects the local copy.
- `quizzes.questions` and `quiz_attempts.answers` must be JSON arrays (`23514`).
- `quiz_attempts.quiz_id` is immutable after insert.
- Hard-deleting a subject/note/quiz deletes the shares that point at it
  (FK cascades: subject → notes/quizzes → note-attached quizzes → attempts).
- Soft-deleting one (`deleted_at` null → non-null) also deletes the shares
  that point at that row. Restoring it (`deleted_at` back to null) does not
  bring them back. Shares on children (e.g. a note share under a
  soft-deleted subject) are kept but grant nothing while the parent is
  deleted.

## Access rules

`can_read_subject(id)`, `can_read_note(id)`, `can_read_quiz(id)` are
`SECURITY DEFINER` helpers (`search_path = ''`, executable by `authenticated`
only). A row is readable when the caller owns it (including its own
soft-deleted rows), or when the row **and every parent** (note → subject;
quiz → subject and, if note-attached, note) have `deleted_at is null` and the
caller holds a share whose `owner_id` equals the row's owner and that targets:
- subject: the subject itself; note: the note or its subject;
  quiz: the quiz, its subject, or (if note-attached) its note.

| Table | SELECT | INSERT / UPDATE / DELETE |
|---|---|---|
| subjects / notes / quizzes | owner or `can_read_*` | owner only (`owner_id = auth.uid()` in USING and WITH CHECK) |
| quiz_attempts | owner only (quiz owners cannot see others' attempts) | owner only; INSERT also needs `can_read_quiz(quiz_id)` |
| shares | owner or recipient | INSERT: `owner_id = auth.uid()`, recipient ≠ self and has a confirmed email, caller owns the resource and neither it nor a parent is soft-deleted. DELETE: owner. No UPDATE. |
| profiles | self, or the other party of a share in either direction | UPDATE `display_name` of self |
| attachments | owner, or `can_read_attachment(id)`: live attachment (`deleted_at is null`) whose subject passes `can_read_subject` (subject shares only) | owner only; subject must be owned by the same user |
| decks | owner or `can_read_deck` (same rules as quizzes, share type `deck`) | owner only; subject/note must be owned by the same user |
| card_reviews | owner only | owner only; INSERT also needs `can_read_deck(deck_id)` |
| mistakes | owner only | owner only; INSERT also needs `can_read_quiz(quiz_id)` |
| chats | owner only (recipients of a shared subject never see the owner's chats) | owner only; INSERT also needs the scope to be readable (`private.can_read_chat_scope`) |
| chat_messages | owner only | owner only; the chat must exist (`23503`) and have the same owner (`42501`) |
| note_image_copies | owner | INSERT (own folder only) / DELETE by owner |

`anon` has no table or function privileges. Supabase's default grants
(including `TRUNCATE`, which ignores RLS) are revoked and replaced with the
minimum needed. RLS is enabled on all tables and **forced** when the migration
role bypasses RLS (superuser/`BYPASSRLS`, as Supabase's `postgres` is);
otherwise forcing would make the definer helpers recurse through the policies,
so the migration only enables it and emits a NOTICE.

### Decisions the Dart data layer must know

1. **Recipients never see tombstones.** Only owners pull their own
   soft-deleted rows. For a recipient, a soft-deleted row (or a row under a
   soft-deleted parent) simply stops being returned, exactly like a revoked
   share, and soft-deleting a shared resource also deletes its shares. The
   client removes such rows with the reconciliation in point 2. New shares
   can't be created for soft-deleted resources, and `copy_*` refuses
   soft-deleted sources and skips soft-deleted children.
2. **Revocation is not visible through the `updated_at` cursor.** When a share
   is deleted, the rows simply stop being returned. The client should
   reconcile shared rows (e.g. on each sync, or when `shares` changes, re-list
   ids of rows it does not own and drop local ones that are no longer
   returned).
3. **New shares expose rows older than the recipient's cursor.** A new
   subject share makes existing notes/quizzes readable, but their `updated_at`
   may be older than the recipient's cursor. When a new share shows up, pull
   that resource (and for subjects, its notes/quizzes) without the cursor.
4. **Cursor skew.** `updated_at = now()` is the transaction start time; a long
   transaction can commit rows with a timestamp slightly older than rows
   already pulled. Pull with a small overlap (e.g. `cursor - 5s`) and upsert
   idempotently.
5. **Errors**: permission problems are `42501` (PostgREST returns 403 for RLS
   violations on insert, or 0 rows for filtered updates/deletes — an update
   of a non-owned row is a silent no-op), not-found in RPCs is `P0002`,
   CHECK failures `23514`, missing parent `23503`. Outbox ops that fail with
   `42501`/`23514` will never succeed and should be dropped/flagged instead of
   retried (e.g. an attempt recorded offline after access was revoked).
6. **Profiles for share lists**: embed with
   `shares?select=*,recipient:profiles!shares_recipient_id_fkey(id,email,display_name),owner:profiles!shares_owner_id_fkey(id,email,display_name)`.
   `share_details` adds `resource_title` (same columns as `shares`).

## RPCs

| RPC | Returns | Notes |
|---|---|---|
| `find_user_by_email(p_email text)` | `table(id uuid, display_name text, email text)` | Exact, case-insensitive, trimmed match among users with a confirmed email (`auth.users.email_confirmed_at is not null`); 0 or 1 row; no wildcards. `email` is an extra column (superset of CONTRACTS.md). |
| `copy_subject(p_subject_id uuid)` | `uuid` (new subject id) | Needs `can_read_subject`; the subject must not be deleted. Copies the subject, its non-deleted notes (with their non-deleted note-attached quizzes and decks, `note_id` remapped), non-deleted subject-level quizzes and decks, and non-deleted attachments (blobs queued, see below). |
| `copy_note(p_note_id uuid, p_target_subject_id uuid)` | `uuid` (new note id) | Needs `can_read_note`; the note and its subject must not be deleted; target subject must be owned by the caller and not deleted. Also copies the note's non-deleted quizzes and decks. |
| `copy_quiz(p_quiz_id uuid, p_target_subject_id uuid, p_target_note_id uuid default null)` | `uuid` (new quiz id) | Needs `can_read_quiz`; the quiz, its subject and (if any) its note must not be deleted; target subject owned; target note (optional) owned, not deleted and in the target subject. |
| `copy_deck(p_deck_id uuid, p_target_subject_id uuid, p_target_note_id uuid default null)` | `uuid` (new deck id) | Same rules as `copy_quiz`, with `can_read_deck`. Copies `title, description, source, cards` (card ids kept); review state is not copied. |

Since Wave 3 every `copy_*` also copies `tags` of notes, quizzes and decks;
`pinned` and `archived_at` are never copied (copies start unpinned and
unarchived).

All copies are atomic (one transaction), get fresh uuids, `owner_id =
auth.uid()`, and server timestamps. The `copy_*` functions are
`SECURITY INVOKER`: every read and write goes through the caller's own RLS,
so they cannot reach data the caller could not read anyway. After a copy the
client should run a sync pull to fetch the new rows.

### Note images when copying

SQL cannot duplicate Storage blobs (a `storage.objects` row without the
underlying file is useless), so copying is split:

1. `copy_note` / `copy_subject` rewrite every
   `note-image://{src_owner}/{src_note}/{file}` in `content_md` to
   `note-image://{caller}/{new_note}/{file}` and insert one row per distinct
   file into `public.note_image_copies(id, owner_id, from_path, to_path, created_at)`.
2. The client (right after the RPC, and on later syncs to catch leftovers)
   selects its rows from `note_image_copies`, calls
   `storage.from('note-images').copy(from_path, to_path)` for each (the
   Storage API checks read access to the source and write access to the
   caller's own folder), and deletes the row on success or when the source
   no longer exists / is no longer readable.

Until a copy completes, the image in the copied note is missing; if access is
revoked before the client copies, the image stays missing (no data leak).

`copy_subject` also copies attachment rows and queues their blobs in the same
table with `bucket = 'attachments'` (note images have `bucket = 'note-images'`,
the column default). The client must copy each row **in the bucket named by
`bucket`** (see *Attachments*). Clients built before this column existed
copy every row in `note-images`; for an `attachments` row that fails
(source not found) and they delete it, so the copied attachment's blob stays
missing until the user re-uploads it. No data leaks either way.

## Storage

Bucket `note-images` is private (10 MiB, `image/*`). Object path
`{owner_id}/{note_id}/{file}`.
- INSERT/UPDATE/DELETE: first path segment must be `auth.uid()`.
- SELECT: own folder, or `can_read_note_object(name)`: the path must be exactly
  three segments, the second a valid uuid, the note must exist and be owned by
  the first segment (so files someone plants under another user's note id are
  never exposed), and the caller must pass `can_read_note`. Malformed paths
  return false instead of raising. Because `can_read_note` ignores
  soft-deleted notes (and notes under soft-deleted subjects) for
  non-owners, recipients lose access to their images at the same time.
- Uploads are not tied to an existing note row (images may be uploaded before
  the note syncs). Use signed URLs or authenticated downloads to read.

Bucket `attachments` (50 MiB, any type, path
`{owner_id}/{subject_id}/{attachment_id}/{file}`) is described under
*Attachments* below.

## Attachments (`20261004000000_attachments.sql`)

Files attached to a subject (PDF, images, text, docx, audio, video). Contract
for the Dart side: `docs/CONTRACTS.md` → *Attachments*.

- `public.attachments(id, subject_id, owner_id, name, mime_type, size_bytes,
  kind, storage_path, extracted_text, created_at, updated_at, deleted_at)`;
  same sync conventions as `notes` (client id/created_at, server
  `updated_at`, immutable `owner_id`, soft delete). The subject must exist
  (`23503`) and be owned by the same user (`42501`). `subject_id` and
  `storage_path` are immutable (`42501`): an attachment cannot move to
  another subject (copy it instead).
- CHECKs (`23514`): `kind in ('pdf','image','text','docx','audio','video','other')`,
  `extracted_text` ≤ 200 000 characters, `size_bytes >= 0`, `name` 1..512
  chars, and `storage_path` must be exactly
  `{owner_id}/{subject_id}/{id}/{file}` (lowercase uuids as Postgres prints
  them, `{file}` one non-empty segment, not `.`/`..`, ≤ 1024 chars total).
- Read access: owner (including own tombstones), or a recipient of a
  **subject** share while the attachment and the subject are not
  soft-deleted (`can_read_attachment`). Note and quiz shares never expose
  attachments. Attachments are not a share resource themselves, so no
  share-deletion trigger is needed: soft-deleting an attachment hides it from
  recipients at once, and soft-deleting the subject deletes the subject's
  shares (hardening trigger). Hard-deleting a subject cascades to its
  attachment rows (blobs are not removed by SQL).
- Bucket `attachments`: private, 50 MiB per file, any MIME type. Path
  `{owner_id}/{subject_id}/{attachment_id}/{file}`. INSERT/UPDATE/DELETE: first
  segment = `auth.uid()`. SELECT: own folder, or
  `can_read_attachment_object(name)`: exactly four segments, segments 2 and 3
  valid uuids (checked before casting; malformed paths return false), an
  attachment row exists with that exact `storage_path`, owned by segment 1
  and in subject segment 2, and the caller passes `can_read_attachment`.
  Blobs without a row, blobs of soft-deleted attachments and blobs planted in
  someone else's folder are never exposed to non-owners.
- `supabase/config.toml` raises the local stack's global upload limit to
  50 MiB to match (the hosted project's global limit under Storage settings
  must also be ≥ 50 MiB, the free-plan maximum).
- `copy_subject` (replaced with `create or replace`) additionally copies the
  subject's non-deleted attachments: new ids, `owner_id` = caller,
  `storage_path = {caller}/{new_subject}/{new_id}/{same file segment}`, all
  other columns copied, and one `note_image_copies` row per attachment with
  `bucket = 'attachments'`, `from_path` = source path, `to_path` = new path.
  `copy_note` / `copy_quiz` never copy attachments.

## Hardening migration (`20261003000000_hardening.sql`)

Applied after the two initial migrations (which stay unchanged because they
are already deployed). Everything is `create or replace` / `drop … if exists`,
so re-running it is harmless.

1. **Confirmed emails only.** `find_user_by_email` joins `auth.users` and
   only matches `email_confirmed_at is not null`; the `shares` INSERT policy
   also requires a confirmed recipient (`private.is_confirmed_user`).
   Requires "Confirm email" to be enabled in production (see *Applying*).
2. **No access to soft-deleted content for recipients.** `can_read_subject`,
   `can_read_note` and `can_read_quiz` grant non-owners access only while
   the row and all its parents are not soft-deleted; owners keep seeing
   their own tombstones. Storage reads follow through `can_read_note`.
   `is_resource_owner` (share creation) also rejects resources under a
   deleted parent, and `copy_note` / `copy_quiz` refuse sources that are, or
   sit under, soft-deleted rows (`P0002`).
3. **Soft delete removes shares.** `AFTER UPDATE OF deleted_at` triggers on
   `subjects`, `notes`, `quizzes` delete the shares pointing at a row when
   its `deleted_at` goes from null to non-null. A one-time cleanup deletes
   existing shares that already point at soft-deleted rows.

## Study (`20261005000000_study.sql`)

Wave 2: flashcards, spaced repetition, mistakes, exam mode. Contract for the
Dart side: `docs/CONTRACTS.md` → *Study (Wave 2)*.

- **`public.decks`** `(id, subject_id, note_id, owner_id, title, description,
  source, cards, created_at, updated_at, deleted_at)`: a copy of the
  `quizzes` design. Same parent rules (`tg_decks_check_parent`: subject/note
  owned by the deck owner, `subject_id` normalized to the note's subject;
  moving a note moves its decks), same sync triggers, same read helper
  (`can_read_deck`: owner incl. tombstones, or the deck + subject + note are
  live and the caller holds a share from the owner on the deck, its subject
  or its note). Share type `deck`: `is_resource_owner` accepts live decks
  under live parents; hard and soft delete remove the deck's shares;
  `share_details.resource_title` covers decks.
  `cards` CHECK (`private.deck_cards_valid`, `23514`): JSON array of objects
  with string `id` (1..255 chars, unique in the deck), string `front`, string
  `back`, optional `hint` (string or null); extra keys allowed.
- **`public.card_reviews`**: one row per (owner, deck, card) (unique),
  FSRS state (`state` 0..3 = new/learning/review/relearning, `due_at`,
  `stability`, `difficulty`, `elapsed_days`, `scheduled_days`, `reps`,
  `lapses`, `last_review_at`). Private: SELECT/UPDATE/DELETE owner only;
  INSERT needs `can_read_deck(deck_id)`, so recipients can study shared
  decks. `deck_id`/`card_id` are immutable. Rows survive revocation or a soft
  delete of the deck (owner keeps them, like attempts); a hard delete of the
  deck cascades to everyone's rows.
- **`public.mistakes`**: one row per (owner, quiz, question) (unique),
  `wrong_count`, `correct_streak`, `last_wrong_at`, `resolved_at`. Private
  like `card_reviews`; INSERT needs `can_read_quiz(quiz_id)`;
  `quiz_id`/`question_id` immutable.
- **`quiz_attempts`** gains `mode` (`practice` default / `exam` /
  `mistakes`), `time_limit_seconds` (> 0, null), `question_ids` (JSON array,
  null), `duration_seconds` (>= 0, null). Existing clients are unaffected.
- `copy_deck` (new), `copy_subject` and `private.copy_note_into` (replaced)
  copy decks as described under *RPCs*.
- **Fix**: `copy_note` / `copy_quiz` from the hardening migration checked
  parent liveness by joining `subjects` under the caller's RLS, so a
  recipient of a direct note or quiz share (who cannot see the subject)
  always got `P0002`. They are replaced to use the definer helpers
  `private.is_live_note/quiz/deck` (liveness only; access is still
  `can_read_*`). `copy_deck` uses the same pattern.
- **Enum value in one transaction.** `alter type ... add value 'deck'` is
  allowed inside a transaction (PG 12+), but the new value cannot be used
  before commit, and SQL-function / view bodies are parsed at creation. The
  migration therefore never parses `'deck'` as the enum: it compares
  `resource_type::text = 'deck'` (and `is_resource_owner` switches on
  `p_resource_type::text`). Verified with `psql --single-transaction`, run
  twice.

## Wave 3 (`20261006000000_wave3.sql`)

AI chats and organization. Contract for the Dart side: `docs/CONTRACTS.md`
→ *Wave 3 schema*. No enum change, so the file runs fine as one transaction
(SQL editor); everything is `if not exists` / `create or replace` /
`drop … if exists` (verified with `psql --single-transaction`, run twice).

- **`public.chats`** `(id, owner_id, scope_type, scope_id, title, provider,
  model, created_at, updated_at, deleted_at)`: `scope_type in
  ('subject','note','attachment','general')` (default `general`);
  `scope_id` is null exactly for `general` (CHECK `chats_scope_shape`);
  `title` text not null default `''` (≤ 500), `provider` / `model` ≤ 255.
  Same sync triggers as the other tables (server `updated_at`, immutable
  `owner_id`); `scope_type` / `scope_id` are immutable (`42501`), since the
  insert is where readability is checked. `scope_id` is polymorphic (no FK):
  hard-deleting the scope leaves the chat in place.
- **`public.chat_messages`** `(id, chat_id, owner_id, role, content,
  citations, created_at, updated_at, deleted_at)`: `role in
  ('user','assistant','system')`, `content` ≤ 200 000 chars, `citations`
  jsonb default `[]` validated by `private.chat_citations_valid` (array of
  objects with string `type` 1..64, string `id` 1..255, string `title`,
  optional `snippet` string/null; extra keys allowed). Trigger
  `tg_chat_messages_check_parent`: chat must exist (`23503`) and be owned by
  the message owner (`42501`); `chat_id` immutable. Hard-deleting a chat
  cascades to its messages; soft deletes do not cascade (client job).
- **RLS (private, never shared)**: every operation on both tables is
  `owner_id = auth.uid()`; there is no share resource type for chats, so a
  recipient of a shared subject can read the subject but never the owner's
  chats about it (and vice versa). `chats` INSERT additionally requires
  `private.can_read_chat_scope(scope_type, scope_id)`: `general` → scope_id
  null; `subject` → `can_read_subject`; `note` → `can_read_note`;
  `attachment` → `can_read_attachment` (owner, or a live attachment whose
  subject passes `can_read_subject`, i.e. subject shares only). Owners pass
  for their own tombstoned scopes (offline-created chats still sync);
  recipients only for live rows. Because RLS `WITH CHECK` runs before
  CHECK constraints, malformed scopes (unknown type, general with an id,
  scoped without one) reach API clients as `42501`, not `23514`.
  Revocation/soft delete of the scope keeps existing chats (and new messages
  in them) — private history, like `card_reviews`; only new chats on that
  scope are refused.
- **Organization columns** (additive, defaulted; old clients unaffected):
  `notes`, `quizzes`, `decks` get `tags text[] not null default '{}'`
  (CHECK `private.tags_valid`: ≤ 50 tags, none null/blank, each ≤ 64 chars;
  `23514`) and `pinned boolean not null default false`, plus GIN indexes
  `{notes,quizzes,decks}_tags_idx` for `@>` / `&&` filters. `subjects` get
  `archived_at timestamptz null` and `pinned boolean not null default false`.
  They are columns of the row, so they are the **owner's** values: owner-only
  writes via the existing policies, recipients see them read-only (an update
  by a recipient is a silent no-op). A personal per-user pin/archive for
  shared items is out of scope (would need a per-user table). Archiving does
  not affect sharing, reading or copying.
- **Copies**: `private.copy_note_into`, `copy_subject`, `copy_quiz`,
  `copy_deck` replaced (bodies otherwise identical to the study migration)
  to copy `tags`; `pinned` / `archived_at` are not copied. `copy_note` is
  unchanged (it calls `copy_note_into`).
