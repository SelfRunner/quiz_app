-- =============================================================================
-- Quiz & Notes app: core schema, triggers, RLS, RPCs.
--
-- Contract: docs/CONTRACTS.md ("Supabase schema implied by the models").
-- Design notes: supabase/README.md.
--
-- Conventions
--   * Every synced table (subjects, notes, quizzes, quiz_attempts) has
--     id (client-generated uuid), owner_id (default auth.uid(), immutable),
--     created_at (client value accepted), updated_at (always server now(),
--     the sync cursor) and deleted_at (soft-delete tombstone).
--   * All SECURITY DEFINER functions pin search_path = '' and fully qualify
--     every object. EXECUTE is revoked from PUBLIC/anon and granted only to
--     authenticated (+ service_role).
--   * Errors raised on purpose use SQLSTATE 42501 (insufficient_privilege),
--     P0002 (no_data_found) or 22023 (invalid_parameter_value).
-- =============================================================================

-- Internal helpers live in a schema that PostgREST does not expose.
create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- Types
-- -----------------------------------------------------------------------------
create type public.share_resource_type as enum ('subject', 'note', 'quiz');

-- -----------------------------------------------------------------------------
-- Tables
-- -----------------------------------------------------------------------------
create table public.profiles (
  id           uuid primary key references auth.users (id) on delete cascade,
  email        text,
  display_name text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
comment on table public.profiles is
  'One row per auth user (created by trigger). Readable by self and by users linked through a share.';

create table public.subjects (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null default auth.uid() references auth.users (id) on delete cascade,
  title       text not null,
  description text,
  color       bigint check (color is null or color between 0 and 4294967295), -- ARGB32
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz
);

create table public.notes (
  id          uuid primary key default gen_random_uuid(),
  subject_id  uuid not null references public.subjects (id) on delete cascade,
  owner_id    uuid not null default auth.uid() references auth.users (id) on delete cascade,
  title       text not null,
  content_md  text not null default '',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz
);

create table public.quizzes (
  id          uuid primary key default gen_random_uuid(),
  subject_id  uuid not null references public.subjects (id) on delete cascade,
  note_id     uuid references public.notes (id) on delete cascade,
  owner_id    uuid not null default auth.uid() references auth.users (id) on delete cascade,
  title       text not null,
  description text,
  source      jsonb check (source is null or jsonb_typeof(source) in ('object', 'null')),
  questions   jsonb not null default '[]'::jsonb
              constraint quizzes_questions_is_array check (jsonb_typeof(questions) = 'array'),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz
);

create table public.quiz_attempts (
  id           uuid primary key default gen_random_uuid(),
  quiz_id      uuid not null references public.quizzes (id) on delete cascade,
  owner_id     uuid not null default auth.uid() references auth.users (id) on delete cascade,
  answers      jsonb not null default '[]'::jsonb
               constraint quiz_attempts_answers_is_array check (jsonb_typeof(answers) = 'array'),
  score        double precision not null default 0,
  total        integer not null default 0 check (total >= 0),
  started_at   timestamptz not null default now(),
  completed_at timestamptz,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz
);

-- resource_id is polymorphic (no FK); rows are removed by triggers when the
-- resource is hard-deleted. owner/recipient reference profiles so PostgREST
-- can embed them: shares?select=*,recipient:profiles!shares_recipient_id_fkey(*)
create table public.shares (
  id            uuid primary key default gen_random_uuid(),
  owner_id      uuid not null default auth.uid(),
  recipient_id  uuid not null,
  resource_type public.share_resource_type not null,
  resource_id   uuid not null,
  created_at    timestamptz not null default now(),
  constraint shares_owner_id_fkey foreign key (owner_id)
    references public.profiles (id) on delete cascade,
  constraint shares_recipient_id_fkey foreign key (recipient_id)
    references public.profiles (id) on delete cascade,
  constraint shares_unique_recipient unique (resource_type, resource_id, recipient_id),
  constraint shares_not_self check (owner_id <> recipient_id)
);

-- Pending Storage copies produced by copy_note / copy_subject (see README).
create table public.note_image_copies (
  id         uuid primary key default gen_random_uuid(),
  owner_id   uuid not null default auth.uid() references auth.users (id) on delete cascade,
  from_path  text not null,
  to_path    text not null,
  created_at timestamptz not null default now()
);

-- -----------------------------------------------------------------------------
-- Indexes
-- -----------------------------------------------------------------------------
create index profiles_email_lower_idx      on public.profiles (lower(email));

create index subjects_owner_updated_idx     on public.subjects (owner_id, updated_at);
create index subjects_updated_idx           on public.subjects (updated_at);

create index notes_owner_updated_idx        on public.notes (owner_id, updated_at);
create index notes_updated_idx              on public.notes (updated_at);
create index notes_subject_idx              on public.notes (subject_id);

create index quizzes_owner_updated_idx      on public.quizzes (owner_id, updated_at);
create index quizzes_updated_idx            on public.quizzes (updated_at);
create index quizzes_subject_idx            on public.quizzes (subject_id);
create index quizzes_note_idx               on public.quizzes (note_id) where note_id is not null;

create index quiz_attempts_owner_updated_idx on public.quiz_attempts (owner_id, updated_at);
create index quiz_attempts_quiz_idx          on public.quiz_attempts (quiz_id);

create index shares_recipient_idx           on public.shares (recipient_id);
create index shares_owner_idx               on public.shares (owner_id);
create index shares_resource_idx            on public.shares (resource_type, resource_id);

create index note_image_copies_owner_idx    on public.note_image_copies (owner_id);

-- -----------------------------------------------------------------------------
-- Trigger functions
-- -----------------------------------------------------------------------------

-- updated_at = server time on every insert/update (sync cursor); owner_id is
-- immutable. Used by subjects, notes, quizzes, quiz_attempts.
create function private.tg_sync_row()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  if tg_op = 'UPDATE' and new.owner_id is distinct from old.owner_id then
    raise exception 'owner_id cannot be changed' using errcode = '42501';
  end if;
  return new;
end;
$$;

create function private.tg_touch_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- A note must belong to a subject owned by the same user.
create function private.tg_notes_check_parent()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_subject_owner uuid;
begin
  select s.owner_id into v_subject_owner
  from public.subjects s
  where s.id = new.subject_id;

  if not found then
    raise exception 'subject % does not exist', new.subject_id using errcode = '23503';
  end if;
  if v_subject_owner <> new.owner_id then
    raise exception 'subject % is not owned by the note owner', new.subject_id
      using errcode = '42501';
  end if;
  return new;
end;
$$;

-- A quiz must belong to a subject owned by the same user. If it is attached to
-- a note, the note must have the same owner and quiz.subject_id is normalized
-- to the note's subject (so a note move can never leave quizzes inconsistent).
create function private.tg_quizzes_check_parent()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner   uuid;
  v_subject uuid;
begin
  if new.note_id is not null then
    select n.owner_id, n.subject_id into v_owner, v_subject
    from public.notes n
    where n.id = new.note_id;

    if not found then
      raise exception 'note % does not exist', new.note_id using errcode = '23503';
    end if;
    if v_owner <> new.owner_id then
      raise exception 'note % is not owned by the quiz owner', new.note_id
        using errcode = '42501';
    end if;
    new.subject_id := v_subject;
  end if;

  select s.owner_id into v_owner
  from public.subjects s
  where s.id = new.subject_id;

  if not found then
    raise exception 'subject % does not exist', new.subject_id using errcode = '23503';
  end if;
  if v_owner <> new.owner_id then
    raise exception 'subject % is not owned by the quiz owner', new.subject_id
      using errcode = '42501';
  end if;
  return new;
end;
$$;

-- When a note moves to another subject, its quizzes follow.
create function private.tg_notes_propagate_subject()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.quizzes q
     set subject_id = new.subject_id
   where q.note_id = new.id
     and q.subject_id <> new.subject_id;
  return null;
end;
$$;

-- quiz_attempts.quiz_id is immutable (insert is where access is checked).
create function private.tg_attempts_immutable_quiz()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.quiz_id is distinct from old.quiz_id then
    raise exception 'quiz_id cannot be changed' using errcode = '42501';
  end if;
  return new;
end;
$$;

-- Remove shares that point at a hard-deleted resource (also fires for
-- FK cascades, e.g. deleting a subject deletes its notes' shares).
create function private.tg_delete_resource_shares()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.shares sh
   where sh.resource_type = tg_argv[0]::public.share_resource_type
     and sh.resource_id = old.id;
  return null;
end;
$$;

-- Profile row on signup.
create function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, email, display_name)
  values (
    new.id,
    new.email,
    coalesce(
      nullif(btrim(new.raw_user_meta_data ->> 'display_name'), ''),
      nullif(split_part(new.email, '@', 1), '')
    )
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

-- Keep profiles.email in sync with auth.users.email.
create function private.handle_user_email_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.profiles p set email = new.email where p.id = new.id;
  return new;
end;
$$;

-- -----------------------------------------------------------------------------
-- Triggers
-- -----------------------------------------------------------------------------
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function private.handle_new_user();

create trigger on_auth_user_email_changed
  after update of email on auth.users
  for each row when (new.email is distinct from old.email)
  execute function private.handle_user_email_change();

create trigger profiles_touch before update on public.profiles
  for each row execute function private.tg_touch_updated_at();

create trigger subjects_sync_row before insert or update on public.subjects
  for each row execute function private.tg_sync_row();
create trigger notes_sync_row before insert or update on public.notes
  for each row execute function private.tg_sync_row();
create trigger quizzes_sync_row before insert or update on public.quizzes
  for each row execute function private.tg_sync_row();
create trigger quiz_attempts_sync_row before insert or update on public.quiz_attempts
  for each row execute function private.tg_sync_row();

create trigger notes_check_parent
  before insert or update of subject_id, owner_id on public.notes
  for each row execute function private.tg_notes_check_parent();
create trigger quizzes_check_parent
  before insert or update of subject_id, note_id, owner_id on public.quizzes
  for each row execute function private.tg_quizzes_check_parent();
create trigger notes_propagate_subject
  after update of subject_id on public.notes
  for each row when (new.subject_id is distinct from old.subject_id)
  execute function private.tg_notes_propagate_subject();

create trigger quiz_attempts_immutable_quiz before update on public.quiz_attempts
  for each row execute function private.tg_attempts_immutable_quiz();

create trigger subjects_delete_shares after delete on public.subjects
  for each row execute function private.tg_delete_resource_shares('subject');
create trigger notes_delete_shares after delete on public.notes
  for each row execute function private.tg_delete_resource_shares('note');
create trigger quizzes_delete_shares after delete on public.quizzes
  for each row execute function private.tg_delete_resource_shares('quiz');

-- Backfill profiles for users that existed before this migration.
insert into public.profiles (id, email, display_name)
select u.id,
       u.email,
       coalesce(nullif(btrim(u.raw_user_meta_data ->> 'display_name'), ''),
                nullif(split_part(u.email, '@', 1), ''))
from auth.users u
on conflict (id) do nothing;

-- -----------------------------------------------------------------------------
-- Access helpers (SECURITY DEFINER so policies do not recurse through RLS).
-- Grants via a share only count when share.owner_id = resource owner.
-- Soft-deleted rows/parents still grant read access on purpose: recipients
-- must be able to pull tombstones (deleted_at) to remove items locally.
-- -----------------------------------------------------------------------------
create function public.can_read_subject(p_subject_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.subjects s
    where s.id = p_subject_id
      and (
        s.owner_id = auth.uid()
        or exists (
          select 1 from public.shares sh
          where sh.resource_type = 'subject'
            and sh.resource_id = s.id
            and sh.owner_id = s.owner_id
            and sh.recipient_id = auth.uid()
        )
      )
  );
$$;

create function public.can_read_note(p_note_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.notes n
    where n.id = p_note_id
      and (
        n.owner_id = auth.uid()
        or exists (
          select 1 from public.shares sh
          where sh.recipient_id = auth.uid()
            and sh.owner_id = n.owner_id
            and (
              (sh.resource_type = 'note' and sh.resource_id = n.id)
              or (sh.resource_type = 'subject' and sh.resource_id = n.subject_id)
            )
        )
      )
  );
$$;

create function public.can_read_quiz(p_quiz_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.quizzes q
    where q.id = p_quiz_id
      and (
        q.owner_id = auth.uid()
        or exists (
          select 1 from public.shares sh
          where sh.recipient_id = auth.uid()
            and sh.owner_id = q.owner_id
            and (
              (sh.resource_type = 'quiz' and sh.resource_id = q.id)
              or (sh.resource_type = 'subject' and sh.resource_id = q.subject_id)
              or (sh.resource_type = 'note' and q.note_id is not null
                  and sh.resource_id = q.note_id)
            )
        )
      )
  );
$$;

-- True when the caller owns the (non-deleted) resource. Used by share inserts.
create function public.is_resource_owner(
  p_resource_type public.share_resource_type,
  p_resource_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case p_resource_type
    when 'subject' then exists (
      select 1 from public.subjects s
      where s.id = p_resource_id and s.owner_id = auth.uid() and s.deleted_at is null)
    when 'note' then exists (
      select 1 from public.notes n
      where n.id = p_resource_id and n.owner_id = auth.uid() and n.deleted_at is null)
    when 'quiz' then exists (
      select 1 from public.quizzes q
      where q.id = p_resource_id and q.owner_id = auth.uid() and q.deleted_at is null)
    else false
  end;
$$;

-- -----------------------------------------------------------------------------
-- Row level security
-- -----------------------------------------------------------------------------
alter table public.profiles          enable row level security;
alter table public.subjects          enable row level security;
alter table public.notes             enable row level security;
alter table public.quizzes           enable row level security;
alter table public.quiz_attempts     enable row level security;
alter table public.shares            enable row level security;
alter table public.note_image_copies enable row level security;

-- FORCE RLS makes RLS apply to the table owner too. The SECURITY DEFINER
-- helpers above run as the table owner and query these tables, so forcing is
-- only safe when the owner bypasses RLS (superuser or BYPASSRLS, which is the
-- case for Supabase's `postgres` role). Otherwise forcing would make the
-- helpers recurse through the policies, so we skip it and say so.
do $$
declare
  v_tables text[] := array['profiles', 'subjects', 'notes', 'quizzes',
                           'quiz_attempts', 'shares', 'note_image_copies'];
  v_table  text;
begin
  if exists (select 1 from pg_catalog.pg_roles r
             where r.rolname = current_user and (r.rolsuper or r.rolbypassrls)) then
    foreach v_table in array v_tables loop
      execute format('alter table public.%I force row level security', v_table);
    end loop;
  else
    raise notice 'Role % lacks BYPASSRLS; leaving RLS enabled but not forced', current_user;
  end if;
end;
$$;

-- profiles --------------------------------------------------------------------
create policy profiles_select on public.profiles
  for select to authenticated
  using (
    id = (select auth.uid())
    or exists (
      select 1 from public.shares sh
      where (sh.owner_id = (select auth.uid()) and sh.recipient_id = profiles.id)
         or (sh.recipient_id = (select auth.uid()) and sh.owner_id = profiles.id)
    )
  );

create policy profiles_update_own on public.profiles
  for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

-- subjects --------------------------------------------------------------------
create policy subjects_select on public.subjects
  for select to authenticated
  using (owner_id = (select auth.uid()) or public.can_read_subject(id));

create policy subjects_insert on public.subjects
  for insert to authenticated
  with check (owner_id = (select auth.uid()));

create policy subjects_update on public.subjects
  for update to authenticated
  using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));

create policy subjects_delete on public.subjects
  for delete to authenticated
  using (owner_id = (select auth.uid()));

-- notes -----------------------------------------------------------------------
create policy notes_select on public.notes
  for select to authenticated
  using (owner_id = (select auth.uid()) or public.can_read_note(id));

create policy notes_insert on public.notes
  for insert to authenticated
  with check (owner_id = (select auth.uid()));

create policy notes_update on public.notes
  for update to authenticated
  using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));

create policy notes_delete on public.notes
  for delete to authenticated
  using (owner_id = (select auth.uid()));

-- quizzes ---------------------------------------------------------------------
create policy quizzes_select on public.quizzes
  for select to authenticated
  using (owner_id = (select auth.uid()) or public.can_read_quiz(id));

create policy quizzes_insert on public.quizzes
  for insert to authenticated
  with check (owner_id = (select auth.uid()));

create policy quizzes_update on public.quizzes
  for update to authenticated
  using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));

create policy quizzes_delete on public.quizzes
  for delete to authenticated
  using (owner_id = (select auth.uid()));

-- quiz_attempts (private to the attempting user) -------------------------------
create policy quiz_attempts_select on public.quiz_attempts
  for select to authenticated
  using (owner_id = (select auth.uid()));

create policy quiz_attempts_insert on public.quiz_attempts
  for insert to authenticated
  with check (owner_id = (select auth.uid()) and public.can_read_quiz(quiz_id));

create policy quiz_attempts_update on public.quiz_attempts
  for update to authenticated
  using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));

create policy quiz_attempts_delete on public.quiz_attempts
  for delete to authenticated
  using (owner_id = (select auth.uid()));

-- shares ----------------------------------------------------------------------
create policy shares_select on public.shares
  for select to authenticated
  using (owner_id = (select auth.uid()) or recipient_id = (select auth.uid()));

create policy shares_insert on public.shares
  for insert to authenticated
  with check (
    owner_id = (select auth.uid())
    and recipient_id <> (select auth.uid())
    and public.is_resource_owner(resource_type, resource_id)
  );

create policy shares_delete on public.shares
  for delete to authenticated
  using (owner_id = (select auth.uid()));

-- note_image_copies -----------------------------------------------------------
create policy note_image_copies_select on public.note_image_copies
  for select to authenticated
  using (owner_id = (select auth.uid()));

create policy note_image_copies_insert on public.note_image_copies
  for insert to authenticated
  with check (
    owner_id = (select auth.uid())
    and split_part(to_path, '/', 1) = (select auth.uid())::text
  );

create policy note_image_copies_delete on public.note_image_copies
  for delete to authenticated
  using (owner_id = (select auth.uid()));

-- -----------------------------------------------------------------------------
-- Convenience view: shares + resource title (RLS of the caller applies).
-- -----------------------------------------------------------------------------
create view public.share_details
with (security_invoker = true)
as
select sh.id,
       sh.owner_id,
       sh.recipient_id,
       sh.resource_type,
       sh.resource_id,
       sh.created_at,
       coalesce(s.title, n.title, q.title) as resource_title
from public.shares sh
left join public.subjects s on sh.resource_type = 'subject' and s.id = sh.resource_id
left join public.notes    n on sh.resource_type = 'note'    and n.id = sh.resource_id
left join public.quizzes  q on sh.resource_type = 'quiz'    and q.id = sh.resource_id;

-- -----------------------------------------------------------------------------
-- RPCs
-- -----------------------------------------------------------------------------

-- Exact, case-insensitive email lookup. Returns 0 or 1 row; never lists.
create function public.find_user_by_email(p_email text)
returns table (id uuid, display_name text, email text)
language sql
stable
security definer
set search_path = ''
as $$
  select p.id, p.display_name, p.email
  from public.profiles p
  where auth.uid() is not null
    and p_email is not null
    and btrim(p_email) <> ''
    and lower(p.email) = lower(btrim(p_email))
  limit 1;
$$;

-- Copies one note (caller must be able to read it) into a subject the caller
-- owns, together with its non-deleted note-attached quizzes. Image references
-- `note-image://{src_owner}/{src_note}/{file}` are rewritten to
-- `note-image://{caller}/{new_note}/{file}` and a row per file is queued in
-- public.note_image_copies for the client to copy via the Storage API.
-- SECURITY INVOKER: all reads/writes go through the caller's RLS.
create function private.copy_note_into(p_note_id uuid, p_target_subject_id uuid)
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

  insert into public.notes (id, subject_id, owner_id, title, content_md)
  values (
    v_new_id,
    p_target_subject_id,
    v_uid,
    v_note.title,
    replace(v_note.content_md, 'note-image://' || v_src_dir, 'note-image://' || v_dst_dir)
  );

  insert into public.note_image_copies (owner_id, from_path, to_path)
  select distinct v_uid, v_src_dir || m.f[1], v_dst_dir || m.f[1]
  from regexp_matches(
         v_note.content_md,
         'note-image://' || v_src_dir || '([A-Za-z0-9._-]+)',
         'g'
       ) as m(f);

  insert into public.quizzes (id, subject_id, note_id, owner_id, title, description, source, questions)
  select gen_random_uuid(), p_target_subject_id, v_new_id, v_uid,
         q.title, q.description, q.source, q.questions
  from public.quizzes q
  where q.note_id = v_note.id
    and q.deleted_at is null
  order by q.created_at;

  return v_new_id;
end;
$$;

create function private.assert_owned_subject(p_subject_id uuid)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if p_subject_id is null or not exists (
    select 1 from public.subjects s
    where s.id = p_subject_id
      and s.owner_id = auth.uid()
      and s.deleted_at is null
  ) then
    raise exception 'target subject % is not owned by the caller', p_subject_id
      using errcode = '42501';
  end if;
end;
$$;

create function public.copy_subject(p_subject_id uuid)
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

  insert into public.quizzes (id, subject_id, note_id, owner_id, title, description, source, questions)
  select gen_random_uuid(), v_new_id, null, v_uid, q.title, q.description, q.source, q.questions
  from public.quizzes q
  where q.subject_id = v_src.id
    and q.note_id is null
    and q.deleted_at is null
  order by q.created_at;

  return v_new_id;
end;
$$;

create function public.copy_note(p_note_id uuid, p_target_subject_id uuid)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.notes n
    where n.id = p_note_id and n.deleted_at is null and public.can_read_note(n.id)
  ) then
    raise exception 'note % not found', p_note_id using errcode = 'P0002';
  end if;
  perform private.assert_owned_subject(p_target_subject_id);
  return private.copy_note_into(p_note_id, p_target_subject_id);
end;
$$;

create function public.copy_quiz(
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

  select * into v_src
  from public.quizzes q
  where q.id = p_quiz_id and q.deleted_at is null and public.can_read_quiz(q.id);
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

  insert into public.quizzes (id, subject_id, note_id, owner_id, title, description, source, questions)
  values (v_new_id, p_target_subject_id, p_target_note_id, v_uid,
          v_src.title, v_src.description, v_src.source, v_src.questions);

  return v_new_id;
end;
$$;

-- -----------------------------------------------------------------------------
-- Privileges. Supabase grants ALL (incl. TRUNCATE, which ignores RLS) on new
-- public tables and EXECUTE on new functions to anon/authenticated by default;
-- tighten that to exactly what the app needs.
-- -----------------------------------------------------------------------------
revoke all on table
  public.profiles, public.subjects, public.notes, public.quizzes,
  public.quiz_attempts, public.shares, public.note_image_copies, public.share_details
from public, anon, authenticated;

grant select, insert, update, delete on table
  public.subjects, public.notes, public.quizzes, public.quiz_attempts
to authenticated;
grant select, insert, delete on table public.shares, public.note_image_copies to authenticated;
grant select on table public.profiles, public.share_details to authenticated;
grant update (display_name) on table public.profiles to authenticated;

grant all on table
  public.profiles, public.subjects, public.notes, public.quizzes,
  public.quiz_attempts, public.shares, public.note_image_copies, public.share_details
to service_role;

-- Trigger functions: nobody needs EXECUTE (triggers fire regardless).
revoke execute on function
  private.tg_sync_row(), private.tg_touch_updated_at(),
  private.tg_notes_check_parent(), private.tg_quizzes_check_parent(),
  private.tg_notes_propagate_subject(), private.tg_attempts_immutable_quiz(),
  private.tg_delete_resource_shares(), private.handle_new_user(),
  private.handle_user_email_change()
from public, anon, authenticated;

-- Callable helpers / RPCs: authenticated only.
revoke execute on function
  public.can_read_subject(uuid), public.can_read_note(uuid), public.can_read_quiz(uuid),
  public.is_resource_owner(public.share_resource_type, uuid),
  public.find_user_by_email(text),
  public.copy_subject(uuid), public.copy_note(uuid, uuid), public.copy_quiz(uuid, uuid, uuid),
  private.copy_note_into(uuid, uuid), private.assert_owned_subject(uuid)
from public, anon;

grant execute on function
  public.can_read_subject(uuid), public.can_read_note(uuid), public.can_read_quiz(uuid),
  public.is_resource_owner(public.share_resource_type, uuid),
  public.find_user_by_email(text),
  public.copy_subject(uuid), public.copy_note(uuid, uuid), public.copy_quiz(uuid, uuid, uuid),
  private.copy_note_into(uuid, uuid), private.assert_owned_subject(uuid)
to authenticated, service_role;
