-- Hardening tests (migration 20261003000000_hardening.sql):
--   * sharing resolves/accepts confirmed users only,
--   * recipients lose access to soft-deleted rows (and rows under a
--     soft-deleted parent), storage follows, owners keep their tombstones,
--   * soft delete removes the shares pointing at the row,
--   * copy_* refuse deleted sources.
begin;
create extension if not exists pgtap with schema extensions;
select plan(45);

-- A = alice (owner), B = bob, C = carol (recipients), D = dave (unconfirmed)
insert into auth.users (id, email, raw_user_meta_data, email_confirmed_at) values
  ('11111111-1111-4111-8111-111111111111', 'alice@example.com', '{}', now()),
  ('22222222-2222-4222-8222-222222222222', 'bob@example.com',   '{}', now()),
  ('33333333-3333-4333-8333-333333333333', 'carol@example.com', '{}', now()),
  ('44444444-4444-4444-8444-444444444444', 'dave@example.com',  '{}', null);

-- Fixture owned by A:
--   S1 { N1 (image) + QN1, N2, Q1 }   S2 { N3 (image) }   S3 (copy target)
set local role authenticated;
set local request.jwt.claims to '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}';
insert into public.subjects (id, title) values
  ('aaaaaaaa-0000-4000-8000-000000000001', 'S1'),
  ('aaaaaaaa-0000-4000-8000-000000000002', 'S2'),
  ('aaaaaaaa-0000-4000-8000-000000000003', 'S3');
insert into public.notes (id, subject_id, title) values
  ('bbbbbbbb-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-000000000001', 'N1'),
  ('bbbbbbbb-0000-4000-8000-000000000002', 'aaaaaaaa-0000-4000-8000-000000000001', 'N2'),
  ('bbbbbbbb-0000-4000-8000-000000000003', 'aaaaaaaa-0000-4000-8000-000000000002', 'N3');
insert into public.quizzes (id, subject_id, note_id, title) values
  ('cccccccc-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-000000000001', null, 'Q1'),
  ('cccccccc-0000-4000-8000-000000000002', 'aaaaaaaa-0000-4000-8000-000000000001',
   'bbbbbbbb-0000-4000-8000-000000000001', 'QN1');
insert into storage.objects (bucket_id, name) values
  ('note-images', '11111111-1111-4111-8111-111111111111/bbbbbbbb-0000-4000-8000-000000000001/a.png'),
  ('note-images', '11111111-1111-4111-8111-111111111111/bbbbbbbb-0000-4000-8000-000000000003/c.png');

-- ============================================================ confirmed users only
select is_empty($$ select * from public.find_user_by_email('dave@example.com') $$,
                'find_user_by_email ignores unconfirmed users');
select results_eq($$ select id from public.find_user_by_email('bob@example.com') $$,
                  $$ values ('22222222-2222-4222-8222-222222222222'::uuid) $$,
                  'find_user_by_email finds confirmed users');
select throws_ok($$
  insert into public.shares (recipient_id, resource_type, resource_id) values
    ('44444444-4444-4444-8444-444444444444', 'subject', 'aaaaaaaa-0000-4000-8000-000000000001')
$$, '42501', null, 'cannot share with an unconfirmed user');

select lives_ok($$
  insert into public.shares (id, recipient_id, resource_type, resource_id) values
    ('ffffffff-0000-4000-8000-000000000001', '22222222-2222-4222-8222-222222222222', 'subject',
     'aaaaaaaa-0000-4000-8000-000000000001'),
    ('ffffffff-0000-4000-8000-000000000002', '33333333-3333-4333-8333-333333333333', 'note',
     'bbbbbbbb-0000-4000-8000-000000000001'),
    ('ffffffff-0000-4000-8000-000000000003', '33333333-3333-4333-8333-333333333333', 'quiz',
     'cccccccc-0000-4000-8000-000000000001'),
    ('ffffffff-0000-4000-8000-000000000004', '33333333-3333-4333-8333-333333333333', 'note',
     'bbbbbbbb-0000-4000-8000-000000000003')
$$, 'A shares S1 with B; N1, Q1 and N3 with C');

reset role;
update auth.users set email_confirmed_at = now() where id = '44444444-4444-4444-8444-444444444444';
set local role authenticated;
select results_eq($$ select id from public.find_user_by_email('dave@example.com') $$,
                  $$ values ('44444444-4444-4444-8444-444444444444'::uuid) $$,
                  'find_user_by_email finds a user once confirmed');

-- ============================================================ baseline visibility
set local request.jwt.claims to '{"sub":"22222222-2222-4222-8222-222222222222","role":"authenticated"}';
select is((select count(*)::int from public.notes), 2, 'B sees N1 and N2 via the subject share');
select is((select count(*)::int from public.quizzes), 2, 'B sees Q1 and QN1 via the subject share');
select is((select count(*)::int from storage.objects), 1, 'B reads the image of N1');

set local request.jwt.claims to '{"sub":"33333333-3333-4333-8333-333333333333","role":"authenticated"}';
select is((select count(*)::int from public.notes), 2, 'C sees N1 and N3 via note shares');
select is((select count(*)::int from public.quizzes), 2, 'C sees Q1 (quiz share) and QN1 (note share)');
select is((select count(*)::int from storage.objects), 2, 'C reads the images of N1 and N3');

-- ============================================================ soft-deleted row hidden from recipients
set local request.jwt.claims to '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}';
update public.notes set deleted_at = now() where id = 'bbbbbbbb-0000-4000-8000-000000000002';
select isnt((select deleted_at from public.notes where id = 'bbbbbbbb-0000-4000-8000-000000000002'), null,
            'owner still sees own tombstone');
set local request.jwt.claims to '{"sub":"22222222-2222-4222-8222-222222222222","role":"authenticated"}';
select is((select array_agg(id)::text from public.notes), '{bbbbbbbb-0000-4000-8000-000000000001}',
          'recipient no longer sees the soft-deleted note');
select is(public.can_read_note('bbbbbbbb-0000-4000-8000-000000000002'), false,
          'can_read_note is false for a recipient on a soft-deleted note');

-- ============================================================ soft-deleted parent hides children
set local request.jwt.claims to '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}';
update public.subjects set deleted_at = now() where id = 'aaaaaaaa-0000-4000-8000-000000000002';
reset role;
select is((select count(*)::int from public.shares where id = 'ffffffff-0000-4000-8000-000000000004'), 1,
          'share on N3 survives soft-deleting its subject (only S2''s own shares are removed)');
set local role authenticated;
set local request.jwt.claims to '{"sub":"33333333-3333-4333-8333-333333333333","role":"authenticated"}';
select is((select count(*)::int from public.notes where id = 'bbbbbbbb-0000-4000-8000-000000000003'), 0,
          'note shared directly is hidden once its subject is soft-deleted');
select is((select count(*)::int from storage.objects
           where name like '11111111-1111-4111-8111-111111111111/bbbbbbbb-0000-4000-8000-000000000003/%'), 0,
          'its images are no longer readable by the recipient');

set local request.jwt.claims to '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}';
select is((select count(*)::int from public.notes where id = 'bbbbbbbb-0000-4000-8000-000000000003'), 1,
          'owner still sees a note under a soft-deleted subject');
select throws_ok($$
  insert into public.shares (recipient_id, resource_type, resource_id) values
    ('22222222-2222-4222-8222-222222222222', 'note', 'bbbbbbbb-0000-4000-8000-000000000003')
$$, '42501', null, 'cannot share a note whose subject is soft-deleted');
select throws_ok($$
  select public.copy_note('bbbbbbbb-0000-4000-8000-000000000003', 'aaaaaaaa-0000-4000-8000-000000000003')
$$, 'P0002', null, 'copy_note refuses a note under a soft-deleted subject (even for the owner)');
select throws_ok($$
  select public.copy_note('bbbbbbbb-0000-4000-8000-000000000002', 'aaaaaaaa-0000-4000-8000-000000000003')
$$, 'P0002', null, 'copy_note refuses a soft-deleted note (even for the owner)');

-- ============================================================ soft delete removes shares
update public.quizzes set deleted_at = now() where id = 'cccccccc-0000-4000-8000-000000000001';
update public.notes set deleted_at = now() where id = 'bbbbbbbb-0000-4000-8000-000000000001';
reset role;
select is((select count(*)::int from public.shares where id = 'ffffffff-0000-4000-8000-000000000003'), 0,
          'soft-deleting a quiz deletes its shares');
select is((select count(*)::int from public.shares where id = 'ffffffff-0000-4000-8000-000000000002'), 0,
          'soft-deleting a note deletes its shares');
select is((select count(*)::int from public.shares where id = 'ffffffff-0000-4000-8000-000000000001'), 1,
          'the parent subject''s share is untouched');

set local role authenticated;
set local request.jwt.claims to '{"sub":"22222222-2222-4222-8222-222222222222","role":"authenticated"}';
select is((select count(*)::int from public.notes), 0, 'B: soft-deleted N1 is hidden');
select is((select count(*)::int from public.quizzes where id = 'cccccccc-0000-4000-8000-000000000001'), 0,
          'B: soft-deleted Q1 is hidden');
select is((select count(*)::int from public.quizzes where id = 'cccccccc-0000-4000-8000-000000000002'), 0,
          'B: live QN1 is hidden because its note is soft-deleted');
select is(public.can_read_quiz('cccccccc-0000-4000-8000-000000000002'), false,
          'can_read_quiz is false under a soft-deleted note');
select is((select count(*)::int from storage.objects), 0, 'B: images of the soft-deleted note are unreadable');
select throws_ok($$
  insert into public.quiz_attempts (quiz_id, total) values ('cccccccc-0000-4000-8000-000000000001', 1)
$$, '42501', null, 'B cannot record an attempt on a soft-deleted quiz');
select is((select count(*)::int from public.subjects), 1, 'B still sees the live shared subject');

set local request.jwt.claims to '{"sub":"33333333-3333-4333-8333-333333333333","role":"authenticated"}';
select is((select count(*)::int from public.shares), 1, 'C keeps only the dormant share on N3');
select is((select count(*)::int from public.quizzes), 0, 'C sees no quizzes any more');

set local request.jwt.claims to '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}';
select is((select count(*)::int from public.notes where deleted_at is not null), 2,
          'owner sees both note tombstones');
select is((select count(*)::int from storage.objects), 2, 'owner still reads own images');
select throws_ok($$
  select public.copy_quiz('cccccccc-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-000000000003')
$$, 'P0002', null, 'copy_quiz refuses a soft-deleted quiz');
select throws_ok($$
  select public.copy_quiz('cccccccc-0000-4000-8000-000000000002', 'aaaaaaaa-0000-4000-8000-000000000003')
$$, 'P0002', null, 'copy_quiz refuses a quiz whose note is soft-deleted');
select lives_ok($$
  update public.notes set deleted_at = now() where id = 'bbbbbbbb-0000-4000-8000-000000000001'
$$, 're-deleting an already deleted row is fine');

-- Restoring does not bring the removed shares back.
update public.notes set deleted_at = null where id = 'bbbbbbbb-0000-4000-8000-000000000001';
set local request.jwt.claims to '{"sub":"33333333-3333-4333-8333-333333333333","role":"authenticated"}';
select is((select count(*)::int from public.notes where id = 'bbbbbbbb-0000-4000-8000-000000000001'), 0,
          'restored note stays hidden from C (its note share was removed)');
set local request.jwt.claims to '{"sub":"22222222-2222-4222-8222-222222222222","role":"authenticated"}';
select is((select count(*)::int from public.notes where id = 'bbbbbbbb-0000-4000-8000-000000000001'), 1,
          'restored note is visible again through the live subject share');

-- ============================================================ soft-deleting the shared subject
set local request.jwt.claims to '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}';
update public.subjects set deleted_at = now() where id = 'aaaaaaaa-0000-4000-8000-000000000001';
select throws_ok($$ select public.copy_subject('aaaaaaaa-0000-4000-8000-000000000001') $$,
                 'P0002', null, 'copy_subject refuses a soft-deleted subject');
reset role;
select is((select count(*)::int from public.shares where id = 'ffffffff-0000-4000-8000-000000000001'), 0,
          'soft-deleting a subject deletes its shares');
set local role authenticated;
set local request.jwt.claims to '{"sub":"22222222-2222-4222-8222-222222222222","role":"authenticated"}';
select is((select count(*)::int from public.subjects), 0, 'B no longer sees the subject');
select is((select count(*)::int from public.notes), 0, 'B no longer sees its notes');
select is((select count(*)::int from public.profiles where id = '11111111-1111-4111-8111-111111111111'), 0,
          'B no longer sees A''s profile (no shares left between them)');
reset role;

select * from finish();
rollback;
