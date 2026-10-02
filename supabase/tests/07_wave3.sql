-- Wave 3 tests (migration 20261006000000_wave3.sql):
--   * organization columns: defaults, tags validation, GIN indexes, owner-only
--     writes, recipients see the owner's values, archived subjects stay
--     shared,
--   * chats / chat_messages: private per user (subject-share recipients
--     never see the owner's chats), insert gated by scope readability
--     (subject / note / attachment / general), constraints, immutable keys,
--     server updated_at, revocation keeps own chats, cascade on hard delete,
--   * copy_subject / copy_note / copy_quiz / copy_deck copy tags (not
--     pinned / archived_at).
begin;
create extension if not exists pgtap with schema extensions;
select plan(91);

-- A = alice (owner), B = bob (subject share on S1), C = carol (note share on N1), D = dave (stranger)
insert into auth.users (id, email, raw_user_meta_data, email_confirmed_at) values
  ('11111111-1111-4111-8111-111111111111', 'alice@example.com', '{}', now()),
  ('22222222-2222-4222-8222-222222222222', 'bob@example.com',   '{}', now()),
  ('33333333-3333-4333-8333-333333333333', 'carol@example.com', '{}', now()),
  ('44444444-4444-4444-8444-444444444444', 'dave@example.com',  '{}', now());

select has_table('public', 'chats', 'table chats exists');
select has_table('public', 'chat_messages', 'table chat_messages exists');
select ok((select bool_and(relrowsecurity) from pg_class
           where oid in ('public.chats'::regclass, 'public.chat_messages'::regclass)),
          'RLS is enabled on chats and chat_messages');
select has_index('public', 'notes',   'notes_tags_idx',   'GIN index on notes.tags');
select has_index('public', 'quizzes', 'quizzes_tags_idx', 'GIN index on quizzes.tags');
select has_index('public', 'decks',   'decks_tags_idx',   'GIN index on decks.tags');

reset role;
create temp table copied (kind text primary key, id uuid);
grant all on copied to authenticated;

-- Fixture owned by A:
--   S1 { N1 { QN, DKN }, Q1, DK1, AT1, AT2 }   S2 { N2, AT3 }
set local role authenticated;
set local request.jwt.claims to '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}';
insert into public.subjects (id, title) values
  ('aaaaaaaa-0000-4000-8000-000000000001', 'S1'),
  ('aaaaaaaa-0000-4000-8000-000000000002', 'S2');
insert into public.notes (id, subject_id, title) values
  ('bbbbbbbb-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-000000000001', 'N1'),
  ('bbbbbbbb-0000-4000-8000-000000000002', 'aaaaaaaa-0000-4000-8000-000000000002', 'N2');
insert into public.quizzes (id, subject_id, note_id, title) values
  ('cccccccc-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-000000000001', null, 'Q1'),
  ('cccccccc-0000-4000-8000-000000000002', 'aaaaaaaa-0000-4000-8000-000000000001',
   'bbbbbbbb-0000-4000-8000-000000000001', 'QN');
insert into public.decks (id, subject_id, note_id, title) values
  ('dddddddd-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-000000000001', null, 'DK1'),
  ('dddddddd-0000-4000-8000-000000000002', 'aaaaaaaa-0000-4000-8000-000000000001',
   'bbbbbbbb-0000-4000-8000-000000000001', 'DKN');
insert into public.attachments (id, subject_id, name, kind, storage_path) values
  ('a7a7a7a7-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-000000000001', 'one.pdf', 'pdf',
   '11111111-1111-4111-8111-111111111111/aaaaaaaa-0000-4000-8000-000000000001/a7a7a7a7-0000-4000-8000-000000000001/one.pdf'),
  ('a7a7a7a7-0000-4000-8000-000000000002', 'aaaaaaaa-0000-4000-8000-000000000001', 'two.pdf', 'pdf',
   '11111111-1111-4111-8111-111111111111/aaaaaaaa-0000-4000-8000-000000000001/a7a7a7a7-0000-4000-8000-000000000002/two.pdf'),
  ('a7a7a7a7-0000-4000-8000-000000000003', 'aaaaaaaa-0000-4000-8000-000000000002', 'three.pdf', 'pdf',
   '11111111-1111-4111-8111-111111111111/aaaaaaaa-0000-4000-8000-000000000002/a7a7a7a7-0000-4000-8000-000000000003/three.pdf');

-- ============================================================ organization columns
select results_eq($$ select tags, pinned from public.notes where id = 'bbbbbbbb-0000-4000-8000-000000000001' $$,
                  $$ values ('{}'::text[], false) $$, 'notes: tags default {} and pinned default false');
select results_eq($$ select tags, pinned from public.quizzes where id = 'cccccccc-0000-4000-8000-000000000001' $$,
                  $$ values ('{}'::text[], false) $$, 'quizzes: tags default {} and pinned default false');
select results_eq($$ select tags, pinned from public.decks where id = 'dddddddd-0000-4000-8000-000000000001' $$,
                  $$ values ('{}'::text[], false) $$, 'decks: tags default {} and pinned default false');
select results_eq($$ select archived_at, pinned from public.subjects where id = 'aaaaaaaa-0000-4000-8000-000000000001' $$,
                  $$ values (null::timestamptz, false) $$, 'subjects: archived_at null and pinned false by default');

select lives_ok($$
  update public.notes set tags = '{algebra,exam}', pinned = true where id = 'bbbbbbbb-0000-4000-8000-000000000001';
  update public.quizzes set tags = '{quiz-tag}', pinned = true where id in
    ('cccccccc-0000-4000-8000-000000000001', 'cccccccc-0000-4000-8000-000000000002');
  update public.decks set tags = '{deck-tag}', pinned = true where id in
    ('dddddddd-0000-4000-8000-000000000001', 'dddddddd-0000-4000-8000-000000000002');
  update public.subjects set pinned = true, archived_at = '2026-10-01T00:00:00Z'
   where id = 'aaaaaaaa-0000-4000-8000-000000000001';
$$, 'owner sets tags, pinned and archived_at');
select ok((select updated_at > '2020-01-01' from public.subjects where id = 'aaaaaaaa-0000-4000-8000-000000000001'),
          'organization changes go through the server updated_at trigger');
select is((select count(*)::int from public.notes where tags @> '{exam}'), 1, 'tag containment query works');

select throws_ok($$ update public.notes set tags = null where id = 'bbbbbbbb-0000-4000-8000-000000000002' $$,
                 '23502', null, 'tags is not null');
select throws_ok($$ update public.notes set tags = array['ok', null] where id = 'bbbbbbbb-0000-4000-8000-000000000002' $$,
                 '23514', null, 'a tag cannot be null');
select throws_ok($$ update public.quizzes set tags = '{"  "}' where id = 'cccccccc-0000-4000-8000-000000000001' $$,
                 '23514', null, 'a tag cannot be blank');
select throws_ok($$ update public.decks set tags = array[repeat('x', 65)] where id = 'dddddddd-0000-4000-8000-000000000001' $$,
                 '23514', null, 'a tag is at most 64 characters');
select throws_ok($$ update public.notes set tags = (select array_agg('t' || g) from generate_series(1, 51) g)
                    where id = 'bbbbbbbb-0000-4000-8000-000000000002' $$,
                 '23514', null, 'at most 50 tags');
select throws_ok($$ update public.subjects set pinned = null where id = 'aaaaaaaa-0000-4000-8000-000000000002' $$,
                 '23502', null, 'subjects.pinned is not null');

select lives_ok($$
  insert into public.shares (id, recipient_id, resource_type, resource_id) values
    ('ffffffff-0000-4000-8000-000000000001', '22222222-2222-4222-8222-222222222222', 'subject',
     'aaaaaaaa-0000-4000-8000-000000000001'),
    ('ffffffff-0000-4000-8000-000000000002', '33333333-3333-4333-8333-333333333333', 'note',
     'bbbbbbbb-0000-4000-8000-000000000001')
$$, 'A shares the archived S1 with B and N1 with C');

-- B sees the owner's organization values and cannot change them.
set local request.jwt.claims to '{"sub":"22222222-2222-4222-8222-222222222222","role":"authenticated"}';
insert into public.subjects (id, title) values ('aaaaaaaa-0000-4000-8000-00000000000b', 'SB');
insert into public.notes (id, subject_id, title) values
  ('bbbbbbbb-0000-4000-8000-00000000000b', 'aaaaaaaa-0000-4000-8000-00000000000b', 'NB');
select results_eq($$ select pinned, archived_at from public.subjects where id = 'aaaaaaaa-0000-4000-8000-000000000001' $$,
                  $$ values (true, '2026-10-01T00:00:00Z'::timestamptz) $$,
                  'recipient sees the owner''s pinned / archived_at (archived subjects stay shared)');
select results_eq($$ select tags, pinned from public.notes where id = 'bbbbbbbb-0000-4000-8000-000000000001' $$,
                  $$ values ('{algebra,exam}'::text[], true) $$, 'recipient sees the owner''s note tags / pinned');
update public.subjects set pinned = false, archived_at = null where id = 'aaaaaaaa-0000-4000-8000-000000000001';
update public.notes set pinned = false, tags = '{}' where id = 'bbbbbbbb-0000-4000-8000-000000000001';
update public.quizzes set pinned = false where id = 'cccccccc-0000-4000-8000-000000000001';
update public.decks set pinned = false where id = 'dddddddd-0000-4000-8000-000000000001';
reset role;
select results_eq(
  $$ select (select pinned and archived_at is not null from public.subjects where id = 'aaaaaaaa-0000-4000-8000-000000000001'),
            (select pinned and tags = '{algebra,exam}' from public.notes where id = 'bbbbbbbb-0000-4000-8000-000000000001'),
            (select pinned from public.quizzes where id = 'cccccccc-0000-4000-8000-000000000001'),
            (select pinned from public.decks where id = 'dddddddd-0000-4000-8000-000000000001') $$,
  $$ values (true, true, true, true) $$,
  'recipient pin/archive/tag updates are silent no-ops');
set local role authenticated;

-- ============================================================ chats: owner
set local request.jwt.claims to '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}';
select lives_ok($$
  insert into public.chats (id, scope_type, scope_id, title, provider, model, updated_at) values
    ('c4a70000-0000-4000-8000-0000000000a1', 'subject', 'aaaaaaaa-0000-4000-8000-000000000001', 'A on S1',
     'openai', 'gpt-x', '2000-01-01'),
    ('c4a70000-0000-4000-8000-0000000000a2', 'note', 'bbbbbbbb-0000-4000-8000-000000000001', 'A on N1', null, null, default),
    ('c4a70000-0000-4000-8000-0000000000a3', 'attachment', 'a7a7a7a7-0000-4000-8000-000000000001', 'A on AT1', null, null, default)
$$, 'owner creates subject / note / attachment chats');
select lives_ok($$ insert into public.chats (id) values ('c4a70000-0000-4000-8000-0000000000a4') $$,
                'a chat with no scope is a general chat');
select results_eq($$ select owner_id, scope_type, scope_id, title, provider, model, deleted_at
                     from public.chats where id = 'c4a70000-0000-4000-8000-0000000000a4' $$,
                  $$ values ('11111111-1111-4111-8111-111111111111'::uuid, 'general'::text, null::uuid, ''::text,
                             null::text, null::text, null::timestamptz) $$,
                  'chats defaults (owner = auth.uid(), general, empty title)');
select ok((select updated_at > '2020-01-01' from public.chats where id = 'c4a70000-0000-4000-8000-0000000000a1'),
          'chats.updated_at is server time');

-- Malformed scopes fail the RLS insert check first (42501 through the API);
-- the CHECK constraints (23514) back it up for privileged writers.
select throws_ok($$ insert into public.chats (scope_type, scope_id) values
                    ('general', 'aaaaaaaa-0000-4000-8000-000000000001') $$,
                 '42501', null, 'API: a general chat with a scope_id is rejected');
select throws_ok($$ insert into public.chats (scope_type) values ('subject') $$,
                 '42501', null, 'API: a scoped chat without scope_id is rejected');
select throws_ok($$ insert into public.chats (scope_type, scope_id) values
                    ('quiz', 'cccccccc-0000-4000-8000-000000000001') $$,
                 '42501', null, 'API: an unknown scope_type is rejected');
reset role;
select throws_ok($$ insert into public.chats (owner_id, scope_type, scope_id) values
                    ('11111111-1111-4111-8111-111111111111', 'general', 'aaaaaaaa-0000-4000-8000-000000000001') $$,
                 '23514', null, 'CHECK: a general chat has no scope_id');
select throws_ok($$ insert into public.chats (owner_id, scope_type) values
                    ('11111111-1111-4111-8111-111111111111', 'subject') $$,
                 '23514', null, 'CHECK: a scoped chat needs a scope_id');
select throws_ok($$ insert into public.chats (owner_id, scope_type, scope_id) values
                    ('11111111-1111-4111-8111-111111111111', 'quiz', 'cccccccc-0000-4000-8000-000000000001') $$,
                 '23514', null, 'CHECK: scope_type is subject/note/attachment/general');
set local role authenticated;
select throws_ok($$ insert into public.chats (scope_type, scope_id) values
                    ('note', 'bbbbbbbb-0000-4000-8000-0000000000ff') $$,
                 '42501', null, 'a chat on a missing note is rejected');
select throws_ok($$ update public.chats set scope_id = 'aaaaaaaa-0000-4000-8000-000000000002'
                    where id = 'c4a70000-0000-4000-8000-0000000000a1' $$,
                 '42501', null, 'chats.scope_id is immutable');
select throws_ok($$ update public.chats set scope_type = 'general', scope_id = null
                    where id = 'c4a70000-0000-4000-8000-0000000000a1' $$,
                 '42501', null, 'chats.scope_type is immutable');
select throws_ok($$ update public.chats set owner_id = '22222222-2222-4222-8222-222222222222'
                    where id = 'c4a70000-0000-4000-8000-0000000000a1' $$,
                 '42501', null, 'chats.owner_id is immutable');
select lives_ok($$ update public.chats set title = 'renamed', model = 'gpt-y'
                   where id = 'c4a70000-0000-4000-8000-0000000000a1' $$,
                'owner renames a chat / changes its model');

-- ============================================================ chat_messages: owner
select lives_ok($$
  insert into public.chat_messages (id, chat_id, role, content, citations, updated_at) values
    ('3e550000-0000-4000-8000-0000000000a1', 'c4a70000-0000-4000-8000-0000000000a1', 'user', 'What is a group?',
     default, '2000-01-01'),
    ('3e550000-0000-4000-8000-0000000000a2', 'c4a70000-0000-4000-8000-0000000000a1', 'assistant', 'A set with...',
     '[{"type":"note","id":"bbbbbbbb-0000-4000-8000-000000000001","title":"N1","snippet":"group"},
       {"type":"attachment","id":"a7a7a7a7-0000-4000-8000-000000000001","title":"one.pdf","snippet":null,"page":3}]',
     default),
    ('3e550000-0000-4000-8000-0000000000a3', 'c4a70000-0000-4000-8000-0000000000a1', 'system', 'Be brief.',
     '[{"type":"subject","id":"aaaaaaaa-0000-4000-8000-000000000001","title":"S1"}]', default)
$$, 'owner adds user / assistant / system messages with citations');
select results_eq($$ select owner_id, citations, deleted_at from public.chat_messages
                     where id = '3e550000-0000-4000-8000-0000000000a1' $$,
                  $$ values ('11111111-1111-4111-8111-111111111111'::uuid, '[]'::jsonb, null::timestamptz) $$,
                  'chat_messages defaults (owner = auth.uid(), citations [])');
select ok((select updated_at > '2020-01-01' from public.chat_messages where id = '3e550000-0000-4000-8000-0000000000a1'),
          'chat_messages.updated_at is server time');
select throws_ok($$ insert into public.chat_messages (chat_id, role) values
                    ('c4a70000-0000-4000-8000-0000000000a1', 'tool') $$,
                 '23514', null, 'role is user/assistant/system');
select throws_ok($$ insert into public.chat_messages (chat_id, role, citations) values
                    ('c4a70000-0000-4000-8000-0000000000a1', 'assistant', '{}') $$,
                 '23514', null, 'citations must be an array');
select throws_ok($$ insert into public.chat_messages (chat_id, role, citations) values
                    ('c4a70000-0000-4000-8000-0000000000a1', 'assistant', '[{"type":"note","id":"x"}]') $$,
                 '23514', null, 'a citation needs a title');
select throws_ok($$ insert into public.chat_messages (chat_id, role, citations) values
                    ('c4a70000-0000-4000-8000-0000000000a1', 'assistant',
                     '[{"type":"note","id":"x","title":"t","snippet":5}]') $$,
                 '23514', null, 'a citation snippet is a string or null');
select throws_ok($$ insert into public.chat_messages (chat_id, role, citations) values
                    ('c4a70000-0000-4000-8000-0000000000a1', 'assistant', '[{"type":"","id":"x","title":"t"}]') $$,
                 '23514', null, 'a citation type is not empty');
select throws_ok($$ insert into public.chat_messages (chat_id, role) values
                    ('c4a70000-0000-4000-8000-0000000000ff', 'user') $$,
                 '23503', null, 'a message needs an existing chat');
select throws_ok($$ update public.chat_messages set chat_id = 'c4a70000-0000-4000-8000-0000000000a2'
                    where id = '3e550000-0000-4000-8000-0000000000a1' $$,
                 '42501', null, 'chat_messages.chat_id is immutable');
select throws_ok($$ update public.chat_messages set owner_id = '22222222-2222-4222-8222-222222222222'
                    where id = '3e550000-0000-4000-8000-0000000000a1' $$,
                 '42501', null, 'chat_messages.owner_id is immutable');

-- ============================================================ chats: subject-share recipient B
set local request.jwt.claims to '{"sub":"22222222-2222-4222-8222-222222222222","role":"authenticated"}';
select ok(public.can_read_subject('aaaaaaaa-0000-4000-8000-000000000001'), 'B can read S1 (shared)');
select is((select count(*)::int from public.chats), 0,
          'B (recipient of S1) does not see the owner''s chats on S1');
select is((select count(*)::int from public.chat_messages), 0, 'B does not see the owner''s chat messages');
select lives_ok($$
  insert into public.chats (id, scope_type, scope_id) values
    ('c4a70000-0000-4000-8000-0000000000b1', 'subject', 'aaaaaaaa-0000-4000-8000-000000000001'),
    ('c4a70000-0000-4000-8000-0000000000b2', 'note', 'bbbbbbbb-0000-4000-8000-000000000001'),
    ('c4a70000-0000-4000-8000-0000000000b3', 'attachment', 'a7a7a7a7-0000-4000-8000-000000000001')
$$, 'B can chat with the shared subject, a note in it and its attachment');
select lives_ok($$
  insert into public.chat_messages (id, chat_id, role, content) values
    ('3e550000-0000-4000-8000-0000000000b1', 'c4a70000-0000-4000-8000-0000000000b1', 'user', 'hi')
$$, 'B adds a message to its own chat');
select throws_ok($$ insert into public.chats (scope_type, scope_id) values
                    ('subject', 'aaaaaaaa-0000-4000-8000-000000000002') $$,
                 '42501', null, 'B cannot chat with an unshared subject');
select throws_ok($$ insert into public.chats (scope_type, scope_id) values
                    ('note', 'bbbbbbbb-0000-4000-8000-000000000002') $$,
                 '42501', null, 'B cannot chat with an unshared note');
select throws_ok($$ insert into public.chats (scope_type, scope_id) values
                    ('attachment', 'a7a7a7a7-0000-4000-8000-000000000003') $$,
                 '42501', null, 'B cannot chat with an attachment of an unshared subject');
select throws_ok($$ insert into public.chats (owner_id, scope_type) values
                    ('11111111-1111-4111-8111-111111111111', 'general') $$,
                 '42501', null, 'B cannot create a chat for someone else');
select throws_ok($$ insert into public.chat_messages (chat_id, role, content) values
                    ('c4a70000-0000-4000-8000-0000000000a1', 'user', 'sneaky') $$,
                 '42501', null, 'B cannot add a message to the owner''s chat');
select throws_ok($$ insert into public.chat_messages (chat_id, owner_id, role) values
                    ('c4a70000-0000-4000-8000-0000000000a1', '11111111-1111-4111-8111-111111111111', 'user') $$,
                 '42501', null, 'B cannot insert a message as the owner');
update public.chats set title = 'hacked' where id = 'c4a70000-0000-4000-8000-0000000000a1';
delete from public.chats where id = 'c4a70000-0000-4000-8000-0000000000a1';
update public.chat_messages set content = 'hacked' where id = '3e550000-0000-4000-8000-0000000000a1';
delete from public.chat_messages where id = '3e550000-0000-4000-8000-0000000000a2';

set local request.jwt.claims to '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}';
select results_eq($$ select (select title from public.chats where id = 'c4a70000-0000-4000-8000-0000000000a1'),
                            (select content from public.chat_messages where id = '3e550000-0000-4000-8000-0000000000a1'),
                            (select count(*)::int from public.chat_messages where chat_id = 'c4a70000-0000-4000-8000-0000000000a1') $$,
                  $$ values ('renamed'::text, 'What is a group?'::text, 3) $$,
                  'B''s update/delete of the owner''s chat and messages are no-ops');
select results_eq($$ select id from public.chats order by id $$,
                  $$ values ('c4a70000-0000-4000-8000-0000000000a1'::uuid), ('c4a70000-0000-4000-8000-0000000000a2'::uuid),
                            ('c4a70000-0000-4000-8000-0000000000a3'::uuid), ('c4a70000-0000-4000-8000-0000000000a4'::uuid) $$,
                  'the subject owner does not see the recipient''s chats');
select is((select count(*)::int from public.chat_messages where owner_id <> auth.uid()), 0,
          'the subject owner does not see the recipient''s messages');

-- ============================================================ chats: note-share recipient C, stranger D
set local request.jwt.claims to '{"sub":"33333333-3333-4333-8333-333333333333","role":"authenticated"}';
insert into public.subjects (id, title) values ('aaaaaaaa-0000-4000-8000-00000000000c', 'SC');
select lives_ok($$ insert into public.chats (id, scope_type, scope_id) values
                   ('c4a70000-0000-4000-8000-0000000000c1', 'note', 'bbbbbbbb-0000-4000-8000-000000000001') $$,
                'C can chat with the note shared directly');
select throws_ok($$ insert into public.chats (scope_type, scope_id) values
                    ('subject', 'aaaaaaaa-0000-4000-8000-000000000001') $$,
                 '42501', null, 'C (note share only) cannot chat with the note''s subject');
select throws_ok($$ insert into public.chats (scope_type, scope_id) values
                    ('attachment', 'a7a7a7a7-0000-4000-8000-000000000001') $$,
                 '42501', null, 'C (note share only) cannot chat with the subject''s attachments');
select is((select count(*)::int from public.chats), 1, 'C sees only its own chat');

set local request.jwt.claims to '{"sub":"44444444-4444-4444-8444-444444444444","role":"authenticated"}';
select is((select count(*)::int from public.chats) + (select count(*)::int from public.chat_messages), 0,
          'a stranger sees no chats or messages');
select throws_ok($$ insert into public.chats (scope_type, scope_id) values
                    ('subject', 'aaaaaaaa-0000-4000-8000-000000000001') $$,
                 '42501', null, 'a stranger cannot chat with A''s subject');
select throws_ok($$ insert into public.chats (scope_type, scope_id) values
                    ('note', 'bbbbbbbb-0000-4000-8000-000000000001') $$,
                 '42501', null, 'a stranger cannot chat with A''s note');
select throws_ok($$ insert into public.chats (scope_type, scope_id) values
                    ('attachment', 'a7a7a7a7-0000-4000-8000-000000000001') $$,
                 '42501', null, 'a stranger cannot chat with A''s attachment');
select lives_ok($$ insert into public.chats (scope_type, title) values ('general', 'my own') $$,
                'anyone can create a general chat');

set local role anon;
select throws_ok($$ select count(*) from public.chats $$, '42501', null, 'anon has no access to chats');
select throws_ok($$ select count(*) from public.chat_messages $$, '42501', null, 'anon has no access to chat_messages');
set local role authenticated;

-- ============================================================ soft-deleted scopes
set local request.jwt.claims to '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}';
update public.attachments set deleted_at = now() where id = 'a7a7a7a7-0000-4000-8000-000000000002';
select lives_ok($$ insert into public.chats (scope_type, scope_id) values
                   ('attachment', 'a7a7a7a7-0000-4000-8000-000000000002') $$,
                'the owner may still create a chat on its own trashed attachment (offline sync)');
set local request.jwt.claims to '{"sub":"22222222-2222-4222-8222-222222222222","role":"authenticated"}';
select throws_ok($$ insert into public.chats (scope_type, scope_id) values
                    ('attachment', 'a7a7a7a7-0000-4000-8000-000000000002') $$,
                 '42501', null, 'a recipient cannot chat with a soft-deleted attachment');

-- ============================================================ copies keep tags
-- (still B, before revocation)
select lives_ok($$
  insert into copied values ('subject', public.copy_subject('aaaaaaaa-0000-4000-8000-000000000001'))
$$, 'B copies the shared subject');
select results_eq($$ select pinned, archived_at from public.subjects where id = (select id from copied where kind = 'subject') $$,
                  $$ values (false, null::timestamptz) $$, 'copy_subject does not copy pinned / archived_at');
select results_eq(
  $$ select 'note' as k, title, tags, pinned from public.notes where subject_id = (select id from copied where kind = 'subject')
     union all
     select 'quiz', title, tags, pinned from public.quizzes where subject_id = (select id from copied where kind = 'subject')
     union all
     select 'deck', title, tags, pinned from public.decks where subject_id = (select id from copied where kind = 'subject')
     order by 1, 2 $$,
  $$ values ('deck'::text, 'DK1'::text, '{deck-tag}'::text[], false), ('deck', 'DKN', '{deck-tag}', false),
            ('note', 'N1', '{algebra,exam}', false),
            ('quiz', 'Q1', '{quiz-tag}', false), ('quiz', 'QN', '{quiz-tag}', false) $$,
  'copy_subject copies tags of notes, quizzes and decks (not pinned)');
select lives_ok($$
  insert into copied values
    ('quiz', public.copy_quiz('cccccccc-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-00000000000b')),
    ('deck', public.copy_deck('dddddddd-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-00000000000b',
                              'bbbbbbbb-0000-4000-8000-00000000000b'))
$$, 'B copies a quiz and a deck');
select results_eq(
  $$ select (select tags from public.quizzes where id = (select id from copied where kind = 'quiz')),
            (select pinned from public.quizzes where id = (select id from copied where kind = 'quiz')),
            (select tags from public.decks where id = (select id from copied where kind = 'deck')),
            (select pinned from public.decks where id = (select id from copied where kind = 'deck')) $$,
  $$ values ('{quiz-tag}'::text[], false, '{deck-tag}'::text[], false) $$,
  'copy_quiz / copy_deck copy tags, not pinned');

set local request.jwt.claims to '{"sub":"33333333-3333-4333-8333-333333333333","role":"authenticated"}';
select lives_ok($$
  insert into copied values ('note', public.copy_note('bbbbbbbb-0000-4000-8000-000000000001',
                                                      'aaaaaaaa-0000-4000-8000-00000000000c'))
$$, 'C copies the shared note');
select results_eq(
  $$ select 'note' as k, tags, pinned from public.notes where id = (select id from copied where kind = 'note')
     union all
     select 'quiz', tags, pinned from public.quizzes where note_id = (select id from copied where kind = 'note')
     union all
     select 'deck', tags, pinned from public.decks where note_id = (select id from copied where kind = 'note')
     order by 1 $$,
  $$ values ('deck'::text, '{deck-tag}'::text[], false), ('note', '{algebra,exam}', false),
            ('quiz', '{quiz-tag}', false) $$,
  'copy_note copies tags of the note and its quizzes / decks (not pinned)');

-- ============================================================ revocation and deletion
set local request.jwt.claims to '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}';
delete from public.shares where id = 'ffffffff-0000-4000-8000-000000000001';
set local request.jwt.claims to '{"sub":"22222222-2222-4222-8222-222222222222","role":"authenticated"}';
select is((select count(*)::int from public.chats where scope_type <> 'general'), 3,
          'after revocation B keeps its own chats on A''s content');
select lives_ok($$ insert into public.chat_messages (chat_id, role, content) values
                   ('c4a70000-0000-4000-8000-0000000000b1', 'user', 'still mine') $$,
                'B can keep writing in its own existing chat');
select throws_ok($$ insert into public.chats (scope_type, scope_id) values
                    ('subject', 'aaaaaaaa-0000-4000-8000-000000000001') $$,
                 '42501', null, 'B cannot start a new chat on the revoked subject');
select lives_ok($$ update public.chats set deleted_at = now() where id = 'c4a70000-0000-4000-8000-0000000000b2' $$,
                'B soft-deletes its chat');
select is((select count(*)::int from public.chats where deleted_at is not null), 1, 'owner sees its own chat tombstone');
delete from public.chats where id = 'c4a70000-0000-4000-8000-0000000000b1';
reset role;
select is((select count(*)::int from public.chat_messages where chat_id = 'c4a70000-0000-4000-8000-0000000000b1'), 0,
          'hard-deleting a chat cascades to its messages');
select is((select count(*)::int from public.chats where id = 'c4a70000-0000-4000-8000-0000000000a1'), 1,
          'the owner''s chats are untouched');

-- Hard-deleting a scope keeps the chat (private history, scope_id dangles).
delete from public.subjects where id = 'aaaaaaaa-0000-4000-8000-000000000001';
select is((select count(*)::int from public.chats where id = 'c4a70000-0000-4000-8000-0000000000a1'), 1,
          'hard-deleting the scope keeps the chat');

select * from finish();
rollback;
