-- =============================================================================
-- Hardening (review findings). Applies on top of 20261002000000_init.sql and
-- 20261002000100_storage.sql; those two are already deployed and stay as is.
--
--   1. Sharing only resolves/accepts users whose email is confirmed
--      (auth.users.email_confirmed_at is not null). "Confirm email" MUST be
--      enabled in production (see README).
--   2. Shares no longer expose soft-deleted content: non-owners can read a
--      row only while it and every parent it hangs under (note -> subject,
--      quiz -> subject and note) have deleted_at is null. Owners still read
--      their own tombstones. Storage reads follow via can_read_note.
--      copy_* refuse deleted sources (including a deleted parent).
--   3. Soft-deleting a subject/note/quiz deletes the shares that point at it
--      (previously only a hard delete did).
--
-- Idempotent: functions use create or replace, triggers/policies are dropped
-- if they exist before being recreated, the cleanup delete is a no-op on rerun.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Confirmed users only
-- -----------------------------------------------------------------------------

-- True when p_user_id is an auth user with a confirmed email. With "Confirm
-- email" disabled GoTrue auto-confirms on signup, so this is always true then.
create or replace function private.is_confirmed_user(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from auth.users u
    where u.id = p_user_id
      and u.email_confirmed_at is not null
  );
$$;

revoke execute on function private.is_confirmed_user(uuid) from public, anon;
grant execute on function private.is_confirmed_user(uuid) to authenticated, service_role;

-- Exact, case-insensitive email lookup among confirmed users. 0 or 1 row.
create or replace function public.find_user_by_email(p_email text)
returns table (id uuid, display_name text, email text)
language sql
stable
security definer
set search_path = ''
as $$
  select p.id, p.display_name, p.email
  from public.profiles p
  join auth.users u on u.id = p.id
  where auth.uid() is not null
    and p_email is not null
    and btrim(p_email) <> ''
    and lower(p.email) = lower(btrim(p_email))
    and u.email_confirmed_at is not null
  limit 1;
$$;

-- -----------------------------------------------------------------------------
-- 2. Read helpers: share grants require live (non-deleted) rows and parents
-- -----------------------------------------------------------------------------
create or replace function public.can_read_subject(p_subject_id uuid)
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
        or (
          s.deleted_at is null
          and exists (
            select 1 from public.shares sh
            where sh.resource_type = 'subject'
              and sh.resource_id = s.id
              and sh.owner_id = s.owner_id
              and sh.recipient_id = auth.uid()
          )
        )
      )
  );
$$;

create or replace function public.can_read_note(p_note_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.notes n
    join public.subjects s on s.id = n.subject_id
    where n.id = p_note_id
      and (
        n.owner_id = auth.uid()
        or (
          n.deleted_at is null
          and s.deleted_at is null
          and exists (
            select 1 from public.shares sh
            where sh.recipient_id = auth.uid()
              and sh.owner_id = n.owner_id
              and (
                (sh.resource_type = 'note' and sh.resource_id = n.id)
                or (sh.resource_type = 'subject' and sh.resource_id = n.subject_id)
              )
          )
        )
      )
  );
$$;

create or replace function public.can_read_quiz(p_quiz_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.quizzes q
    join public.subjects s on s.id = q.subject_id
    left join public.notes n on n.id = q.note_id
    where q.id = p_quiz_id
      and (
        q.owner_id = auth.uid()
        or (
          q.deleted_at is null
          and s.deleted_at is null
          and n.deleted_at is null   -- also true when the quiz has no note
          and exists (
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
      )
  );
$$;

-- Share inserts: caller owns the resource and neither it nor a parent is
-- soft-deleted (a share on a trashed item would be dormant anyway).
create or replace function public.is_resource_owner(
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
      join public.subjects s on s.id = n.subject_id
      where n.id = p_resource_id and n.owner_id = auth.uid()
        and n.deleted_at is null and s.deleted_at is null)
    when 'quiz' then exists (
      select 1 from public.quizzes q
      join public.subjects s on s.id = q.subject_id
      left join public.notes n on n.id = q.note_id
      where q.id = p_resource_id and q.owner_id = auth.uid()
        and q.deleted_at is null and s.deleted_at is null and n.deleted_at is null)
    else false
  end;
$$;

-- Shares can only be addressed to confirmed users.
drop policy if exists shares_insert on public.shares;
create policy shares_insert on public.shares
  for insert to authenticated
  with check (
    owner_id = (select auth.uid())
    and recipient_id <> (select auth.uid())
    and public.is_resource_owner(resource_type, resource_id)
    and private.is_confirmed_user(recipient_id)
  );

-- -----------------------------------------------------------------------------
-- copy_*: refuse deleted sources, including sources under a deleted parent
-- (owners can still read their own tombstones, so check explicitly).
-- -----------------------------------------------------------------------------
create or replace function public.copy_note(p_note_id uuid, p_target_subject_id uuid)
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
    join public.subjects s on s.id = n.subject_id
    where n.id = p_note_id
      and n.deleted_at is null
      and s.deleted_at is null
      and public.can_read_note(n.id)
  ) then
    raise exception 'note % not found', p_note_id using errcode = 'P0002';
  end if;
  perform private.assert_owned_subject(p_target_subject_id);
  return private.copy_note_into(p_note_id, p_target_subject_id);
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
  join public.subjects s on s.id = q.subject_id
  left join public.notes n on n.id = q.note_id
  where q.id = p_quiz_id
    and q.deleted_at is null
    and s.deleted_at is null
    and n.deleted_at is null
    and public.can_read_quiz(q.id);
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
-- copy_subject already requires s.deleted_at is null and only copies
-- non-deleted notes/quizzes; copy_note_into skips deleted note quizzes.

-- -----------------------------------------------------------------------------
-- 3. Soft delete removes the shares pointing at the row.
-- private.tg_delete_resource_shares(type) deletes shares for old.id, which is
-- the same row on UPDATE, so it is reused as is.
-- -----------------------------------------------------------------------------
drop trigger if exists subjects_soft_delete_shares on public.subjects;
create trigger subjects_soft_delete_shares
  after update of deleted_at on public.subjects
  for each row when (old.deleted_at is null and new.deleted_at is not null)
  execute function private.tg_delete_resource_shares('subject');

drop trigger if exists notes_soft_delete_shares on public.notes;
create trigger notes_soft_delete_shares
  after update of deleted_at on public.notes
  for each row when (old.deleted_at is null and new.deleted_at is not null)
  execute function private.tg_delete_resource_shares('note');

drop trigger if exists quizzes_soft_delete_shares on public.quizzes;
create trigger quizzes_soft_delete_shares
  after update of deleted_at on public.quizzes
  for each row when (old.deleted_at is null and new.deleted_at is not null)
  execute function private.tg_delete_resource_shares('quiz');

-- One-time cleanup: shares created before this migration that point at rows
-- that are already soft-deleted.
delete from public.shares sh
where (sh.resource_type = 'subject' and exists (
        select 1 from public.subjects s where s.id = sh.resource_id and s.deleted_at is not null))
   or (sh.resource_type = 'note' and exists (
        select 1 from public.notes n where n.id = sh.resource_id and n.deleted_at is not null))
   or (sh.resource_type = 'quiz' and exists (
        select 1 from public.quizzes q where q.id = sh.resource_id and q.deleted_at is not null));
