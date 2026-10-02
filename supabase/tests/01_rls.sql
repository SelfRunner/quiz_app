-- RLS / trigger tests: owner CRUD, subject/note/quiz shares, revoke,
-- soft-deleted rows hidden from recipients, attempts privacy, profiles, owner_id immutability, injection.
-- Run with `supabase test db` (or supabase/tests/local_stubs/run_local.sh).
begin;
create extension if not exists pgtap with schema extensions;
select plan(75);

-- Users: A = alice (owner), B = bob (recipient), C = carol (stranger)
insert into auth.users (id, email, raw_user_meta_data, email_confirmed_at) values
  ('11111111-1111-4111-8111-111111111111', 'alice@example.com', '{"display_name":"Alice"}', now()),
  ('22222222-2222-4222-8222-222222222222', 'bob@example.com',   '{"display_name":"Bob"}', now()),
  ('33333333-3333-4333-8333-333333333333', 'carol@example.com', '{}', now());

select is((select display_name from public.profiles where id = '11111111-1111-4111-8111-111111111111'),
          'Alice', 'profile created by trigger with display_name from metadata');
select is((select display_name from public.profiles where id = '33333333-3333-4333-8333-333333333333'),
          'carol', 'display_name falls back to email local part');

-- ============================================================ A: owner CRUD
set local role authenticated;
set local request.jwt.claims to '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}';

select lives_ok($$
  insert into public.subjects (id, title, updated_at) values
    ('aaaaaaaa-0000-4000-8000-000000000001', 'Biology', '2000-01-01'),
    ('aaaaaaaa-0000-4000-8000-000000000002', 'Chemistry', '2000-01-01')
$$, 'owner inserts subjects');
select is((select owner_id from public.subjects where id = 'aaaaaaaa-0000-4000-8000-000000000001'),
          '11111111-1111-4111-8111-111111111111'::uuid, 'owner_id defaults to auth.uid()');
select is((select updated_at from public.subjects where id = 'aaaaaaaa-0000-4000-8000-000000000001'),
          now(), 'updated_at is set by the server, client value ignored');

select lives_ok($$
  insert into public.notes (id, subject_id, title, content_md) values
    ('bbbbbbbb-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-000000000001', 'Cells', '# Cells'),
    ('bbbbbbbb-0000-4000-8000-000000000002', 'aaaaaaaa-0000-4000-8000-000000000001', 'DNA', ''),
    ('bbbbbbbb-0000-4000-8000-000000000003', 'aaaaaaaa-0000-4000-8000-000000000002', 'Atoms', ''),
    ('bbbbbbbb-0000-4000-8000-000000000005', 'aaaaaaaa-0000-4000-8000-000000000002', 'Bonds', '')
$$, 'owner inserts notes');

select lives_ok($$
  insert into public.quizzes (id, subject_id, note_id, title, questions) values
    ('cccccccc-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-000000000001', null,
     'Bio quiz', '[{"id":"q1","type":"true_false","prompt":"?","options":["True","False"],"correct_indices":[0]}]'),
    ('cccccccc-0000-4000-8000-000000000002', 'aaaaaaaa-0000-4000-8000-000000000001',
     'bbbbbbbb-0000-4000-8000-000000000001', 'Cells quiz', '[]'),
    ('cccccccc-0000-4000-8000-000000000003', 'aaaaaaaa-0000-4000-8000-000000000002', null, 'Chem quiz', '[]'),
    ('cccccccc-0000-4000-8000-000000000004', 'aaaaaaaa-0000-4000-8000-000000000002',
     'bbbbbbbb-0000-4000-8000-000000000003', 'Atoms quiz', '[]')
$$, 'owner inserts quizzes (subject-level and note-attached)');

select throws_ok($$
  insert into public.quizzes (subject_id, title, questions)
  values ('aaaaaaaa-0000-4000-8000-000000000001', 'bad', '{"not":"array"}')
$$, '23514', null, 'questions must be a JSON array');

select throws_ok($$
  insert into public.subjects (title, owner_id) values ('spoof', '22222222-2222-4222-8222-222222222222')
$$, '42501', null, 'cannot insert a row owned by someone else');

select throws_ok($$
  update public.subjects set owner_id = '22222222-2222-4222-8222-222222222222'
  where id = 'aaaaaaaa-0000-4000-8000-000000000001'
$$, '42501', null, 'owner cannot hand a row to another owner_id');

select lives_ok($$
  update public.subjects set title = 'Biology 101' where id = 'aaaaaaaa-0000-4000-8000-000000000001'
$$, 'owner updates own subject');
select is((select title from public.subjects where id = 'aaaaaaaa-0000-4000-8000-000000000001'),
          'Biology 101', 'owner update applied');

-- note-attached quiz: subject_id is normalized to the note's subject
select lives_ok($$
  insert into public.quizzes (id, subject_id, note_id, title)
  values ('cccccccc-0000-4000-8000-000000000009', 'aaaaaaaa-0000-4000-8000-000000000001',
          'bbbbbbbb-0000-4000-8000-000000000003', 'normalized')
$$, 'quiz with mismatched subject/note is accepted');
select is((select subject_id from public.quizzes where id = 'cccccccc-0000-4000-8000-000000000009'),
          'aaaaaaaa-0000-4000-8000-000000000002'::uuid, 'quiz.subject_id normalized to its note''s subject');
select lives_ok($$
  insert into public.notes (id, subject_id, title, content_md)
  values ('bbbbbbbb-0000-4000-8000-000000000005', 'aaaaaaaa-0000-4000-8000-000000000002', 'Bonds', 'v2')
  on conflict (id) do update set title = excluded.title, content_md = excluded.content_md
$$, 'owner upsert (sync push) updates an existing row');
select is((select content_md from public.notes where id = 'bbbbbbbb-0000-4000-8000-000000000005'), 'v2',
          'owner upsert applied');
select lives_ok($$ delete from public.quizzes where id = 'cccccccc-0000-4000-8000-000000000009' $$,
                'owner hard-deletes own quiz');
select is((select count(*)::int from public.quizzes where id = 'cccccccc-0000-4000-8000-000000000009'), 0,
          'hard delete applied');

-- ============================================================ B before sharing
set local request.jwt.claims to '{"sub":"22222222-2222-4222-8222-222222222222","role":"authenticated"}';
select is((select count(*)::int from public.subjects), 0, 'B sees no subjects before sharing');
select is((select count(*)::int from public.notes), 0, 'B sees no notes before sharing');
select is((select count(*)::int from public.profiles), 1, 'B sees only own profile before sharing');

-- ============================================================ A shares
set local request.jwt.claims to '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}';
select lives_ok($$
  insert into public.shares (id, recipient_id, resource_type, resource_id) values
    ('ffffffff-0000-4000-8000-000000000001', '22222222-2222-4222-8222-222222222222', 'subject',
     'aaaaaaaa-0000-4000-8000-000000000001')
$$, 'A shares subject S1 with B');
select throws_ok($$
  insert into public.shares (recipient_id, resource_type, resource_id) values
    ('11111111-1111-4111-8111-111111111111', 'subject', 'aaaaaaaa-0000-4000-8000-000000000001')
$$, '42501', null, 'cannot share with yourself');
select throws_ok($$
  insert into public.shares (recipient_id, resource_type, resource_id) values
    ('33333333-3333-4333-8333-333333333333', 'subject', 'aaaaaaaa-0000-4000-8000-0000000000ff')
$$, '42501', null, 'cannot share a resource that does not exist');
select throws_ok($$
  insert into public.shares (recipient_id, resource_type, resource_id, owner_id) values
    ('33333333-3333-4333-8333-333333333333', 'subject', 'aaaaaaaa-0000-4000-8000-000000000001',
     '22222222-2222-4222-8222-222222222222')
$$, '42501', null, 'cannot forge share owner_id');
select lives_ok($$
  insert into public.shares (id, recipient_id, resource_type, resource_id) values
    ('ffffffff-0000-4000-8000-000000000002', '33333333-3333-4333-8333-333333333333', 'note',
     'bbbbbbbb-0000-4000-8000-000000000003')
$$, 'A shares note N3 with C');

-- ============================================================ B (subject share)
set local request.jwt.claims to '{"sub":"22222222-2222-4222-8222-222222222222","role":"authenticated"}';
select is((select count(*)::int from public.subjects), 1, 'B sees the shared subject');
select is((select count(*)::int from public.notes), 2, 'B sees all notes of the shared subject');
select is((select count(*)::int from public.quizzes), 2,
          'B sees subject-level and note-attached quizzes of the shared subject');
select is((select count(*)::int from public.notes where subject_id = 'aaaaaaaa-0000-4000-8000-000000000002'), 0,
          'B does not see notes of the unshared subject');
select is((select count(*)::int from public.shares), 1, 'B sees only shares addressed to B');
select is((select display_name from public.profiles where id = '11111111-1111-4111-8111-111111111111'),
          'Alice', 'B can read the profile of the user who shared with B');
select is((select count(*)::int from public.profiles where id = '33333333-3333-4333-8333-333333333333'), 0,
          'B cannot read unrelated profiles');
select is((select resource_title from public.share_details where id = 'ffffffff-0000-4000-8000-000000000001'),
          'Biology 101', 'share_details exposes the resource title to the recipient');

-- B cannot modify A's content (RLS filters the rows -> 0 rows affected)
update public.subjects set title = 'hacked' where id = 'aaaaaaaa-0000-4000-8000-000000000001';
update public.notes set content_md = 'hacked' where id = 'bbbbbbbb-0000-4000-8000-000000000001';
delete from public.notes where id = 'bbbbbbbb-0000-4000-8000-000000000002';
delete from public.quizzes where id = 'cccccccc-0000-4000-8000-000000000001';
delete from public.shares where id = 'ffffffff-0000-4000-8000-000000000001';

select throws_ok($$
  insert into public.notes (id, subject_id, title, owner_id)
  values ('bbbbbbbb-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-000000000001', 'x',
          '11111111-1111-4111-8111-111111111111')
  on conflict (id) do update set title = excluded.title
$$, '42501', null, 'recipient upsert of a shared row is rejected');
select throws_ok($$
  insert into public.notes (subject_id, title, owner_id)
  values ('aaaaaaaa-0000-4000-8000-000000000001', 'injected', '11111111-1111-4111-8111-111111111111')
$$, '42501', null, 'B cannot insert a note owned by A');
select throws_ok($$
  insert into public.notes (subject_id, title)
  values ('aaaaaaaa-0000-4000-8000-000000000001', 'injected')
$$, '42501', null, 'B cannot attach own note to A''s subject (cross-owner subject_id)');
select lives_ok($$
  insert into public.subjects (id, title) values ('dddddddd-0000-4000-8000-000000000001', 'Bob''s')
$$, 'B creates own subject');
select throws_ok($$
  insert into public.quizzes (subject_id, note_id, title)
  values ('dddddddd-0000-4000-8000-000000000001', 'bbbbbbbb-0000-4000-8000-000000000001', 'injected')
$$, '42501', null, 'B cannot attach own quiz to A''s note');
select throws_ok($$
  insert into public.notes (id, subject_id, title) values
    ('bbbbbbbb-0000-4000-8000-0000000000b1', 'dddddddd-0000-4000-8000-000000000001', 'mine');
  update public.notes set subject_id = 'aaaaaaaa-0000-4000-8000-000000000001'
  where id = 'bbbbbbbb-0000-4000-8000-0000000000b1'
$$, '42501', null, 'B cannot move own note into A''s subject');
select throws_ok($$
  insert into public.shares (recipient_id, resource_type, resource_id) values
    ('33333333-3333-4333-8333-333333333333', 'subject', 'aaaaaaaa-0000-4000-8000-000000000001')
$$, '42501', null, 'B cannot re-share A''s subject');

-- attempts
select lives_ok($$
  insert into public.quiz_attempts (id, quiz_id, total, score)
  values ('eeeeeeee-0000-4000-8000-000000000001', 'cccccccc-0000-4000-8000-000000000001', 1, 1)
$$, 'B records an attempt on a shared quiz');
select throws_ok($$
  insert into public.quiz_attempts (quiz_id, total, owner_id)
  values ('cccccccc-0000-4000-8000-000000000001', 1, '11111111-1111-4111-8111-111111111111')
$$, '42501', null, 'B cannot record an attempt for A');
select throws_ok($$
  insert into public.quiz_attempts (quiz_id, total)
  values ('cccccccc-0000-4000-8000-000000000003', 1)
$$, '42501', null, 'B cannot record an attempt on an unshared quiz');
select throws_ok($$
  update public.quiz_attempts set quiz_id = 'cccccccc-0000-4000-8000-000000000003'
  where id = 'eeeeeeee-0000-4000-8000-000000000001'
$$, '42501', null, 'attempt quiz_id is immutable');

reset role;
select is((select title from public.subjects where id = 'aaaaaaaa-0000-4000-8000-000000000001'),
          'Biology 101', 'B update of A''s subject had no effect');
select is((select content_md from public.notes where id = 'bbbbbbbb-0000-4000-8000-000000000001'),
          '# Cells', 'B update of A''s note had no effect');
select is((select count(*)::int from public.notes where id = 'bbbbbbbb-0000-4000-8000-000000000002'), 1,
          'B delete of A''s note had no effect');
select is((select count(*)::int from public.quizzes where id = 'cccccccc-0000-4000-8000-000000000001'), 1,
          'B delete of A''s quiz had no effect');
select is((select count(*)::int from public.shares where id = 'ffffffff-0000-4000-8000-000000000001'), 1,
          'recipient cannot delete the share');
select throws_ok($$
  update public.subjects set owner_id = '22222222-2222-4222-8222-222222222222'
  where id = 'aaaaaaaa-0000-4000-8000-000000000001'
$$, '42501', 'owner_id cannot be changed', 'owner_id is immutable even without RLS');

-- ============================================================ A: future items, tombstones, attempts privacy
set local role authenticated;
set local request.jwt.claims to '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}';
insert into public.notes (id, subject_id, title)
values ('bbbbbbbb-0000-4000-8000-000000000004', 'aaaaaaaa-0000-4000-8000-000000000001', 'Later note');
update public.notes set deleted_at = now() where id = 'bbbbbbbb-0000-4000-8000-000000000002';
select is((select count(*)::int from public.quiz_attempts), 0, 'A cannot see B''s attempts on A''s quiz');

set local request.jwt.claims to '{"sub":"22222222-2222-4222-8222-222222222222","role":"authenticated"}';
select is((select count(*)::int from public.notes where subject_id = 'aaaaaaaa-0000-4000-8000-000000000001'), 2,
          'B sees notes added after the share (live subject share), minus soft-deleted ones');
select is((select count(*)::int from public.notes where id = 'bbbbbbbb-0000-4000-8000-000000000002'), 0,
          'B no longer sees a soft-deleted note (client reconciles it away)');
select is((select count(*)::int from public.quiz_attempts), 1, 'B sees own attempt');

-- ============================================================ C (note share + stranger)
set local request.jwt.claims to '{"sub":"33333333-3333-4333-8333-333333333333","role":"authenticated"}';
select is((select count(*)::int from public.subjects), 0, 'note share does not expose the parent subject');
select is((select array_agg(id)::text from public.notes), '{bbbbbbbb-0000-4000-8000-000000000003}',
          'note share exposes only that note, not sibling notes');
select is((select array_agg(id)::text from public.quizzes), '{cccccccc-0000-4000-8000-000000000004}',
          'note share exposes the note-attached quiz but not subject-level quizzes');
select is((select count(*)::int from public.notes where subject_id = 'aaaaaaaa-0000-4000-8000-000000000001'), 0,
          'C sees nothing of subject S1');
select is((select count(*)::int from public.quiz_attempts), 0, 'C sees no attempts');
select throws_ok($$
  insert into public.quiz_attempts (quiz_id, total) values ('cccccccc-0000-4000-8000-000000000001', 1)
$$, '42501', null, 'C cannot record an attempt on a quiz C cannot read');

-- ============================================================ quiz-only share
set local request.jwt.claims to '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}';
insert into public.shares (id, recipient_id, resource_type, resource_id) values
  ('ffffffff-0000-4000-8000-000000000003', '33333333-3333-4333-8333-333333333333', 'quiz',
   'cccccccc-0000-4000-8000-000000000001');
set local request.jwt.claims to '{"sub":"33333333-3333-4333-8333-333333333333","role":"authenticated"}';
select is((select count(*)::int from public.quizzes where id = 'cccccccc-0000-4000-8000-000000000001'), 1,
          'quiz share exposes the quiz');
select is((select count(*)::int from public.notes where subject_id = 'aaaaaaaa-0000-4000-8000-000000000001'), 0,
          'quiz share does not expose notes of the subject');

-- ============================================================ revoke
set local request.jwt.claims to '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}';
select lives_ok($$ delete from public.shares where id = 'ffffffff-0000-4000-8000-000000000001' $$,
                'A revokes the subject share');
select lives_ok($$ update public.profiles set display_name = 'Alice A.' $$, 'A updates own display_name');
select throws_ok($$ update public.profiles set email = 'x@example.com' $$, '42501', null,
                 'profiles.email is not client-writable');

set local request.jwt.claims to '{"sub":"22222222-2222-4222-8222-222222222222","role":"authenticated"}';
select is((select count(*)::int from public.subjects where owner_id = '11111111-1111-4111-8111-111111111111'), 0,
          'after revoke B no longer sees the subject');
select is((select count(*)::int from public.notes where owner_id = '11111111-1111-4111-8111-111111111111'), 0,
          'after revoke B no longer sees the notes');
select is((select count(*)::int from public.quizzes where owner_id = '11111111-1111-4111-8111-111111111111'), 0,
          'after revoke B no longer sees the quizzes');
select is((select count(*)::int from public.quiz_attempts), 1, 'B keeps own attempt history after revoke');
select is((select count(*)::int from public.profiles where id = '11111111-1111-4111-8111-111111111111'), 0,
          'after revoke B can no longer read A''s profile');
update public.profiles set display_name = 'pwned' where id = '11111111-1111-4111-8111-111111111111';

-- ============================================================ hard delete removes shares; anon
reset role;
select is((select display_name from public.profiles where id = '11111111-1111-4111-8111-111111111111'),
          'Alice A.', 'B cannot update A''s profile');
delete from public.subjects where id = 'aaaaaaaa-0000-4000-8000-000000000002';
select is((select count(*)::int from public.shares where id = 'ffffffff-0000-4000-8000-000000000002'), 0,
          'hard-deleting a subject removes shares of its (cascaded) notes');

set local role anon;
select throws_ok($$ select count(*) from public.subjects $$, '42501', null, 'anon has no table access');
select throws_ok($$ select public.can_read_subject('aaaaaaaa-0000-4000-8000-000000000001') $$, '42501', null,
                 'anon cannot execute helpers');
reset role;

select * from finish();
rollback;
