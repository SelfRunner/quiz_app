-- RPC tests: find_user_by_email, copy_subject, copy_note, copy_quiz.
begin;
create extension if not exists pgtap with schema extensions;
select plan(35);

insert into auth.users (id, email, raw_user_meta_data, email_confirmed_at) values
  ('11111111-1111-4111-8111-111111111111', 'alice@example.com', '{"display_name":"Alice"}', now()),
  ('22222222-2222-4222-8222-222222222222', 'Bob@Example.com',   '{"display_name":"Bob"}', now()),
  ('33333333-3333-4333-8333-333333333333', 'carol@example.com', '{}', now());

-- Fixture owned by A: S1 { N1 (with image) + QN1, N2 (deleted) + QN2, Q1 }
set local role authenticated;
set local request.jwt.claims to '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}';
insert into public.subjects (id, title, description, color) values
  ('aaaaaaaa-0000-4000-8000-000000000001', 'Biology', 'desc', 4294901760);
insert into public.notes (id, subject_id, title, content_md) values
  ('bbbbbbbb-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-000000000001', 'Cells',
   'Intro ![cell](note-image://11111111-1111-4111-8111-111111111111/bbbbbbbb-0000-4000-8000-000000000001/img-1.png) '
   || 'again ![cell](note-image://11111111-1111-4111-8111-111111111111/bbbbbbbb-0000-4000-8000-000000000001/img-1.png) '
   || 'and ![x](note-image://11111111-1111-4111-8111-111111111111/bbbbbbbb-0000-4000-8000-000000000001/img-2.jpg)'),
  ('bbbbbbbb-0000-4000-8000-000000000002', 'aaaaaaaa-0000-4000-8000-000000000001', 'Old', '');
insert into public.quizzes (id, subject_id, note_id, title, questions, source) values
  ('cccccccc-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-000000000001', null, 'Bio quiz',
   '[{"id":"q1","type":"true_false","prompt":"?","options":["True","False"],"correct_indices":[0]}]',
   '{"provider":"gemini"}'),
  ('cccccccc-0000-4000-8000-000000000002', 'aaaaaaaa-0000-4000-8000-000000000001',
   'bbbbbbbb-0000-4000-8000-000000000001', 'Cells quiz', '[]', null),
  ('cccccccc-0000-4000-8000-000000000003', 'aaaaaaaa-0000-4000-8000-000000000001',
   'bbbbbbbb-0000-4000-8000-000000000002', 'Old quiz', '[]', null);
update public.notes set deleted_at = now() where id = 'bbbbbbbb-0000-4000-8000-000000000002';
update public.quizzes set deleted_at = now() where id = 'cccccccc-0000-4000-8000-000000000003';
insert into public.shares (recipient_id, resource_type, resource_id) values
  ('22222222-2222-4222-8222-222222222222', 'subject', 'aaaaaaaa-0000-4000-8000-000000000001');

-- ============================================================ find_user_by_email
select results_eq(
  $$ select id, display_name, email from public.find_user_by_email('  BOB@example.COM ') $$,
  $$ values ('22222222-2222-4222-8222-222222222222'::uuid, 'Bob'::text, 'Bob@Example.com'::text) $$,
  'find_user_by_email: exact, case-insensitive, trimmed');
select is_empty($$ select * from public.find_user_by_email('bob') $$, 'no partial matches');
select is_empty($$ select * from public.find_user_by_email('%') $$, 'no wildcard matches');
select is_empty($$ select * from public.find_user_by_email('%@example.com') $$, 'no LIKE patterns');
select is_empty($$ select * from public.find_user_by_email('') $$, 'empty email returns nothing');
select is_empty($$ select * from public.find_user_by_email(null) $$, 'null email returns nothing');

-- ============================================================ copy_subject (B, via subject share)
reset role;
create temp table copied (kind text primary key, id uuid);
grant all on copied to authenticated;
set local role authenticated;
set local request.jwt.claims to '{"sub":"22222222-2222-4222-8222-222222222222","role":"authenticated"}';

select lives_ok($$
  insert into copied values ('subject', public.copy_subject('aaaaaaaa-0000-4000-8000-000000000001'))
$$, 'B copies the shared subject');
select results_eq(
  $$ select owner_id, title, description, color from public.subjects where id = (select id from copied where kind = 'subject') $$,
  $$ values ('22222222-2222-4222-8222-222222222222'::uuid, 'Biology'::text, 'desc'::text, 4294901760::bigint) $$,
  'copied subject is owned by B with the same fields');
select isnt((select id from copied where kind = 'subject'), 'aaaaaaaa-0000-4000-8000-000000000001'::uuid,
            'copied subject has a new id');

insert into copied
select 'note', id from public.notes where subject_id = (select id from copied where kind = 'subject');
select is((select count(*)::int from public.notes where subject_id = (select id from copied where kind = 'subject')), 1,
          'only non-deleted notes are copied');
select is((select owner_id from public.notes where id = (select id from copied where kind = 'note')),
          '22222222-2222-4222-8222-222222222222'::uuid, 'copied note is owned by B');
select is((select content_md from public.notes where id = (select id from copied where kind = 'note')),
          'Intro ![cell](note-image://22222222-2222-4222-8222-222222222222/' || (select id from copied where kind = 'note') || '/img-1.png) '
          || 'again ![cell](note-image://22222222-2222-4222-8222-222222222222/' || (select id from copied where kind = 'note') || '/img-1.png) '
          || 'and ![x](note-image://22222222-2222-4222-8222-222222222222/' || (select id from copied where kind = 'note') || '/img-2.jpg)',
          'image references are rewritten to the new owner/note prefix');
select results_eq(
  $$ select from_path, to_path from public.note_image_copies order by from_path $$,
  $$ select * from (values
       ('11111111-1111-4111-8111-111111111111/bbbbbbbb-0000-4000-8000-000000000001/img-1.png',
        '22222222-2222-4222-8222-222222222222/' || (select id from copied where kind = 'note') || '/img-1.png'),
       ('11111111-1111-4111-8111-111111111111/bbbbbbbb-0000-4000-8000-000000000001/img-2.jpg',
        '22222222-2222-4222-8222-222222222222/' || (select id from copied where kind = 'note') || '/img-2.jpg')
     ) v(f, t) $$,
  'one pending storage copy per distinct image');
select results_eq(
  $$ select note_id, title, questions, source from public.quizzes
     where subject_id = (select id from copied where kind = 'subject') order by title $$,
  $$ values (null::uuid, 'Bio quiz'::text,
             '[{"id":"q1","type":"true_false","prompt":"?","options":["True","False"],"correct_indices":[0]}]'::jsonb,
             '{"provider":"gemini"}'::jsonb),
            ((select id from copied where kind = 'note'), 'Cells quiz'::text, '[]'::jsonb, null::jsonb) $$,
  'quizzes copied (deleted ones skipped) with note_id remapped to the copied note');
select is((select count(*)::int from public.quizzes
           where owner_id = '22222222-2222-4222-8222-222222222222'
             and note_id = 'bbbbbbbb-0000-4000-8000-000000000001'), 0,
          'no copied quiz points at the original note');
select lives_ok($$
  update public.subjects set title = 'Mine now' where id = (select id from copied where kind = 'subject')
$$, 'B can edit the copy');
select lives_ok($$ delete from public.note_image_copies $$, 'B can clear processed image copy jobs');
select throws_ok($$
  insert into public.note_image_copies (from_path, to_path) values ('a/b/c', '11111111-1111-4111-8111-111111111111/x/y')
$$, '42501', null, 'cannot queue an image copy into someone else''s folder');

-- ============================================================ copy_note / copy_quiz (B)
select lives_ok($$
  insert into copied values ('note2', public.copy_note('bbbbbbbb-0000-4000-8000-000000000001',
                                                       (select id from copied where kind = 'subject')))
$$, 'B copies a readable note into an owned subject');
select is((select count(*)::int from public.quizzes where note_id = (select id from copied where kind = 'note2')), 1,
          'copy_note also copies the note-attached quiz');
select throws_ok($$
  select public.copy_note('bbbbbbbb-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-000000000001')
$$, '42501', null, 'copy_note into a subject B does not own fails');
select throws_ok($$
  select public.copy_note('bbbbbbbb-0000-4000-8000-000000000002', (select id from copied where kind = 'subject'))
$$, 'P0002', null, 'copy_note of a deleted note fails');

select lives_ok($$
  insert into copied values ('quiz', public.copy_quiz('cccccccc-0000-4000-8000-000000000001',
                                                      (select id from copied where kind = 'subject')))
$$, 'B copies a quiz into an owned subject');
select results_eq(
  $$ select owner_id, note_id, subject_id from public.quizzes where id = (select id from copied where kind = 'quiz') $$,
  $$ values ('22222222-2222-4222-8222-222222222222'::uuid, null::uuid, (select id from copied where kind = 'subject')) $$,
  'copied quiz is owned by B, subject-level');
select lives_ok($$
  insert into copied values ('quiz2', public.copy_quiz('cccccccc-0000-4000-8000-000000000002',
                                                       (select id from copied where kind = 'subject'),
                                                       (select id from copied where kind = 'note')))
$$, 'B copies a quiz onto an owned note');
select is((select note_id from public.quizzes where id = (select id from copied where kind = 'quiz2')),
          (select id from copied where kind = 'note'), 'copied quiz attached to the target note');
select throws_ok($$
  select public.copy_quiz('cccccccc-0000-4000-8000-000000000001', (select id from copied where kind = 'subject'),
                          'bbbbbbbb-0000-4000-8000-000000000001')
$$, '42501', null, 'copy_quiz onto someone else''s note fails');

reset role;
select is((select count(*)::int from public.notes where subject_id = 'aaaaaaaa-0000-4000-8000-000000000001'), 2,
          'originals untouched');
select is((select owner_id from public.subjects where id = 'aaaaaaaa-0000-4000-8000-000000000001'),
          '11111111-1111-4111-8111-111111111111'::uuid, 'original subject still owned by A');

-- ============================================================ C: no access
set local role authenticated;
set local request.jwt.claims to '{"sub":"33333333-3333-4333-8333-333333333333","role":"authenticated"}';
insert into public.subjects (id, title) values ('dddddddd-0000-4000-8000-000000000003', 'Carol''s');
select throws_ok($$ select public.copy_subject('aaaaaaaa-0000-4000-8000-000000000001') $$,
                 'P0002', null, 'C cannot copy an unshared subject');
select throws_ok($$ select public.copy_note('bbbbbbbb-0000-4000-8000-000000000001', 'dddddddd-0000-4000-8000-000000000003') $$,
                 'P0002', null, 'C cannot copy an unshared note');
select throws_ok($$ select public.copy_quiz('cccccccc-0000-4000-8000-000000000001', 'dddddddd-0000-4000-8000-000000000003') $$,
                 'P0002', null, 'C cannot copy an unshared quiz');
select is((select count(*)::int from public.notes), 0, 'failed copies left nothing behind for C');

-- ============================================================ anon
reset role;
set local role anon;
select throws_ok($$ select * from public.find_user_by_email('bob@example.com') $$, '42501', null,
                 'anon cannot call find_user_by_email');
select throws_ok($$ select public.copy_subject('aaaaaaaa-0000-4000-8000-000000000001') $$, '42501', null,
                 'anon cannot call copy_subject');
reset role;

select * from finish();
rollback;
