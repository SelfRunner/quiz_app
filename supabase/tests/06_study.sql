-- Study tests (migration 20261005000000_study.sql):
--   * decks: card validation, server updated_at, immutable owner, parent
--     ownership, subject normalized to the note's subject (and follows note
--     moves),
--   * deck visibility for owner / subject-share / note-share / deck-share
--     recipients and strangers; recipients are read-only; share_details,
--   * card_reviews and mistakes: private per user, inserts gated by
--     can_read_deck / can_read_quiz, unique per (owner, parent, item),
--     parent keys immutable,
--   * quiz_attempts exam-mode columns,
--   * soft delete / revoke / hard delete of decks and their shares,
--   * copy_deck, copy_subject and copy_note include decks.
begin;
create extension if not exists pgtap with schema extensions;
select plan(84);

-- A = alice (owner), B = bob (subject share), C = carol (note + deck share), D = dave (stranger)
insert into auth.users (id, email, raw_user_meta_data, email_confirmed_at) values
  ('11111111-1111-4111-8111-111111111111', 'alice@example.com', '{}', now()),
  ('22222222-2222-4222-8222-222222222222', 'bob@example.com',   '{}', now()),
  ('33333333-3333-4333-8333-333333333333', 'carol@example.com', '{}', now()),
  ('44444444-4444-4444-8444-444444444444', 'dave@example.com',  '{}', now());

select ok('deck' = any (enum_range(null::public.share_resource_type)::text[]),
          'share_resource_type has the value deck');

reset role;
create temp table copied (kind text primary key, id uuid);
grant all on copied to authenticated;

-- Fixture owned by A:
--   S1 { N1 { DKN, QN1 }, N2 { DKN2 }, Q1, DK1, DK2 }   S2 { DK3 }
set local role authenticated;
set local request.jwt.claims to '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}';
insert into public.subjects (id, title) values
  ('aaaaaaaa-0000-4000-8000-000000000001', 'S1'),
  ('aaaaaaaa-0000-4000-8000-000000000002', 'S2');
insert into public.notes (id, subject_id, title) values
  ('bbbbbbbb-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-000000000001', 'N1'),
  ('bbbbbbbb-0000-4000-8000-000000000002', 'aaaaaaaa-0000-4000-8000-000000000001', 'N2');
insert into public.quizzes (id, subject_id, note_id, title, questions) values
  ('cccccccc-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-000000000001', null, 'Q1', '[]'),
  ('cccccccc-0000-4000-8000-000000000002', 'aaaaaaaa-0000-4000-8000-000000000001',
   'bbbbbbbb-0000-4000-8000-000000000001', 'QN1', '[]');

-- ============================================================ decks: constraints and triggers
select lives_ok($$
  insert into public.decks (id, subject_id, note_id, title, cards, source, updated_at) values
    ('dddddddd-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-000000000001', null, 'DK1',
     '[{"id":"c1","front":"F1","back":"B1"},{"id":"c2","front":"F2","back":"B2","hint":"H2"}]',
     '{"provider":"openai"}', '2000-01-01'),
    ('dddddddd-0000-4000-8000-000000000002', 'aaaaaaaa-0000-4000-8000-000000000001', null, 'DK2', '[]', null, default),
    ('dddddddd-0000-4000-8000-000000000003', 'aaaaaaaa-0000-4000-8000-000000000002', null, 'DK3',
     '[{"id":"x","front":"f","back":"b","hint":null}]', null, default),
    -- wrong subject on purpose: normalized to N1's subject (S1)
    ('dddddddd-0000-4000-8000-000000000004', 'aaaaaaaa-0000-4000-8000-000000000002',
     'bbbbbbbb-0000-4000-8000-000000000001', 'DKN', '[{"id":"n1","front":"f","back":"b"}]', null, default),
    ('dddddddd-0000-4000-8000-000000000005', 'aaaaaaaa-0000-4000-8000-000000000001',
     'bbbbbbbb-0000-4000-8000-000000000002', 'DKN2', '[]', null, default)
$$, 'A creates decks (subject-level and note-attached)');
select ok((select updated_at > '2020-01-01' from public.decks where id = 'dddddddd-0000-4000-8000-000000000001'),
          'decks.updated_at is server time');
select is((select subject_id from public.decks where id = 'dddddddd-0000-4000-8000-000000000004'),
          'aaaaaaaa-0000-4000-8000-000000000001'::uuid,
          'note deck subject_id is normalized to the note''s subject');
select is((select owner_id from public.decks where id = 'dddddddd-0000-4000-8000-000000000001'),
          '11111111-1111-4111-8111-111111111111'::uuid, 'owner_id defaults to auth.uid()');

select throws_ok($$ update public.decks set cards = '{}' where id = 'dddddddd-0000-4000-8000-000000000002' $$,
                 '23514', null, 'cards must be an array');
select throws_ok($$ update public.decks set cards = '[{"id":"a","front":"f"}]'
                    where id = 'dddddddd-0000-4000-8000-000000000002' $$,
                 '23514', null, 'a card needs front and back');
select throws_ok($$ update public.decks set cards = '[{"id":"a","front":"f","back":"b"},{"id":"a","front":"g","back":"c"}]'
                    where id = 'dddddddd-0000-4000-8000-000000000002' $$,
                 '23514', null, 'card ids are unique within a deck');
select throws_ok($$ update public.decks set cards = '[{"id":"a","front":"f","back":"b","hint":3}]'
                    where id = 'dddddddd-0000-4000-8000-000000000002' $$,
                 '23514', null, 'hint must be a string or null');
select throws_ok($$ update public.decks set cards = '[{"id":"","front":"f","back":"b"}]'
                    where id = 'dddddddd-0000-4000-8000-000000000002' $$,
                 '23514', null, 'card id must not be empty');
select lives_ok($$ update public.decks set cards = '[{"id":"a","front":"f","back":"b","hint":null,"extra":1}]'
                   where id = 'dddddddd-0000-4000-8000-000000000002' $$,
                'extra card keys and a null hint are accepted');
select throws_ok($$ update public.decks set source = '[]' where id = 'dddddddd-0000-4000-8000-000000000002' $$,
                 '23514', null, 'source must be an object');
select throws_ok($$ update public.decks set owner_id = '22222222-2222-4222-8222-222222222222'
                    where id = 'dddddddd-0000-4000-8000-000000000001' $$,
                 '42501', null, 'decks.owner_id is immutable');

-- Moving N2 to S2 moves its deck along.
update public.notes set subject_id = 'aaaaaaaa-0000-4000-8000-000000000002'
 where id = 'bbbbbbbb-0000-4000-8000-000000000002';
select is((select subject_id from public.decks where id = 'dddddddd-0000-4000-8000-000000000005'),
          'aaaaaaaa-0000-4000-8000-000000000002'::uuid, 'a note''s decks follow it to another subject');

-- ============================================================ shares on decks
select lives_ok($$
  insert into public.shares (id, recipient_id, resource_type, resource_id) values
    ('ffffffff-0000-4000-8000-000000000001', '22222222-2222-4222-8222-222222222222', 'subject',
     'aaaaaaaa-0000-4000-8000-000000000001'),
    ('ffffffff-0000-4000-8000-000000000002', '33333333-3333-4333-8333-333333333333', 'note',
     'bbbbbbbb-0000-4000-8000-000000000001'),
    ('ffffffff-0000-4000-8000-000000000003', '33333333-3333-4333-8333-333333333333', 'deck',
     'dddddddd-0000-4000-8000-000000000003')
$$, 'A shares S1 with B, N1 and DK3 with C');

-- B: own subject/note (copy targets) and attempts to touch A's decks
set local request.jwt.claims to '{"sub":"22222222-2222-4222-8222-222222222222","role":"authenticated"}';
insert into public.subjects (id, title) values ('aaaaaaaa-0000-4000-8000-00000000000b', 'SB');
insert into public.notes (id, subject_id, title) values
  ('bbbbbbbb-0000-4000-8000-00000000000b', 'aaaaaaaa-0000-4000-8000-00000000000b', 'NB');
select throws_ok($$
  insert into public.shares (recipient_id, resource_type, resource_id) values
    ('44444444-4444-4444-8444-444444444444', 'deck', 'dddddddd-0000-4000-8000-000000000001')
$$, '42501', null, 'B cannot share A''s deck');
select throws_ok($$
  insert into public.decks (subject_id, title) values ('aaaaaaaa-0000-4000-8000-000000000001', 'evil')
$$, '42501', null, 'B cannot create a deck in A''s subject');
select throws_ok($$
  insert into public.decks (subject_id, note_id, title) values
    ('aaaaaaaa-0000-4000-8000-00000000000b', 'bbbbbbbb-0000-4000-8000-000000000001', 'evil')
$$, '42501', null, 'B cannot attach a deck to A''s note');

-- ============================================================ visibility
select results_eq($$ select title from public.decks order by title $$,
                  $$ values ('DK1'), ('DK2'), ('DKN') $$,
                  'B sees S1''s decks (incl. the note deck) via the subject share');
select is(public.can_read_deck('dddddddd-0000-4000-8000-000000000003'), false,
          'B cannot read DK3 (other subject)');
update public.decks set title = 'hacked' where id = 'dddddddd-0000-4000-8000-000000000001';
delete from public.decks where id = 'dddddddd-0000-4000-8000-000000000001';
select is((select title from public.decks where id = 'dddddddd-0000-4000-8000-000000000001'), 'DK1',
          'recipient update/delete of a shared deck is a no-op');

set local request.jwt.claims to '{"sub":"33333333-3333-4333-8333-333333333333","role":"authenticated"}';
insert into public.subjects (id, title) values ('aaaaaaaa-0000-4000-8000-00000000000c', 'SC');
select results_eq($$ select title from public.decks order by title $$,
                  $$ values ('DK3'), ('DKN') $$,
                  'C sees DK3 (deck share) and DKN (note share)');
select results_eq($$ select resource_title from public.share_details where resource_type::text = 'deck' $$,
                  $$ values ('DK3') $$, 'share_details resolves the deck title');

set local request.jwt.claims to '{"sub":"44444444-4444-4444-8444-444444444444","role":"authenticated"}';
insert into public.subjects (id, title) values ('aaaaaaaa-0000-4000-8000-00000000000d', 'SD');
select is((select count(*)::int from public.decks), 0, 'stranger sees no decks');
select is(public.can_read_deck('dddddddd-0000-4000-8000-000000000001'), false, 'can_read_deck false for a stranger');

-- ============================================================ card_reviews
set local request.jwt.claims to '{"sub":"22222222-2222-4222-8222-222222222222","role":"authenticated"}';
select lives_ok($$
  insert into public.card_reviews (id, deck_id, card_id, state, due_at, stability, difficulty, updated_at) values
    ('eeeeeeee-0000-4000-8000-000000000001', 'dddddddd-0000-4000-8000-000000000001', 'c1', 1,
     now() + interval '1 day', 2.5, 5.0, '2000-01-01')
$$, 'B can review a card of a deck shared through the subject');
select results_eq($$ select owner_id, state, reps, lapses, elapsed_days, scheduled_days, last_review_at
                     from public.card_reviews $$,
                  $$ values ('22222222-2222-4222-8222-222222222222'::uuid, 1::smallint, 0, 0, 0, 0, null::timestamptz) $$,
                  'card_reviews defaults');
select ok((select updated_at > '2020-01-01' from public.card_reviews), 'card_reviews.updated_at is server time');
select throws_ok($$
  insert into public.card_reviews (deck_id, card_id) values ('dddddddd-0000-4000-8000-000000000001', 'c1')
$$, '23505', null, 'one review row per (owner, deck, card)');
select throws_ok($$
  insert into public.card_reviews (deck_id, card_id) values ('dddddddd-0000-4000-8000-000000000003', 'x')
$$, '42501', null, 'B cannot review a deck it cannot read');
select throws_ok($$
  insert into public.card_reviews (deck_id, card_id, state) values ('dddddddd-0000-4000-8000-000000000001', 'c2', 4)
$$, '23514', null, 'state is 0..3');
select throws_ok($$
  insert into public.card_reviews (deck_id, card_id, owner_id) values
    ('dddddddd-0000-4000-8000-000000000001', 'c2', '11111111-1111-4111-8111-111111111111')
$$, '42501', null, 'B cannot insert a review row for someone else');
select lives_ok($$
  update public.card_reviews set state = 2, reps = 1, scheduled_days = 3, last_review_at = now()
   where id = 'eeeeeeee-0000-4000-8000-000000000001'
$$, 'B updates its own review state');
select throws_ok($$
  update public.card_reviews set deck_id = 'dddddddd-0000-4000-8000-000000000002'
   where id = 'eeeeeeee-0000-4000-8000-000000000001'
$$, '42501', null, 'card_reviews.deck_id is immutable');
select throws_ok($$
  update public.card_reviews set card_id = 'c2' where id = 'eeeeeeee-0000-4000-8000-000000000001'
$$, '42501', null, 'card_reviews.card_id is immutable');

set local request.jwt.claims to '{"sub":"33333333-3333-4333-8333-333333333333","role":"authenticated"}';
select lives_ok($$
  insert into public.card_reviews (deck_id, card_id) values
    ('dddddddd-0000-4000-8000-000000000003', 'x'),
    ('dddddddd-0000-4000-8000-000000000004', 'n1')
$$, 'C can review decks shared directly and through a note');
select is((select count(*)::int from public.card_reviews), 2, 'C sees only its own reviews');

set local request.jwt.claims to '{"sub":"44444444-4444-4444-8444-444444444444","role":"authenticated"}';
select throws_ok($$
  insert into public.card_reviews (deck_id, card_id) values ('dddddddd-0000-4000-8000-000000000001', 'c1')
$$, '42501', null, 'stranger cannot review A''s deck');

set local request.jwt.claims to '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}';
select lives_ok($$
  insert into public.card_reviews (deck_id, card_id) values ('dddddddd-0000-4000-8000-000000000001', 'c1')
$$, 'the owner reviews the same card independently');
select is((select count(*)::int from public.card_reviews), 1, 'deck owner does not see recipients'' reviews');
update public.card_reviews set reps = 99 where id = 'eeeeeeee-0000-4000-8000-000000000001';
delete from public.card_reviews where id = 'eeeeeeee-0000-4000-8000-000000000001';
set local request.jwt.claims to '{"sub":"22222222-2222-4222-8222-222222222222","role":"authenticated"}';
select results_eq($$ select state, reps from public.card_reviews $$, $$ values (2::smallint, 1) $$,
                  'B''s review is untouched by the deck owner''s update/delete');

-- ============================================================ mistakes
select lives_ok($$
  insert into public.mistakes (id, quiz_id, question_id, wrong_count, last_wrong_at) values
    ('99999999-0000-4000-8000-000000000001', 'cccccccc-0000-4000-8000-000000000001', 'q1', 1, now())
$$, 'B records a mistake on a quiz shared through the subject');
select results_eq($$ select owner_id, wrong_count, correct_streak, resolved_at from public.mistakes $$,
                  $$ values ('22222222-2222-4222-8222-222222222222'::uuid, 1, 0, null::timestamptz) $$,
                  'mistakes defaults');
select throws_ok($$
  insert into public.mistakes (quiz_id, question_id) values ('cccccccc-0000-4000-8000-000000000001', 'q1')
$$, '23505', null, 'one mistake row per (owner, quiz, question)');
select throws_ok($$
  insert into public.mistakes (quiz_id, question_id, wrong_count) values
    ('cccccccc-0000-4000-8000-000000000001', 'q2', -1)
$$, '23514', null, 'wrong_count >= 0');
select lives_ok($$
  update public.mistakes set correct_streak = 2, resolved_at = now()
   where id = '99999999-0000-4000-8000-000000000001'
$$, 'B updates its own mistake');
select throws_ok($$
  update public.mistakes set question_id = 'q9' where id = '99999999-0000-4000-8000-000000000001'
$$, '42501', null, 'mistakes.question_id is immutable');

set local request.jwt.claims to '{"sub":"33333333-3333-4333-8333-333333333333","role":"authenticated"}';
select throws_ok($$
  insert into public.mistakes (quiz_id, question_id) values ('cccccccc-0000-4000-8000-000000000001', 'q1')
$$, '42501', null, 'C (note share only) cannot record a mistake on a subject-level quiz');
set local request.jwt.claims to '{"sub":"44444444-4444-4444-8444-444444444444","role":"authenticated"}';
select throws_ok($$
  insert into public.mistakes (quiz_id, question_id) values ('cccccccc-0000-4000-8000-000000000001', 'q1')
$$, '42501', null, 'stranger cannot record a mistake on A''s quiz');
set local request.jwt.claims to '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}';
select is((select count(*)::int from public.mistakes), 0, 'quiz owner does not see others'' mistakes');

-- ============================================================ quiz_attempts exam mode
set local request.jwt.claims to '{"sub":"22222222-2222-4222-8222-222222222222","role":"authenticated"}';
select lives_ok($$
  insert into public.quiz_attempts (id, quiz_id, total) values
    ('88888888-0000-4000-8000-000000000001', 'cccccccc-0000-4000-8000-000000000001', 1)
$$, 'an attempt without the new columns still works');
select results_eq($$ select mode, time_limit_seconds, question_ids, duration_seconds
                     from public.quiz_attempts where id = '88888888-0000-4000-8000-000000000001' $$,
                  $$ values ('practice'::text, null::int, null::jsonb, null::int) $$,
                  'new attempt columns default to practice / null');
select lives_ok($$
  insert into public.quiz_attempts (quiz_id, total, mode, time_limit_seconds, question_ids, duration_seconds) values
    ('cccccccc-0000-4000-8000-000000000001', 2, 'exam', 600, '["q1","q2"]', 312),
    ('cccccccc-0000-4000-8000-000000000001', 1, 'mistakes', null, '["q1"]', null)
$$, 'exam and mistakes attempts');
select throws_ok($$
  insert into public.quiz_attempts (quiz_id, mode) values ('cccccccc-0000-4000-8000-000000000001', 'timed')
$$, '23514', null, 'mode is practice/exam/mistakes');
select throws_ok($$
  insert into public.quiz_attempts (quiz_id, question_ids) values ('cccccccc-0000-4000-8000-000000000001', '{"a":1}')
$$, '23514', null, 'question_ids must be an array');
select throws_ok($$
  insert into public.quiz_attempts (quiz_id, time_limit_seconds) values ('cccccccc-0000-4000-8000-000000000001', 0)
$$, '23514', null, 'time_limit_seconds must be positive');
select throws_ok($$
  insert into public.quiz_attempts (quiz_id, duration_seconds) values ('cccccccc-0000-4000-8000-000000000001', -1)
$$, '23514', null, 'duration_seconds must be >= 0');

-- ============================================================ soft delete
set local request.jwt.claims to '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}';
update public.decks set deleted_at = now()
 where id in ('dddddddd-0000-4000-8000-000000000002', 'dddddddd-0000-4000-8000-000000000003');
select is((select count(*)::int from public.decks where deleted_at is not null), 2,
          'owner still sees own deck tombstones');
select throws_ok($$
  insert into public.shares (recipient_id, resource_type, resource_id) values
    ('22222222-2222-4222-8222-222222222222', 'deck', 'dddddddd-0000-4000-8000-000000000003')
$$, '42501', null, 'cannot share a soft-deleted deck');
select throws_ok($$
  select public.copy_deck('dddddddd-0000-4000-8000-000000000003', 'aaaaaaaa-0000-4000-8000-000000000001')
$$, 'P0002', null, 'copy_deck refuses a soft-deleted deck (even for the owner)');
reset role;
select is((select count(*)::int from public.shares where id = 'ffffffff-0000-4000-8000-000000000003'), 0,
          'soft-deleting a deck deletes its shares');
set local role authenticated;

set local request.jwt.claims to '{"sub":"22222222-2222-4222-8222-222222222222","role":"authenticated"}';
select results_eq($$ select title from public.decks order by title $$, $$ values ('DK1'), ('DKN') $$,
                  'B no longer sees the soft-deleted DK2');
set local request.jwt.claims to '{"sub":"33333333-3333-4333-8333-333333333333","role":"authenticated"}';
select results_eq($$ select title from public.decks $$, $$ values ('DKN') $$,
                  'C no longer sees the soft-deleted DK3');

-- ============================================================ copies
set local request.jwt.claims to '{"sub":"22222222-2222-4222-8222-222222222222","role":"authenticated"}';
select lives_ok($$
  insert into copied values
    ('deck', public.copy_deck('dddddddd-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-00000000000b')),
    ('deck_in_note', public.copy_deck('dddddddd-0000-4000-8000-000000000004', 'aaaaaaaa-0000-4000-8000-00000000000b',
                                      'bbbbbbbb-0000-4000-8000-00000000000b'))
$$, 'B copies shared decks into its own subject / note');
select results_eq(
  $$ select d.owner_id, d.subject_id, d.note_id, d.title, d.cards, d.source, d.deleted_at
     from public.decks d where d.id = (select id from copied where kind = 'deck') $$,
  $$ values ('22222222-2222-4222-8222-222222222222'::uuid, 'aaaaaaaa-0000-4000-8000-00000000000b'::uuid,
             null::uuid, 'DK1'::text,
             '[{"id":"c1","front":"F1","back":"B1"},{"id":"c2","front":"F2","back":"B2","hint":"H2"}]'::jsonb,
             '{"provider":"openai"}'::jsonb, null::timestamptz) $$,
  'copy_deck copies title, cards (ids kept) and source to the caller');
select is((select note_id from public.decks where id = (select id from copied where kind = 'deck_in_note')),
          'bbbbbbbb-0000-4000-8000-00000000000b'::uuid, 'copy_deck can target an owned note');
select is((select count(*)::int from public.card_reviews
           where deck_id in (select id from copied)), 0, 'review state is not copied');
select throws_ok($$
  select public.copy_deck('dddddddd-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-000000000001')
$$, '42501', null, 'copy_deck target subject must be owned');
select throws_ok($$
  select public.copy_deck('dddddddd-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-00000000000b',
                          'bbbbbbbb-0000-4000-8000-000000000001')
$$, '42501', null, 'copy_deck target note must be owned');
select throws_ok($$
  select public.copy_deck('dddddddd-0000-4000-8000-000000000003', 'aaaaaaaa-0000-4000-8000-00000000000b')
$$, 'P0002', null, 'copy_deck refuses an unreadable deck');

select lives_ok($$
  insert into copied values ('subject', public.copy_subject('aaaaaaaa-0000-4000-8000-000000000001'))
$$, 'B copies the shared subject');
select results_eq(
  $$ select d.title, n.title, d.owner_id, d.cards
     from public.decks d
     left join public.notes n on n.id = d.note_id
     where d.subject_id = (select id from copied where kind = 'subject')
     order by d.title $$,
  $$ values ('DK1'::text, null::text, '22222222-2222-4222-8222-222222222222'::uuid,
             '[{"id":"c1","front":"F1","back":"B1"},{"id":"c2","front":"F2","back":"B2","hint":"H2"}]'::jsonb),
            ('DKN', 'N1', '22222222-2222-4222-8222-222222222222'::uuid,
             '[{"id":"n1","front":"f","back":"b"}]'::jsonb) $$,
  'copy_subject copies live subject decks and note decks (remapped to the copied note), not deleted ones');

set local request.jwt.claims to '{"sub":"33333333-3333-4333-8333-333333333333","role":"authenticated"}';
select lives_ok($$
  insert into copied values ('note', public.copy_note('bbbbbbbb-0000-4000-8000-000000000001',
                                                      'aaaaaaaa-0000-4000-8000-00000000000c'))
$$, 'C copies the shared note');
select results_eq(
  $$ select title, subject_id, owner_id from public.decks where note_id = (select id from copied where kind = 'note') $$,
  $$ values ('DKN'::text, 'aaaaaaaa-0000-4000-8000-00000000000c'::uuid, '33333333-3333-4333-8333-333333333333'::uuid) $$,
  'copy_note copies the note''s decks');
select lives_ok($$
  select public.copy_quiz('cccccccc-0000-4000-8000-000000000002', 'aaaaaaaa-0000-4000-8000-00000000000c')
$$, 'copy_quiz works for a note-share recipient who cannot see the subject (regression)');

-- ============================================================ deck share, parent soft delete, revoke, hard delete
set local request.jwt.claims to '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}';
insert into public.shares (id, recipient_id, resource_type, resource_id) values
  ('ffffffff-0000-4000-8000-000000000004', '44444444-4444-4444-8444-444444444444', 'deck',
   'dddddddd-0000-4000-8000-000000000001');
set local request.jwt.claims to '{"sub":"44444444-4444-4444-8444-444444444444","role":"authenticated"}';
select results_eq($$ select title from public.decks $$, $$ values ('DK1') $$,
                  'a direct deck share exposes exactly that deck');
select lives_ok($$
  insert into public.card_reviews (deck_id, card_id) values ('dddddddd-0000-4000-8000-000000000001', 'c1')
$$, 'deck-share recipient can review it');
select lives_ok($$
  select public.copy_deck('dddddddd-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-00000000000d')
$$, 'deck-share recipient (subject not visible) can copy the deck');

set local request.jwt.claims to '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}';
update public.notes set deleted_at = now() where id = 'bbbbbbbb-0000-4000-8000-000000000001';
set local request.jwt.claims to '{"sub":"22222222-2222-4222-8222-222222222222","role":"authenticated"}';
select results_eq($$ select title from public.decks where owner_id <> auth.uid() $$, $$ values ('DK1') $$,
                  'a note deck is hidden from recipients once its note is soft-deleted');

set local request.jwt.claims to '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}';
delete from public.shares where id = 'ffffffff-0000-4000-8000-000000000001';
set local request.jwt.claims to '{"sub":"22222222-2222-4222-8222-222222222222","role":"authenticated"}';
select is((select count(*)::int from public.decks where owner_id <> auth.uid()), 0,
          'after revoking the subject share B sees none of A''s decks');
select is((select count(*)::int from public.card_reviews), 1, 'B keeps its own review rows');
select throws_ok($$
  insert into public.card_reviews (deck_id, card_id) values ('dddddddd-0000-4000-8000-000000000001', 'c2')
$$, '42501', null, 'B cannot add reviews after revocation');

set local request.jwt.claims to '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}';
delete from public.decks where id = 'dddddddd-0000-4000-8000-000000000001';
reset role;
select is((select count(*)::int from public.shares where resource_id = 'dddddddd-0000-4000-8000-000000000001'), 0,
          'hard-deleting a deck deletes its shares');
select is((select count(*)::int from public.card_reviews where deck_id = 'dddddddd-0000-4000-8000-000000000001'), 0,
          'hard-deleting a deck cascades to everyone''s review rows');

select * from finish();
rollback;
