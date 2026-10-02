-- =============================================================================
-- Study (Wave 2). Applies on top of 20261002000000_init.sql,
-- 20261002000100_storage.sql, 20261003000000_hardening.sql and
-- 20261004000000_attachments.sql, which are deployed and stay unchanged.
--
--   * public.decks: flashcard decks, synced/shared/copied exactly like
--     quizzes (subject + optional note, share resource type 'deck',
--     can_read_deck, copy_deck, included in copy_subject / copy_note).
--   * public.card_reviews: private per-user spaced-repetition state per card
--     (FSRS-ready). Insert needs can_read_deck(deck_id).
--   * public.mistakes: private per-user wrong-answer tracking per question.
--     Insert needs can_read_quiz(quiz_id).
--   * public.quiz_attempts: exam-mode columns (mode, time_limit_seconds,
--     question_ids, duration_seconds), additive with defaults/nulls.
--   * Fix: copy_note / copy_quiz (hardening versions) checked parent liveness
--     by joining subjects under the caller's RLS, so recipients of a direct
--     note/quiz share always got P0002. They now use private.is_live_*.
--
-- Contract: docs/CONTRACTS.md ("Study (Wave 2)"). Design notes: supabase/README.md.
--
-- Transaction safety: `alter type ... add value` may run inside a transaction
-- block (PG 12+), but the new value cannot be *used* in that same transaction
-- ("unsafe use of new enum value"). `supabase db push` and the SQL editor run
-- a script as one transaction, and SQL-function / view bodies are parsed at
-- creation, so this file never writes the literal 'deck' as a
-- share_resource_type: it compares `resource_type::text = 'deck'` instead.
-- The trigger argument 'deck' is only cast when the trigger fires (later).
--
-- Idempotent: safe to run more than once (if not exists / create or replace /
-- drop ... if exists).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Share resource type
-- -----------------------------------------------------------------------------
alter type public.share_resource_type add value if not exists 'deck';

-- -----------------------------------------------------------------------------
-- Card validation (used by the decks.cards CHECK)
-- -----------------------------------------------------------------------------

-- True when p_cards is a JSON array of objects
--   {"id": text 1..255 (unique within the array), "front": text, "back": text,
--    "hint": text | null | absent}
-- Extra keys are allowed (forward compatibility).
create or replace function private.deck_cards_valid(p_cards jsonb)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select case
    when p_cards is null or jsonb_typeof(p_cards) <> 'array' then false
    else not exists (
           select 1
           from jsonb_array_elements(p_cards) as c(v)
           where jsonb_typeof(c.v) <> 'object'
              or jsonb_typeof(c.v -> 'id') is distinct from 'string'
              or char_length(c.v ->> 'id') not between 1 and 255
              or jsonb_typeof(c.v -> 'front') is distinct from 'string'
              or jsonb_typeof(c.v -> 'back') is distinct from 'string'
              or coalesce(jsonb_typeof(c.v -> 'hint'), 'null') not in ('string', 'null')
         )
         and (select count(*) = count(distinct c.v ->> 'id')
              from jsonb_array_elements(p_cards) as c(v))
  end;
$$;

-- The CHECK runs as the inserting role, so authenticated needs EXECUTE.
revoke execute on function private.deck_cards_valid(jsonb) from public, anon;
grant execute on function private.deck_cards_valid(jsonb) to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- Tables
-- -----------------------------------------------------------------------------
create table if not exists public.decks (
  id          uuid primary key default gen_random_uuid(),
  subject_id  uuid not null references public.subjects (id) on delete cascade,
  note_id     uuid references public.notes (id) on delete cascade,
  owner_id    uuid not null default auth.uid() references auth.users (id) on delete cascade,
  title       text not null,
  description text,
  source      jsonb check (source is null or jsonb_typeof(source) in ('object', 'null')),
  cards       jsonb not null default '[]'::jsonb
              constraint decks_cards_valid check (private.deck_cards_valid(cards)),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz
);
comment on table public.decks is
  'Flashcard decks in a subject (optionally attached to a note). Shared/copied like quizzes (share resource type deck).';

create table if not exists public.card_reviews (
  id             uuid primary key default gen_random_uuid(),
  owner_id       uuid not null default auth.uid() references auth.users (id) on delete cascade,
  deck_id        uuid not null references public.decks (id) on delete cascade,
  card_id        text not null check (char_length(card_id) between 1 and 255),
  -- 0 new, 1 learning, 2 review, 3 relearning (FSRS State numbering)
  state          smallint not null default 0 check (state between 0 and 3),
  due_at         timestamptz not null default now(),
  stability      double precision not null default 0 check (stability >= 0),
  difficulty     double precision not null default 0 check (difficulty >= 0),
  elapsed_days   integer not null default 0 check (elapsed_days >= 0),
  scheduled_days integer not null default 0 check (scheduled_days >= 0),
  reps           integer not null default 0 check (reps >= 0),
  lapses         integer not null default 0 check (lapses >= 0),
  last_review_at timestamptz,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  deleted_at     timestamptz,
  constraint card_reviews_owner_deck_card_key unique (owner_id, deck_id, card_id)
);
comment on table public.card_reviews is
  'Private per-user spaced-repetition state of one card of a deck. Never shared.';

create table if not exists public.mistakes (
  id             uuid primary key default gen_random_uuid(),
  owner_id       uuid not null default auth.uid() references auth.users (id) on delete cascade,
  quiz_id        uuid not null references public.quizzes (id) on delete cascade,
  question_id    text not null check (char_length(question_id) between 1 and 255),
  wrong_count    integer not null default 0 check (wrong_count >= 0),
  correct_streak integer not null default 0 check (correct_streak >= 0),
  last_wrong_at  timestamptz,
  resolved_at    timestamptz,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  deleted_at     timestamptz,
  constraint mistakes_owner_quiz_question_key unique (owner_id, quiz_id, question_id)
);
comment on table public.mistakes is
  'Private per-user record of a wrongly answered quiz question (Mistakes practice set). Never shared.';

-- Exam mode on attempts: additive, defaults keep existing clients working.
alter table public.quiz_attempts
  add column if not exists mode text not null default 'practice'
    constraint quiz_attempts_mode_check check (mode in ('practice', 'exam', 'mistakes')),
  add column if not exists time_limit_seconds integer
    constraint quiz_attempts_time_limit_check check (time_limit_seconds is null or time_limit_seconds > 0),
  add column if not exists question_ids jsonb
    constraint quiz_attempts_question_ids_is_array
    check (question_ids is null or jsonb_typeof(question_ids) = 'array'),
  add column if not exists duration_seconds integer
    constraint quiz_attempts_duration_check check (duration_seconds is null or duration_seconds >= 0);

-- -----------------------------------------------------------------------------
-- Indexes
-- -----------------------------------------------------------------------------
create index if not exists decks_owner_updated_idx on public.decks (owner_id, updated_at);
create index if not exists decks_updated_idx       on public.decks (updated_at);
create index if not exists decks_subject_idx       on public.decks (subject_id);
create index if not exists decks_note_idx          on public.decks (note_id) where note_id is not null;

create index if not exists card_reviews_owner_updated_idx on public.card_reviews (owner_id, updated_at);
create index if not exists card_reviews_deck_idx          on public.card_reviews (deck_id);
create index if not exists card_reviews_owner_due_idx     on public.card_reviews (owner_id, due_at)
  where deleted_at is null;

create index if not exists mistakes_owner_updated_idx on public.mistakes (owner_id, updated_at);
create index if not exists mistakes_quiz_idx          on public.mistakes (quiz_id);

-- -----------------------------------------------------------------------------
-- Trigger functions
-- -----------------------------------------------------------------------------

-- Same rules as quizzes: subject (and note, if set) must have the same owner;
-- subject_id is normalized to the note's subject.
create or replace function private.tg_decks_check_parent()
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
      raise exception 'note % is not owned by the deck owner', new.note_id
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
    raise exception 'subject % is not owned by the deck owner', new.subject_id
      using errcode = '42501';
  end if;
  return new;
end;
$$;

-- When a note moves to another subject, its decks follow (quizzes already do).
create or replace function private.tg_notes_propagate_subject_decks()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.decks d
     set subject_id = new.subject_id
   where d.note_id = new.id
     and d.subject_id <> new.subject_id;
  return null;
end;
$$;

-- card_reviews.deck_id / card_id are fixed at insert (where access is checked).
create or replace function private.tg_card_reviews_immutable()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.deck_id is distinct from old.deck_id or new.card_id is distinct from old.card_id then
    raise exception 'card_reviews deck_id/card_id cannot be changed' using errcode = '42501';
  end if;
  return new;
end;
$$;

-- mistakes.quiz_id / question_id are fixed at insert (where access is checked).
create or replace function private.tg_mistakes_immutable()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.quiz_id is distinct from old.quiz_id or new.question_id is distinct from old.question_id then
    raise exception 'mistakes quiz_id/question_id cannot be changed' using errcode = '42501';
  end if;
  return new;
end;
$$;

revoke execute on function
  private.tg_decks_check_parent(), private.tg_notes_propagate_subject_decks(),
  private.tg_card_reviews_immutable(), private.tg_mistakes_immutable()
from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- Triggers
-- -----------------------------------------------------------------------------
drop trigger if exists decks_sync_row on public.decks;
create trigger decks_sync_row before insert or update on public.decks
  for each row execute function private.tg_sync_row();

drop trigger if exists decks_check_parent on public.decks;
create trigger decks_check_parent
  before insert or update of subject_id, note_id, owner_id on public.decks
  for each row execute function private.tg_decks_check_parent();

drop trigger if exists notes_propagate_subject_decks on public.notes;
create trigger notes_propagate_subject_decks
  after update of subject_id on public.notes
  for each row when (new.subject_id is distinct from old.subject_id)
  execute function private.tg_notes_propagate_subject_decks();

-- Shares pointing at a deck go away on hard delete (incl. FK cascades from a
-- subject/note) and on soft delete. The 'deck' argument is cast to the enum
-- only when the trigger fires.
drop trigger if exists decks_delete_shares on public.decks;
create trigger decks_delete_shares after delete on public.decks
  for each row execute function private.tg_delete_resource_shares('deck');

drop trigger if exists decks_soft_delete_shares on public.decks;
create trigger decks_soft_delete_shares
  after update of deleted_at on public.decks
  for each row when (old.deleted_at is null and new.deleted_at is not null)
  execute function private.tg_delete_resource_shares('deck');

drop trigger if exists card_reviews_sync_row on public.card_reviews;
create trigger card_reviews_sync_row before insert or update on public.card_reviews
  for each row execute function private.tg_sync_row();

drop trigger if exists card_reviews_immutable on public.card_reviews;
create trigger card_reviews_immutable before update on public.card_reviews
  for each row execute function private.tg_card_reviews_immutable();

drop trigger if exists mistakes_sync_row on public.mistakes;
create trigger mistakes_sync_row before insert or update on public.mistakes
  for each row execute function private.tg_sync_row();

drop trigger if exists mistakes_immutable on public.mistakes;
create trigger mistakes_immutable before update on public.mistakes
  for each row execute function private.tg_mistakes_immutable();

-- -----------------------------------------------------------------------------
-- Access helpers
-- -----------------------------------------------------------------------------

-- Mirrors can_read_quiz (hardening semantics): owner (including own
-- tombstones), or the deck, its subject and (if any) its note are live and
-- the caller holds a share from the deck owner on the deck, its subject or
-- its note.
create or replace function public.can_read_deck(p_deck_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.decks d
    join public.subjects s on s.id = d.subject_id
    left join public.notes n on n.id = d.note_id
    where d.id = p_deck_id
      and (
        d.owner_id = auth.uid()
        or (
          d.deleted_at is null
          and s.deleted_at is null
          and n.deleted_at is null   -- also true when the deck has no note
          and exists (
            select 1 from public.shares sh
            where sh.recipient_id = auth.uid()
              and sh.owner_id = d.owner_id
              and (
                (sh.resource_type::text = 'deck' and sh.resource_id = d.id)
                or (sh.resource_type = 'subject' and sh.resource_id = d.subject_id)
                or (sh.resource_type = 'note' and d.note_id is not null
                    and sh.resource_id = d.note_id)
              )
          )
        )
      )
  );
$$;

-- Share inserts (hardening semantics) + decks. Switches on the text value so
-- the body never parses 'deck' as the enum (see header).
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
  select case p_resource_type::text
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
    when 'deck' then exists (
      select 1 from public.decks d
      join public.subjects s on s.id = d.subject_id
      left join public.notes n on n.id = d.note_id
      where d.id = p_resource_id and d.owner_id = auth.uid()
        and d.deleted_at is null and s.deleted_at is null and n.deleted_at is null)
    else false
  end;
$$;

revoke execute on function public.can_read_deck(uuid) from public, anon;
grant execute on function public.can_read_deck(uuid) to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- Row level security
-- -----------------------------------------------------------------------------
alter table public.decks        enable row level security;
alter table public.card_reviews enable row level security;
alter table public.mistakes     enable row level security;

-- Same rule as the init migration: force only when the migration role
-- bypasses RLS (Supabase's postgres does), otherwise the definer helpers
-- would recurse through the policies.
do $$
begin
  if exists (select 1 from pg_catalog.pg_roles r
             where r.rolname = current_user and (r.rolsuper or r.rolbypassrls)) then
    alter table public.decks        force row level security;
    alter table public.card_reviews force row level security;
    alter table public.mistakes     force row level security;
  else
    raise notice 'Role % lacks BYPASSRLS; leaving RLS enabled but not forced', current_user;
  end if;
end;
$$;

-- decks -----------------------------------------------------------------------
drop policy if exists decks_select on public.decks;
create policy decks_select on public.decks
  for select to authenticated
  using (owner_id = (select auth.uid()) or public.can_read_deck(id));

drop policy if exists decks_insert on public.decks;
create policy decks_insert on public.decks
  for insert to authenticated
  with check (owner_id = (select auth.uid()));

drop policy if exists decks_update on public.decks;
create policy decks_update on public.decks
  for update to authenticated
  using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));

drop policy if exists decks_delete on public.decks;
create policy decks_delete on public.decks
  for delete to authenticated
  using (owner_id = (select auth.uid()));

-- card_reviews (private to the reviewing user) ----------------------------------
drop policy if exists card_reviews_select on public.card_reviews;
create policy card_reviews_select on public.card_reviews
  for select to authenticated
  using (owner_id = (select auth.uid()));

drop policy if exists card_reviews_insert on public.card_reviews;
create policy card_reviews_insert on public.card_reviews
  for insert to authenticated
  with check (owner_id = (select auth.uid()) and public.can_read_deck(deck_id));

drop policy if exists card_reviews_update on public.card_reviews;
create policy card_reviews_update on public.card_reviews
  for update to authenticated
  using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));

drop policy if exists card_reviews_delete on public.card_reviews;
create policy card_reviews_delete on public.card_reviews
  for delete to authenticated
  using (owner_id = (select auth.uid()));

-- mistakes (private to the user) -----------------------------------------------
drop policy if exists mistakes_select on public.mistakes;
create policy mistakes_select on public.mistakes
  for select to authenticated
  using (owner_id = (select auth.uid()));

drop policy if exists mistakes_insert on public.mistakes;
create policy mistakes_insert on public.mistakes
  for insert to authenticated
  with check (owner_id = (select auth.uid()) and public.can_read_quiz(quiz_id));

drop policy if exists mistakes_update on public.mistakes;
create policy mistakes_update on public.mistakes
  for update to authenticated
  using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));

drop policy if exists mistakes_delete on public.mistakes;
create policy mistakes_delete on public.mistakes
  for delete to authenticated
  using (owner_id = (select auth.uid()));

-- Privileges: replace Supabase's default ALL (incl. TRUNCATE) grants.
revoke all on table public.decks, public.card_reviews, public.mistakes
  from public, anon, authenticated;
grant select, insert, update, delete on table public.decks, public.card_reviews, public.mistakes
  to authenticated;
grant all on table public.decks, public.card_reviews, public.mistakes to service_role;

-- -----------------------------------------------------------------------------
-- share_details: resource_title also covers decks (same columns as before).
-- -----------------------------------------------------------------------------
create or replace view public.share_details
with (security_invoker = true)
as
select sh.id,
       sh.owner_id,
       sh.recipient_id,
       sh.resource_type,
       sh.resource_id,
       sh.created_at,
       coalesce(s.title, n.title, q.title, d.title) as resource_title
from public.shares sh
left join public.subjects s on sh.resource_type = 'subject' and s.id = sh.resource_id
left join public.notes    n on sh.resource_type = 'note'    and n.id = sh.resource_id
left join public.quizzes  q on sh.resource_type = 'quiz'    and q.id = sh.resource_id
left join public.decks    d on sh.resource_type::text = 'deck' and d.id = sh.resource_id;

-- -----------------------------------------------------------------------------
-- Copy RPCs (SECURITY INVOKER: every read/write goes through the caller's RLS)
-- -----------------------------------------------------------------------------

-- Liveness of a row and all its parents, independent of the caller's RLS.
-- Fix: the hardening copy_note / copy_quiz joined subjects (and notes) under
-- the caller's RLS, so a recipient of a direct note or quiz share (who cannot
-- see the parent subject) always got P0002. Access is still checked by
-- can_read_*; these only answer "is it (and its parents) not soft-deleted".
create or replace function private.is_live_note(p_note_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.notes n
    join public.subjects s on s.id = n.subject_id
    where n.id = p_note_id and n.deleted_at is null and s.deleted_at is null
  );
$$;

create or replace function private.is_live_quiz(p_quiz_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.quizzes q
    join public.subjects s on s.id = q.subject_id
    left join public.notes n on n.id = q.note_id
    where q.id = p_quiz_id and q.deleted_at is null and s.deleted_at is null
      and n.deleted_at is null
  );
$$;

create or replace function private.is_live_deck(p_deck_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.decks d
    join public.subjects s on s.id = d.subject_id
    left join public.notes n on n.id = d.note_id
    where d.id = p_deck_id and d.deleted_at is null and s.deleted_at is null
      and n.deleted_at is null
  );
$$;

revoke execute on function
  private.is_live_note(uuid), private.is_live_quiz(uuid), private.is_live_deck(uuid)
from public, anon;
grant execute on function
  private.is_live_note(uuid), private.is_live_quiz(uuid), private.is_live_deck(uuid)
to authenticated, service_role;

-- copy_note: same contract as the hardening version, parent check via
-- is_live_note (works for direct note-share recipients).
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
  if not (public.can_read_note(p_note_id) and private.is_live_note(p_note_id)) then
    raise exception 'note % not found', p_note_id using errcode = 'P0002';
  end if;
  perform private.assert_owned_subject(p_target_subject_id);
  return private.copy_note_into(p_note_id, p_target_subject_id);
end;
$$;

-- copy_quiz: same contract as the hardening version, parent check via
-- is_live_quiz (works for direct quiz/note-share recipients).
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

  insert into public.quizzes (id, subject_id, note_id, owner_id, title, description, source, questions)
  values (v_new_id, p_target_subject_id, p_target_note_id, v_uid,
          v_src.title, v_src.description, v_src.source, v_src.questions);

  return v_new_id;
end;
$$;

-- Copies one deck the caller can read into a subject (and optionally a note
-- of that subject) the caller owns. Card ids are kept. Review state is not
-- copied (card_reviews are per user and per deck).
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

  insert into public.decks (id, subject_id, note_id, owner_id, title, description, source, cards)
  values (v_new_id, p_target_subject_id, p_target_note_id, v_uid,
          v_src.title, v_src.description, v_src.source, v_src.cards);

  return v_new_id;
end;
$$;

revoke execute on function public.copy_deck(uuid, uuid, uuid) from public, anon;
grant execute on function public.copy_deck(uuid, uuid, uuid) to authenticated, service_role;

-- copy_note_into (used by copy_note and copy_subject): body identical to the
-- init migration, plus the note's non-deleted decks (note_id remapped).
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

  insert into public.decks (id, subject_id, note_id, owner_id, title, description, source, cards)
  select gen_random_uuid(), p_target_subject_id, v_new_id, v_uid,
         d.title, d.description, d.source, d.cards
  from public.decks d
  where d.note_id = v_note.id
    and d.deleted_at is null
  order by d.created_at;

  return v_new_id;
end;
$$;

-- copy_subject: body identical to 20261004000000_attachments.sql, plus the
-- subject's non-deleted subject-level decks (note decks come with their note).
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

  insert into public.decks (id, subject_id, note_id, owner_id, title, description, source, cards)
  select gen_random_uuid(), v_new_id, null, v_uid, d.title, d.description, d.source, d.cards
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
