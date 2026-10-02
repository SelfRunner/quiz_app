-- =============================================================================
-- Subject attachments ("Files" library). Applies on top of
-- 20261002000000_init.sql, 20261002000100_storage.sql and
-- 20261003000000_hardening.sql, which are deployed and stay unchanged.
--
--   * public.attachments: synced table (same conventions as notes), one row
--     per file attached to a subject. Shared together with the subject
--     (subject shares only; note/quiz shares never expose attachments).
--   * Private Storage bucket `attachments`, object path
--     {owner_id}/{subject_id}/{attachment_id}/{file}; the row's storage_path
--     must be exactly that path.
--   * note_image_copies gains a `bucket` column (default 'note-images') so the
--     existing copy queue also carries attachment blobs; copy_subject copies
--     the subject's live attachments and queues their Storage copies.
--
-- Contract: docs/CONTRACTS.md ("Attachments"). Design notes: supabase/README.md.
-- Idempotent: safe to run more than once (if not exists / create or replace /
-- drop ... if exists).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Table
-- -----------------------------------------------------------------------------
create table if not exists public.attachments (
  id             uuid primary key default gen_random_uuid(),
  subject_id     uuid not null references public.subjects (id) on delete cascade,
  owner_id       uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name           text not null check (char_length(name) between 1 and 512),
  mime_type      text check (mime_type is null or char_length(mime_type) <= 255),
  size_bytes     bigint not null default 0 check (size_bytes >= 0),
  kind           text not null default 'other'
                 check (kind in ('pdf', 'image', 'text', 'docx', 'audio', 'video', 'other')),
  storage_path   text not null unique,
  extracted_text text check (extracted_text is null or char_length(extracted_text) <= 200000),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  deleted_at     timestamptz,
  -- storage_path = {owner_id}/{subject_id}/{id}/{file}; {file} is one
  -- non-empty segment (no '/', not '.' or '..').
  constraint attachments_storage_path_shape check (
    char_length(storage_path) <= 1024
    and storage_path ~ '^[^/]+/[^/]+/[^/]+/[^/]+$'
    and split_part(storage_path, '/', 1) = owner_id::text
    and split_part(storage_path, '/', 2) = subject_id::text
    and split_part(storage_path, '/', 3) = id::text
    and split_part(storage_path, '/', 4) not in ('.', '..')
  )
);
comment on table public.attachments is
  'Files attached to a subject (Files library). Blob in Storage bucket attachments at storage_path. Readable by the owner and by recipients of a subject share.';

create index if not exists attachments_owner_updated_idx on public.attachments (owner_id, updated_at);
create index if not exists attachments_updated_idx       on public.attachments (updated_at);
create index if not exists attachments_subject_idx       on public.attachments (subject_id);

-- -----------------------------------------------------------------------------
-- Copy queue: one queue for both buckets. Existing rows / inserts without a
-- bucket keep meaning 'note-images'.
-- -----------------------------------------------------------------------------
alter table public.note_image_copies
  add column if not exists bucket text not null default 'note-images'
  constraint note_image_copies_bucket_check check (bucket in ('note-images', 'attachments'));

-- -----------------------------------------------------------------------------
-- Triggers
-- -----------------------------------------------------------------------------

-- An attachment must belong to a subject owned by the same user; subject_id
-- and storage_path are fixed at insert (the blob lives under that path).
create or replace function private.tg_attachments_check()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_subject_owner uuid;
begin
  if tg_op = 'UPDATE' then
    if new.subject_id is distinct from old.subject_id then
      raise exception 'attachment subject_id cannot be changed' using errcode = '42501';
    end if;
    if new.storage_path is distinct from old.storage_path then
      raise exception 'attachment storage_path cannot be changed' using errcode = '42501';
    end if;
    return new;
  end if;

  select s.owner_id into v_subject_owner
  from public.subjects s
  where s.id = new.subject_id;

  if not found then
    raise exception 'subject % does not exist', new.subject_id using errcode = '23503';
  end if;
  if v_subject_owner <> new.owner_id then
    raise exception 'subject % is not owned by the attachment owner', new.subject_id
      using errcode = '42501';
  end if;
  return new;
end;
$$;

revoke execute on function private.tg_attachments_check() from public, anon, authenticated;

drop trigger if exists attachments_sync_row on public.attachments;
create trigger attachments_sync_row before insert or update on public.attachments
  for each row execute function private.tg_sync_row();

drop trigger if exists attachments_check on public.attachments;
create trigger attachments_check before insert or update on public.attachments
  for each row execute function private.tg_attachments_check();

-- -----------------------------------------------------------------------------
-- Access helpers
-- -----------------------------------------------------------------------------

-- Owner (including own tombstones), or a live attachment whose subject the
-- caller can read. can_read_subject only grants non-owners access through a
-- subject share on a live subject, so note/quiz shares never expose files.
create or replace function public.can_read_attachment(p_attachment_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.attachments a
    where a.id = p_attachment_id
      and (
        a.owner_id = auth.uid()
        or (a.deleted_at is null and public.can_read_subject(a.subject_id))
      )
  );
$$;

-- True when p_name has the exact shape {owner_uuid}/{subject_uuid}/{attachment_uuid}/{file},
-- an attachment row with that storage_path exists (owned by the first segment,
-- in the subject of the second) and the caller can read it. Malformed paths
-- return false, never error.
create or replace function public.can_read_attachment_object(p_name text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_parts   text[] := string_to_array(p_name, '/');
  v_uuid_re constant text :=
    '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';
  v_subject uuid;
  v_id      uuid;
begin
  if p_name is null
     or coalesce(array_length(v_parts, 1), 0) <> 4
     or v_parts[4] = ''
     or v_parts[2] !~ v_uuid_re
     or v_parts[3] !~ v_uuid_re then
    return false;
  end if;
  v_subject := v_parts[2]::uuid;
  v_id := v_parts[3]::uuid;

  return exists (
    select 1 from public.attachments a
    where a.id = v_id
      and a.subject_id = v_subject
      and a.owner_id::text = v_parts[1]
      and a.storage_path = p_name
  ) and public.can_read_attachment(v_id);
end;
$$;

revoke execute on function
  public.can_read_attachment(uuid), public.can_read_attachment_object(text)
from public, anon;
grant execute on function
  public.can_read_attachment(uuid), public.can_read_attachment_object(text)
to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- Row level security
-- -----------------------------------------------------------------------------
alter table public.attachments enable row level security;

-- Same rule as the init migration: force only when the migration role
-- bypasses RLS (Supabase's postgres does), otherwise the definer helpers
-- would recurse through the policies.
do $$
begin
  if exists (select 1 from pg_catalog.pg_roles r
             where r.rolname = current_user and (r.rolsuper or r.rolbypassrls)) then
    alter table public.attachments force row level security;
  else
    raise notice 'Role % lacks BYPASSRLS; leaving RLS enabled but not forced', current_user;
  end if;
end;
$$;

drop policy if exists attachments_select on public.attachments;
create policy attachments_select on public.attachments
  for select to authenticated
  using (owner_id = (select auth.uid()) or public.can_read_attachment(id));

drop policy if exists attachments_insert on public.attachments;
create policy attachments_insert on public.attachments
  for insert to authenticated
  with check (owner_id = (select auth.uid()));

drop policy if exists attachments_update on public.attachments;
create policy attachments_update on public.attachments
  for update to authenticated
  using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));

drop policy if exists attachments_delete on public.attachments;
create policy attachments_delete on public.attachments
  for delete to authenticated
  using (owner_id = (select auth.uid()));

-- Privileges: replace Supabase's default ALL (incl. TRUNCATE) grants.
revoke all on table public.attachments from public, anon, authenticated;
grant select, insert, update, delete on table public.attachments to authenticated;
grant all on table public.attachments to service_role;

-- -----------------------------------------------------------------------------
-- Storage: private bucket `attachments`, path {owner_id}/{subject_id}/{attachment_id}/{file}
-- -----------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('attachments', 'attachments', false, 52428800, null)   -- 50 MiB, any type
on conflict (id) do nothing;

drop policy if exists "attachments: owner insert" on storage.objects;
create policy "attachments: owner insert" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'attachments'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists "attachments: owner update" on storage.objects;
create policy "attachments: owner update" on storage.objects
  for update to authenticated
  using (
    bucket_id = 'attachments'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  )
  with check (
    bucket_id = 'attachments'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists "attachments: owner delete" on storage.objects;
create policy "attachments: owner delete" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'attachments'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists "attachments: read own or shared" on storage.objects;
create policy "attachments: read own or shared" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'attachments'
    and (
      (storage.foldername(name))[1] = (select auth.uid())::text
      or public.can_read_attachment_object(name)
    )
  );

-- -----------------------------------------------------------------------------
-- copy_subject: also copies the subject's live attachments (new ids, new
-- storage paths under the caller) and queues their Storage copies in
-- note_image_copies with bucket = 'attachments'. Body otherwise identical to
-- the init migration (soft-delete checks unchanged).
-- -----------------------------------------------------------------------------
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

  insert into public.quizzes (id, subject_id, note_id, owner_id, title, description, source, questions)
  select gen_random_uuid(), v_new_id, null, v_uid, q.title, q.description, q.source, q.questions
  from public.quizzes q
  where q.subject_id = v_src.id
    and q.note_id is null
    and q.deleted_at is null
  order by q.created_at;

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
