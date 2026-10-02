-- =============================================================================
-- Wave 3: AI chats and organization. Applies on top of
-- 20261002000000_init.sql, 20261002000100_storage.sql,
-- 20261003000000_hardening.sql, 20261004000000_attachments.sql and
-- 20261005000000_study.sql, which are deployed and stay unchanged.
--
--   * public.chats / public.chat_messages: AI chats with a subject, note,
--     attachment or nothing ("general"). Synced like the other tables but
--     PRIVATE: owner-only for every operation, never shared (no share
--     resource type, recipients of a shared subject never see the owner's
--     chats). A chat can only be created on a scope the caller can read
--     (can_read_subject / can_read_note / can_read_attachment).
--   * Organization (additive, defaulted columns; old clients keep working):
--     notes / quizzes / decks gain `tags text[]` + `pinned`; subjects gain
--     `pinned` + `archived_at`. They are properties of the row, i.e. the
--     owner's values; recipients see them read-only.
--   * copy_* RPCs copy `tags` (never `pinned` / `archived_at`).
--
-- Contract: docs/CONTRACTS.md ("Wave 3 schema"). Design notes: supabase/README.md.
-- No enum changes, so the whole file also runs as a single transaction (SQL
-- editor, `supabase db push`).
-- Idempotent: safe to run more than once (if not exists / create or replace /
-- drop ... if exists).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Validation helpers (used by CHECK constraints, which run as the writing
-- role, so authenticated needs EXECUTE)
-- -----------------------------------------------------------------------------

-- True when p_citations is a JSON array of objects
--   {"type": text 1..64, "id": text 1..255, "title": text, "snippet"?: text | null}
-- Extra keys are allowed (forward compatibility).
create or replace function private.chat_citations_valid(p_citations jsonb)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select case
    when p_citations is null or jsonb_typeof(p_citations) <> 'array' then false
    else not exists (
      select 1
      from jsonb_array_elements(p_citations) as c(v)
      where jsonb_typeof(c.v) <> 'object'
         or jsonb_typeof(c.v -> 'type') is distinct from 'string'
         or char_length(c.v ->> 'type') not between 1 and 64
         or jsonb_typeof(c.v -> 'id') is distinct from 'string'
         or char_length(c.v ->> 'id') not between 1 and 255
         or jsonb_typeof(c.v -> 'title') is distinct from 'string'
         or coalesce(jsonb_typeof(c.v -> 'snippet'), 'null') not in ('string', 'null')
    )
  end;
$$;

-- True when p_tags has at most 50 entries, none null, each 1..64 characters
-- and not blank. (Normalization — trim, case, de-duplication — is the
-- client's job; the server only bounds the data.)
create or replace function private.tags_valid(p_tags text[])
returns boolean
language sql
immutable
set search_path = ''
as $$
  select p_tags is not null
     and coalesce(array_length(p_tags, 1), 0) <= 50
     and not exists (
       select 1 from unnest(p_tags) as t(v)
       where t.v is null or char_length(t.v) > 64 or btrim(t.v) = ''
     );
$$;

revoke execute on function
  private.chat_citations_valid(jsonb), private.tags_valid(text[])
from public, anon;
grant execute on function
  private.chat_citations_valid(jsonb), private.tags_valid(text[])
to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 1. AI chats
-- -----------------------------------------------------------------------------
create table if not exists public.chats (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null default auth.uid() references auth.users (id) on delete cascade,
  scope_type  text not null default 'general'
              constraint chats_scope_type_check
              check (scope_type in ('subject', 'note', 'attachment', 'general')),
  -- Polymorphic (no FK): the subject / note / attachment id, null for general.
  -- Hard-deleting the scope leaves the chat in place (it is the user's own
  -- history); the client shows it as "source unavailable".
  scope_id    uuid,
  title       text not null default '' check (char_length(title) <= 500),
  provider    text check (provider is null or char_length(provider) <= 255),
  model       text check (model is null or char_length(model) <= 255),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz,
  constraint chats_scope_shape check ((scope_type = 'general') = (scope_id is null))
);
comment on table public.chats is
  'Private AI chat of one user, optionally about a subject/note/attachment it can read. Never shared.';

create table if not exists public.chat_messages (
  id          uuid primary key default gen_random_uuid(),
  chat_id     uuid not null references public.chats (id) on delete cascade,
  owner_id    uuid not null default auth.uid() references auth.users (id) on delete cascade,
  role        text not null
              constraint chat_messages_role_check check (role in ('user', 'assistant', 'system')),
  content     text not null default '' check (char_length(content) <= 200000),
  citations   jsonb not null default '[]'::jsonb
              constraint chat_messages_citations_valid check (private.chat_citations_valid(citations)),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz
);
comment on table public.chat_messages is
  'Message of a private AI chat (same owner as the chat). citations = [{type, id, title, snippet?}]. Never shared.';

create index if not exists chats_owner_updated_idx         on public.chats (owner_id, updated_at);
create index if not exists chats_owner_scope_idx           on public.chats (owner_id, scope_type, scope_id);
create index if not exists chat_messages_owner_updated_idx on public.chat_messages (owner_id, updated_at);
create index if not exists chat_messages_chat_created_idx  on public.chat_messages (chat_id, created_at);

-- Chat scope readability (insert gate). Owners pass for their own rows
-- (including tombstones, so an offline-created chat still syncs); others
-- only through the share rules of can_read_* (live rows and parents).
-- Attachments: can_read_attachment = owner, or a live attachment whose
-- subject passes can_read_subject (subject shares only).
create or replace function private.can_read_chat_scope(p_scope_type text, p_scope_id uuid)
returns boolean
language sql
stable
set search_path = ''
as $$
  select case p_scope_type
    when 'general'    then p_scope_id is null
    when 'subject'    then p_scope_id is not null and public.can_read_subject(p_scope_id)
    when 'note'       then p_scope_id is not null and public.can_read_note(p_scope_id)
    when 'attachment' then p_scope_id is not null and public.can_read_attachment(p_scope_id)
    else false
  end;
$$;

revoke execute on function private.can_read_chat_scope(text, uuid) from public, anon;
grant execute on function private.can_read_chat_scope(text, uuid) to authenticated, service_role;

-- chats.scope_type / scope_id are fixed at insert (where readability is checked).
create or replace function private.tg_chats_immutable_scope()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.scope_type is distinct from old.scope_type or new.scope_id is distinct from old.scope_id then
    raise exception 'chat scope_type/scope_id cannot be changed' using errcode = '42501';
  end if;
  return new;
end;
$$;

-- A message belongs to an existing chat of the same owner; chat_id is fixed.
create or replace function private.tg_chat_messages_check_parent()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_chat_owner uuid;
begin
  if tg_op = 'UPDATE' then
    if new.chat_id is distinct from old.chat_id then
      raise exception 'chat_messages chat_id cannot be changed' using errcode = '42501';
    end if;
    return new;
  end if;

  select c.owner_id into v_chat_owner
  from public.chats c
  where c.id = new.chat_id;

  if not found then
    raise exception 'chat % does not exist', new.chat_id using errcode = '23503';
  end if;
  if v_chat_owner <> new.owner_id then
    raise exception 'chat % is not owned by the message owner', new.chat_id
      using errcode = '42501';
  end if;
  return new;
end;
$$;

revoke execute on function
  private.tg_chats_immutable_scope(), private.tg_chat_messages_check_parent()
from public, anon, authenticated;

drop trigger if exists chats_sync_row on public.chats;
create trigger chats_sync_row before insert or update on public.chats
  for each row execute function private.tg_sync_row();

drop trigger if exists chats_immutable_scope on public.chats;
create trigger chats_immutable_scope before update on public.chats
  for each row execute function private.tg_chats_immutable_scope();

drop trigger if exists chat_messages_sync_row on public.chat_messages;
create trigger chat_messages_sync_row before insert or update on public.chat_messages
  for each row execute function private.tg_sync_row();

drop trigger if exists chat_messages_check_parent on public.chat_messages;
create trigger chat_messages_check_parent before insert or update on public.chat_messages
  for each row execute function private.tg_chat_messages_check_parent();

alter table public.chats         enable row level security;
alter table public.chat_messages enable row level security;

-- Same rule as the earlier migrations: force only when the migration role
-- bypasses RLS (Supabase's postgres does), otherwise the definer helpers
-- would recurse through the policies.
do $$
begin
  if exists (select 1 from pg_catalog.pg_roles r
             where r.rolname = current_user and (r.rolsuper or r.rolbypassrls)) then
    alter table public.chats         force row level security;
    alter table public.chat_messages force row level security;
  else
    raise notice 'Role % lacks BYPASSRLS; leaving RLS enabled but not forced', current_user;
  end if;
end;
$$;

-- chats (private) -------------------------------------------------------------
drop policy if exists chats_select on public.chats;
create policy chats_select on public.chats
  for select to authenticated
  using (owner_id = (select auth.uid()));

drop policy if exists chats_insert on public.chats;
create policy chats_insert on public.chats
  for insert to authenticated
  with check (
    owner_id = (select auth.uid())
    and private.can_read_chat_scope(scope_type, scope_id)
  );

drop policy if exists chats_update on public.chats;
create policy chats_update on public.chats
  for update to authenticated
  using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));

drop policy if exists chats_delete on public.chats;
create policy chats_delete on public.chats
  for delete to authenticated
  using (owner_id = (select auth.uid()));

-- chat_messages (private; parent ownership enforced by trigger) -----------------
drop policy if exists chat_messages_select on public.chat_messages;
create policy chat_messages_select on public.chat_messages
  for select to authenticated
  using (owner_id = (select auth.uid()));

drop policy if exists chat_messages_insert on public.chat_messages;
create policy chat_messages_insert on public.chat_messages
  for insert to authenticated
  with check (owner_id = (select auth.uid()));

drop policy if exists chat_messages_update on public.chat_messages;
create policy chat_messages_update on public.chat_messages
  for update to authenticated
  using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));

drop policy if exists chat_messages_delete on public.chat_messages;
create policy chat_messages_delete on public.chat_messages
  for delete to authenticated
  using (owner_id = (select auth.uid()));

-- Privileges: replace Supabase's default ALL (incl. TRUNCATE) grants.
revoke all on table public.chats, public.chat_messages from public, anon, authenticated;
grant select, insert, update, delete on table public.chats, public.chat_messages to authenticated;
grant all on table public.chats, public.chat_messages to service_role;

-- -----------------------------------------------------------------------------
-- 2. Organization: tags / pinned / archived_at (additive, defaulted)
-- -----------------------------------------------------------------------------
alter table public.notes
  add column if not exists tags text[] not null default '{}'
    constraint notes_tags_valid check (private.tags_valid(tags)),
  add column if not exists pinned boolean not null default false;

alter table public.quizzes
  add column if not exists tags text[] not null default '{}'
    constraint quizzes_tags_valid check (private.tags_valid(tags)),
  add column if not exists pinned boolean not null default false;

alter table public.decks
  add column if not exists tags text[] not null default '{}'
    constraint decks_tags_valid check (private.tags_valid(tags)),
  add column if not exists pinned boolean not null default false;

alter table public.subjects
  add column if not exists archived_at timestamptz,
  add column if not exists pinned boolean not null default false;

-- Tag filters (`tags @> '{x}'`, `tags && '{x,y}'`) for remote queries.
create index if not exists notes_tags_idx   on public.notes   using gin (tags);
create index if not exists quizzes_tags_idx on public.quizzes using gin (tags);
create index if not exists decks_tags_idx   on public.decks   using gin (tags);

-- -----------------------------------------------------------------------------
-- 3. Copy RPCs: bodies identical to 20261005000000_study.sql, plus `tags`
-- on copied notes, quizzes and decks. pinned / archived_at are not copied
-- (copies start unpinned and unarchived).
-- -----------------------------------------------------------------------------
create or replace function private.copy_note_into(p_note_id uuid, p_target_subject_id uuid)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_uid     uuid := auth.uid();
  v_note    public.notes%rowtype;
  v_new_id  uuid := gen_random_uuid();
  v_src_dir text;
  v_dst_dir text;
begin
  select * into v_note from public.notes n where n.id = p_note_id;
  if not found then
    raise exception 'note % not found', p_note_id using errcode = 'P0002';
  end if;

  v_src_dir := v_note.owner_id::text || '/' || v_note.id::text || '/';
  v_dst_dir := v_uid::text || '/' || v_new_id::text || '/';

  insert into public.notes (id, subject_id, owner_id, title, content_md, tags)
  values (
    v_new_id,
    p_target_subject_id,
    v_uid,
    v_note.title,
    replace(v_note.content_md, 'note-image://' || v_src_dir, 'note-image://' || v_dst_dir),
    v_note.tags
  );

  insert into public.note_image_copies (owner_id, from_path, to_path)
  select distinct v_uid, v_src_dir || m.f[1], v_dst_dir || m.f[1]
  from regexp_matches(
         v_note.content_md,
         'note-image://' || v_src_dir || '([A-Za-z0-9._-]+)',
         'g'
       ) as m(f);

  insert into public.quizzes (id, subject_id, note_id, owner_id, title, description, source, questions, tags)
  select gen_random_uuid(), p_target_subject_id, v_new_id, v_uid,
         q.title, q.description, q.source, q.questions, q.tags
  from public.quizzes q
  where q.note_id = v_note.id
    and q.deleted_at is null
  order by q.created_at;

  insert into public.decks (id, subject_id, note_id, owner_id, title, description, source, cards, tags)
  select gen_random_uuid(), p_target_subject_id, v_new_id, v_uid,
         d.title, d.description, d.source, d.cards, d.tags
  from public.decks d
  where d.note_id = v_note.id
    and d.deleted_at is null
  order by d.created_at;

  return v_new_id;
end;
$$;

create or replace function public.copy_subject(p_subject_id uuid)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_uid    uuid := auth.uid();
  v_src    public.subjects%rowtype;
  v_new_id uuid := gen_random_uuid();
  v_note   record;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  select * into v_src
  from public.subjects s
  where s.id = p_subject_id and s.deleted_at is null and public.can_read_subject(s.id);
  if not found then
    raise exception 'subject % not found', p_subject_id using errcode = 'P0002';
  end if;

  insert into public.subjects (id, owner_id, title, description, color)
  values (v_new_id, v_uid, v_src.title, v_src.description, v_src.color);

  for v_note in
    select n.id from public.notes n
    where n.subject_id = v_src.id and n.deleted_at is null
    order by n.created_at, n.id
  loop
    perform private.copy_note_into(v_note.id, v_new_id);
  end loop;

  insert into public.quizzes (id, subject_id, note_id, owner_id, title, description, source, questions, tags)
  select gen_random_uuid(), v_new_id, null, v_uid, q.title, q.description, q.source, q.questions, q.tags
  from public.quizzes q
  where q.subject_id = v_src.id
    and q.note_id is null
    and q.deleted_at is null
  order by q.created_at;

  insert into public.decks (id, subject_id, note_id, owner_id, title, description, source, cards, tags)
  select gen_random_uuid(), v_new_id, null, v_uid, d.title, d.description, d.source, d.cards, d.tags
  from public.decks d
  where d.subject_id = v_src.id
    and d.note_id is null
    and d.deleted_at is null
  order by d.created_at;

  -- Attachments: new ids, path re-rooted under the caller (file segment kept),
  -- one queued Storage copy per file. `src` is materialized once, so both
  -- inserts see the same generated ids.
  with src as materialized (
    select a.id as src_id,
           x.new_id,
           a.storage_path as from_path,
           v_uid::text || '/' || v_new_id::text || '/' || x.new_id::text || '/'
             || split_part(a.storage_path, '/', 4) as to_path
    from public.attachments a
    cross join lateral (select gen_random_uuid() as new_id) x
    where a.subject_id = v_src.id
      and a.deleted_at is null
  ),
  copied as (
    insert into public.attachments
      (id, subject_id, owner_id, name, mime_type, size_bytes, kind, storage_path, extracted_text)
    select src.new_id, v_new_id, v_uid, a.name, a.mime_type, a.size_bytes, a.kind, src.to_path,
           a.extracted_text
    from src
    join public.attachments a on a.id = src.src_id
    returning id
  )
  insert into public.note_image_copies (owner_id, bucket, from_path, to_path)
  select v_uid, 'attachments', src.from_path, src.to_path
  from src;

  return v_new_id;
end;
$$;

create or replace function public.copy_quiz(
  p_quiz_id uuid,
  p_target_subject_id uuid,
  p_target_note_id uuid default null
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_uid    uuid := auth.uid();
  v_src    public.quizzes%rowtype;
  v_new_id uuid := gen_random_uuid();
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  select q.* into v_src
  from public.quizzes q
  where q.id = p_quiz_id
    and public.can_read_quiz(q.id)
    and private.is_live_quiz(q.id);
  if not found then
    raise exception 'quiz % not found', p_quiz_id using errcode = 'P0002';
  end if;

  perform private.assert_owned_subject(p_target_subject_id);

  if p_target_note_id is not null and not exists (
    select 1 from public.notes n
    where n.id = p_target_note_id
      and n.owner_id = v_uid
      and n.subject_id = p_target_subject_id
      and n.deleted_at is null
  ) then
    raise exception 'target note % is not an owned note of subject %',
      p_target_note_id, p_target_subject_id using errcode = '42501';
  end if;

  insert into public.quizzes (id, subject_id, note_id, owner_id, title, description, source, questions, tags)
  values (v_new_id, p_target_subject_id, p_target_note_id, v_uid,
          v_src.title, v_src.description, v_src.source, v_src.questions, v_src.tags);

  return v_new_id;
end;
$$;

create or replace function public.copy_deck(
  p_deck_id uuid,
  p_target_subject_id uuid,
  p_target_note_id uuid default null
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_uid    uuid := auth.uid();
  v_src    public.decks%rowtype;
  v_new_id uuid := gen_random_uuid();
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  select d.* into v_src
  from public.decks d
  where d.id = p_deck_id
    and public.can_read_deck(d.id)
    and private.is_live_deck(d.id);
  if not found then
    raise exception 'deck % not found', p_deck_id using errcode = 'P0002';
  end if;

  perform private.assert_owned_subject(p_target_subject_id);

  if p_target_note_id is not null and not exists (
    select 1 from public.notes n
    where n.id = p_target_note_id
      and n.owner_id = v_uid
      and n.subject_id = p_target_subject_id
      and n.deleted_at is null
  ) then
    raise exception 'target note % is not an owned note of subject %',
      p_target_note_id, p_target_subject_id using errcode = '42501';
  end if;

  insert into public.decks (id, subject_id, note_id, owner_id, title, description, source, cards, tags)
  values (v_new_id, p_target_subject_id, p_target_note_id, v_uid,
          v_src.title, v_src.description, v_src.source, v_src.cards, v_src.tags);

  return v_new_id;
end;
$$;
