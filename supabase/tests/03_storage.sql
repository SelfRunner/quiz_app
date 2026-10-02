-- Storage policy tests for bucket `note-images` (path {owner}/{note}/{file}).
-- Rows are inserted into storage.objects directly to exercise the policies;
-- the Storage API evaluates the same policies.
begin;
create extension if not exists pgtap with schema extensions;
select plan(16);

insert into auth.users (id, email, raw_user_meta_data, email_confirmed_at) values
  ('11111111-1111-4111-8111-111111111111', 'alice@example.com', '{}', now()),
  ('22222222-2222-4222-8222-222222222222', 'bob@example.com',   '{}', now()),
  ('33333333-3333-4333-8333-333333333333', 'carol@example.com', '{}', now());

select results_eq($$ select public from storage.buckets where id = 'note-images' $$,
                  $$ values (false) $$, 'bucket note-images exists and is private');

set local role authenticated;
set local request.jwt.claims to '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}';
insert into public.subjects (id, title) values ('aaaaaaaa-0000-4000-8000-000000000001', 'Bio');
insert into public.notes (id, subject_id, title) values
  ('bbbbbbbb-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-000000000001', 'N1'),
  ('bbbbbbbb-0000-4000-8000-000000000002', 'aaaaaaaa-0000-4000-8000-000000000001', 'N2');

select lives_ok($$
  insert into storage.objects (bucket_id, name) values
    ('note-images', '11111111-1111-4111-8111-111111111111/bbbbbbbb-0000-4000-8000-000000000001/a.png'),
    ('note-images', '11111111-1111-4111-8111-111111111111/bbbbbbbb-0000-4000-8000-000000000002/b.png'),
    ('note-images', '11111111-1111-4111-8111-111111111111/not-a-uuid/c.png'),
    ('note-images', '11111111-1111-4111-8111-111111111111/d.png')
$$, 'owner uploads into own folder');
select throws_ok($$
  insert into storage.objects (bucket_id, name)
  values ('note-images', '22222222-2222-4222-8222-222222222222/bbbbbbbb-0000-4000-8000-000000000001/x.png')
$$, '42501', null, 'cannot upload into another user''s folder');
select throws_ok($$
  insert into storage.objects (bucket_id, name) values ('note-images', 'x.png')
$$, '42501', null, 'cannot upload at the bucket root');
select is((select count(*)::int from storage.objects), 4, 'owner reads own objects');

-- Share only N1 with B (note share).
insert into public.shares (recipient_id, resource_type, resource_id)
values ('22222222-2222-4222-8222-222222222222', 'note', 'bbbbbbbb-0000-4000-8000-000000000001');

set local request.jwt.claims to '{"sub":"22222222-2222-4222-8222-222222222222","role":"authenticated"}';
select results_eq($$ select name from storage.objects $$,
  $$ values ('11111111-1111-4111-8111-111111111111/bbbbbbbb-0000-4000-8000-000000000001/a.png'::text) $$,
  'recipient reads images of the shared note only (malformed paths ignored, no error)');
-- B plants a file in B's own folder under A's note id.
select lives_ok($$
  insert into storage.objects (bucket_id, name)
  values ('note-images', '22222222-2222-4222-8222-222222222222/bbbbbbbb-0000-4000-8000-000000000001/planted.png')
$$, 'B may upload into B''s own folder');

do $$
begin
  update storage.objects set metadata = '{"hacked":true}'
  where name like '11111111-1111-4111-8111-111111111111/%';
  delete from storage.objects where name like '11111111-1111-4111-8111-111111111111/%';
exception when others then null;
end;
$$;

set local request.jwt.claims to '{"sub":"33333333-3333-4333-8333-333333333333","role":"authenticated"}';
select is((select count(*)::int from storage.objects), 0, 'stranger reads nothing');

reset role;
select is((select count(*)::int from storage.objects where name like '11111111-1111-4111-8111-111111111111/%'), 4,
          'recipient could not delete the owner''s objects');
select is((select count(*)::int from storage.objects where metadata is not null), 0,
          'recipient could not update the owner''s objects');

-- Share N1 with C too: C must see A's image but not B's planted file.
set local role authenticated;
set local request.jwt.claims to '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}';
insert into public.shares (recipient_id, resource_type, resource_id)
values ('33333333-3333-4333-8333-333333333333', 'note', 'bbbbbbbb-0000-4000-8000-000000000001');
select is((select count(*)::int from storage.objects where name like '22222222-2222-4222-8222-222222222222/%'), 0,
          'note owner does not see files others put under the note id');
set local request.jwt.claims to '{"sub":"33333333-3333-4333-8333-333333333333","role":"authenticated"}';
select results_eq($$ select name from storage.objects $$,
  $$ values ('11111111-1111-4111-8111-111111111111/bbbbbbbb-0000-4000-8000-000000000001/a.png'::text) $$,
  'path owner segment must match the note owner (planted files are not exposed)');

-- Helper edge cases never raise.
select is(public.can_read_note_object(null), false, 'null path -> false');
select is(public.can_read_note_object('a/b'), false, 'two segments -> false');
select is(public.can_read_note_object('11111111-1111-4111-8111-111111111111/BBBB/../x/y.png'), false,
          'extra segments -> false');
select is(public.can_read_note_object('11111111-1111-4111-8111-111111111111/zzzzzzzz-0000-4000-8000-000000000001/a.png'),
          false, 'non-uuid note segment -> false');
reset role;

select * from finish();
rollback;
