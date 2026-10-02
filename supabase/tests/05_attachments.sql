-- Attachments tests (migration 20261004000000_attachments.sql):
--   * table constraints (path shape, kind, extracted_text cap), owner_id /
--     subject_id / storage_path immutability, parent ownership,
--   * RLS: owner CRUD, subject-share recipient read-only, note-only share and
--     strangers see nothing, soft-deleted attachments hidden from recipients,
--   * Storage bucket `attachments` policies,
--   * copy_subject copies live attachments and queues their Storage copies.
begin;
create extension if not exists pgtap with schema extensions;
select plan(73);

-- A = alice (owner), B = bob (subject share), C = carol (note-only share), D = dave (stranger)
insert into auth.users (id, email, raw_user_meta_data, email_confirmed_at) values
  ('11111111-1111-4111-8111-111111111111', 'alice@example.com', '{}', now()),
  ('22222222-2222-4222-8222-222222222222', 'bob@example.com',   '{}', now()),
  ('33333333-3333-4333-8333-333333333333', 'carol@example.com', '{}', now()),
  ('44444444-4444-4444-8444-444444444444', 'dave@example.com',  '{}', now());

select results_eq(
  $$ select public, file_size_limit from storage.buckets where id = 'attachments' $$,
  $$ values (false, 52428800::bigint) $$,
  'bucket attachments exists, is private, 50 MiB limit');

-- Fixture owned by A:
--   S1 { N1 (with image), AT1 pdf, AT2 text, AT3 image }   S2 { AT4 docx }
set local role authenticated;
set local request.jwt.claims to '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}';
insert into public.subjects (id, title) values
  ('aaaaaaaa-0000-4000-8000-000000000001', 'S1'),
  ('aaaaaaaa-0000-4000-8000-000000000002', 'S2');
insert into public.notes (id, subject_id, title, content_md) values
  ('bbbbbbbb-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-000000000001', 'N1',
   '![x](note-image://11111111-1111-4111-8111-111111111111/bbbbbbbb-0000-4000-8000-000000000001/img.png)');

select lives_ok($$
  insert into public.attachments (id, subject_id, name, mime_type, size_bytes, kind, storage_path, extracted_text, updated_at) values
    ('abababab-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-000000000001', 'Lecture 1.pdf',
     'application/pdf', 1000, 'pdf',
     '11111111-1111-4111-8111-111111111111/aaaaaaaa-0000-4000-8000-000000000001/abababab-0000-4000-8000-000000000001/lecture-1.pdf',
     null, '2000-01-01'),
    ('abababab-0000-4000-8000-000000000002', 'aaaaaaaa-0000-4000-8000-000000000001', 'notes.txt',
     'text/plain', 5, 'text',
     '11111111-1111-4111-8111-111111111111/aaaaaaaa-0000-4000-8000-000000000001/abababab-0000-4000-8000-000000000002/notes.txt',
     'hello', '2000-01-01'),
    ('abababab-0000-4000-8000-000000000003', 'aaaaaaaa-0000-4000-8000-000000000001', 'old.png',
     'image/png', 10, 'image',
     '11111111-1111-4111-8111-111111111111/aaaaaaaa-0000-4000-8000-000000000001/abababab-0000-4000-8000-000000000003/old.png',
     null, '2000-01-01'),
    ('abababab-0000-4000-8000-000000000004', 'aaaaaaaa-0000-4000-8000-000000000002', 'essay.docx',
     'application/vnd.openxmlformats-officedocument.wordprocessingml.document', 20, 'docx',
     '11111111-1111-4111-8111-111111111111/aaaaaaaa-0000-4000-8000-000000000002/abababab-0000-4000-8000-000000000004/essay.docx',
     'essay text', '2000-01-01')
$$, 'owner inserts attachments');
select is((select owner_id from public.attachments where id = 'abababab-0000-4000-8000-000000000001'),
          '11111111-1111-4111-8111-111111111111'::uuid, 'owner_id defaults to auth.uid()');
select is((select updated_at from public.attachments where id = 'abababab-0000-4000-8000-000000000001'),
          now(), 'updated_at is set by the server, client value ignored');

-- ============================================================ constraints
select throws_ok($$
  insert into public.attachments (id, subject_id, name, kind, storage_path) values
    ('abababab-0000-4000-8000-0000000000e1', 'aaaaaaaa-0000-4000-8000-000000000001', 'x', 'pdf',
     '11111111-1111-4111-8111-111111111111/aaaaaaaa-0000-4000-8000-000000000001/abababab-0000-4000-8000-0000000000ff/x.pdf')
$$, '23514', null, 'storage_path must contain the attachment id');
select throws_ok($$
  insert into public.attachments (id, subject_id, name, kind, storage_path) values
    ('abababab-0000-4000-8000-0000000000e1', 'aaaaaaaa-0000-4000-8000-000000000001', 'x', 'pdf',
     '11111111-1111-4111-8111-111111111111/aaaaaaaa-0000-4000-8000-000000000002/abababab-0000-4000-8000-0000000000e1/x.pdf')
$$, '23514', null, 'storage_path must contain the subject id');
select throws_ok($$
  insert into public.attachments (id, subject_id, name, kind, storage_path) values
    ('abababab-0000-4000-8000-0000000000e1', 'aaaaaaaa-0000-4000-8000-000000000001', 'x', 'pdf',
     '22222222-2222-4222-8222-222222222222/aaaaaaaa-0000-4000-8000-000000000001/abababab-0000-4000-8000-0000000000e1/x.pdf')
$$, '23514', null, 'storage_path must start with the owner id');
select throws_ok($$
  insert into public.attachments (id, subject_id, name, kind, storage_path) values
    ('abababab-0000-4000-8000-0000000000e1', 'aaaaaaaa-0000-4000-8000-000000000001', 'x', 'pdf',
     '11111111-1111-4111-8111-111111111111/aaaaaaaa-0000-4000-8000-000000000001/abababab-0000-4000-8000-0000000000e1/a/x.pdf')
$$, '23514', null, 'storage_path must have exactly four segments');
select throws_ok($$
  insert into public.attachments (id, subject_id, name, kind, storage_path) values
    ('abababab-0000-4000-8000-0000000000e1', 'aaaaaaaa-0000-4000-8000-000000000001', 'x', 'spreadsheet',
     '11111111-1111-4111-8111-111111111111/aaaaaaaa-0000-4000-8000-000000000001/abababab-0000-4000-8000-0000000000e1/x')
$$, '23514', null, 'kind must be one of the known kinds');
select throws_ok($$
  insert into public.attachments (id, subject_id, name, kind, storage_path, extracted_text) values
    ('abababab-0000-4000-8000-0000000000e1', 'aaaaaaaa-0000-4000-8000-000000000001', 'x', 'text',
     '11111111-1111-4111-8111-111111111111/aaaaaaaa-0000-4000-8000-000000000001/abababab-0000-4000-8000-0000000000e1/x.txt',
     repeat('a', 200001))
$$, '23514', null, 'extracted_text is capped at 200000 characters');
select lives_ok($$
  insert into public.attachments (id, subject_id, name, kind, storage_path, extracted_text) values
    ('abababab-0000-4000-8000-0000000000e2', 'aaaaaaaa-0000-4000-8000-000000000002', 'big.txt', 'text',
     '11111111-1111-4111-8111-111111111111/aaaaaaaa-0000-4000-8000-000000000002/abababab-0000-4000-8000-0000000000e2/big.txt',
     repeat('a', 200000))
$$, 'extracted_text of exactly 200000 characters is accepted');
select throws_ok($$
  insert into public.attachments (id, subject_id, name, kind, storage_path) values
    ('abababab-0000-4000-8000-0000000000e1', 'aaaaaaaa-0000-4000-8000-0000000000ff', 'x', 'pdf',
     '11111111-1111-4111-8111-111111111111/aaaaaaaa-0000-4000-8000-0000000000ff/abababab-0000-4000-8000-0000000000e1/x.pdf')
$$, '23503', null, 'missing subject is rejected with 23503');
select throws_ok($$
  insert into public.attachments (id, subject_id, name, kind, storage_path, owner_id) values
    ('abababab-0000-4000-8000-0000000000e1', 'aaaaaaaa-0000-4000-8000-000000000001', 'x', 'pdf',
     '22222222-2222-4222-8222-222222222222/aaaaaaaa-0000-4000-8000-000000000001/abababab-0000-4000-8000-0000000000e1/x.pdf',
     '22222222-2222-4222-8222-222222222222')
$$, '42501', null, 'cannot insert an attachment owned by someone else');

select lives_ok($$
  update public.attachments set name = 'Lecture one.pdf' where id = 'abababab-0000-4000-8000-000000000001'
$$, 'owner renames own attachment');
select throws_ok($$
  update public.attachments set subject_id = 'aaaaaaaa-0000-4000-8000-000000000002'
  where id = 'abababab-0000-4000-8000-000000000001'
$$, '42501', null, 'subject_id is immutable');
select throws_ok($$
  update public.attachments
  set storage_path = '11111111-1111-4111-8111-111111111111/aaaaaaaa-0000-4000-8000-000000000001/abababab-0000-4000-8000-000000000001/renamed.pdf'
  where id = 'abababab-0000-4000-8000-000000000001'
$$, '42501', null, 'storage_path is immutable');
select throws_ok($$
  update public.attachments set owner_id = '22222222-2222-4222-8222-222222222222'
  where id = 'abababab-0000-4000-8000-000000000001'
$$, '42501', null, 'owner_id is immutable');
select lives_ok($$
  insert into public.attachments (id, subject_id, name, kind, storage_path) values
    ('abababab-0000-4000-8000-000000000002', 'aaaaaaaa-0000-4000-8000-000000000001', 'notes v2.txt', 'text',
     '11111111-1111-4111-8111-111111111111/aaaaaaaa-0000-4000-8000-000000000001/abababab-0000-4000-8000-000000000002/notes.txt')
  on conflict (id) do update set name = excluded.name
$$, 'owner upsert (sync push) updates an existing row');
select is((select name from public.attachments where id = 'abababab-0000-4000-8000-000000000002'), 'notes v2.txt',
          'owner upsert applied');

-- ============================================================ storage: owner
select lives_ok($$
  insert into storage.objects (bucket_id, name) values
    ('attachments', '11111111-1111-4111-8111-111111111111/aaaaaaaa-0000-4000-8000-000000000001/abababab-0000-4000-8000-000000000001/lecture-1.pdf'),
    ('attachments', '11111111-1111-4111-8111-111111111111/aaaaaaaa-0000-4000-8000-000000000001/abababab-0000-4000-8000-000000000002/notes.txt'),
    ('attachments', '11111111-1111-4111-8111-111111111111/aaaaaaaa-0000-4000-8000-000000000001/abababab-0000-4000-8000-000000000003/old.png'),
    ('attachments', '11111111-1111-4111-8111-111111111111/aaaaaaaa-0000-4000-8000-000000000002/abababab-0000-4000-8000-000000000004/essay.docx'),
    ('attachments', '11111111-1111-4111-8111-111111111111/aaaaaaaa-0000-4000-8000-000000000001/abababab-0000-4000-8000-0000000000aa/orphan.bin'),
    ('attachments', '11111111-1111-4111-8111-111111111111/aaaaaaaa-0000-4000-8000-000000000001/not-a-uuid/x.bin'),
    ('note-images', '11111111-1111-4111-8111-111111111111/bbbbbbbb-0000-4000-8000-000000000001/img.png')
$$, 'owner uploads into own folder (including blobs without a row)');
select throws_ok($$
  insert into storage.objects (bucket_id, name) values
    ('attachments', '22222222-2222-4222-8222-222222222222/aaaaaaaa-0000-4000-8000-000000000001/abababab-0000-4000-8000-000000000001/x.pdf')
$$, '42501', null, 'cannot upload into another user''s folder');
select throws_ok($$
  insert into storage.objects (bucket_id, name) values ('attachments', 'x.pdf')
$$, '42501', null, 'cannot upload at the bucket root');
select is((select count(*)::int from storage.objects where bucket_id = 'attachments'), 6,
          'owner reads all own attachment objects');

-- ============================================================ shares
select lives_ok($$
  insert into public.shares (id, recipient_id, resource_type, resource_id) values
    ('ffffffff-0000-4000-8000-000000000001', '22222222-2222-4222-8222-222222222222', 'subject',
     'aaaaaaaa-0000-4000-8000-000000000001'),
    ('ffffffff-0000-4000-8000-000000000002', '33333333-3333-4333-8333-333333333333', 'note',
     'bbbbbbbb-0000-4000-8000-000000000001')
$$, 'A shares S1 with B and only note N1 with C');

-- ============================================================ B: subject recipient
set local request.jwt.claims to '{"sub":"22222222-2222-4222-8222-222222222222","role":"authenticated"}';
select is((select array_agg(id order by id)::text from public.attachments),
          '{abababab-0000-4000-8000-000000000001,abababab-0000-4000-8000-000000000002,abababab-0000-4000-8000-000000000003}',
          'B sees the attachments of the shared subject only');
select is((select extracted_text from public.attachments where id = 'abababab-0000-4000-8000-000000000002'), 'hello',
          'B reads extracted_text of a shared attachment');
select is(public.can_read_attachment('abababab-0000-4000-8000-000000000004'), false,
          'can_read_attachment is false for an attachment of an unshared subject');
select results_eq(
  $$ select name from storage.objects where bucket_id = 'attachments' order by name $$,
  $$ values
     ('11111111-1111-4111-8111-111111111111/aaaaaaaa-0000-4000-8000-000000000001/abababab-0000-4000-8000-000000000001/lecture-1.pdf'::text),
     ('11111111-1111-4111-8111-111111111111/aaaaaaaa-0000-4000-8000-000000000001/abababab-0000-4000-8000-000000000002/notes.txt'),
     ('11111111-1111-4111-8111-111111111111/aaaaaaaa-0000-4000-8000-000000000001/abababab-0000-4000-8000-000000000003/old.png') $$,
  'B reads the blobs of the shared attachments only (orphans/malformed paths ignored, no error)');

update public.attachments set name = 'hacked' where id = 'abababab-0000-4000-8000-000000000001';
delete from public.attachments where id = 'abababab-0000-4000-8000-000000000002';
select throws_ok($$
  insert into public.attachments (id, subject_id, name, kind, storage_path) values
    ('abababab-0000-4000-8000-0000000000b1', 'aaaaaaaa-0000-4000-8000-000000000001', 'x', 'pdf',
     '22222222-2222-4222-8222-222222222222/aaaaaaaa-0000-4000-8000-000000000001/abababab-0000-4000-8000-0000000000b1/x.pdf')
$$, '42501', null, 'B cannot add an attachment to A''s subject');
select throws_ok($$
  insert into public.attachments (id, subject_id, name, kind, storage_path, owner_id) values
    ('abababab-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-000000000001', 'x', 'pdf',
     '11111111-1111-4111-8111-111111111111/aaaaaaaa-0000-4000-8000-000000000001/abababab-0000-4000-8000-000000000001/lecture-1.pdf',
     '11111111-1111-4111-8111-111111111111')
  on conflict (id) do update set name = excluded.name
$$, '42501', null, 'recipient upsert of a shared attachment is rejected');
-- B plants a blob in B's own folder under A's subject/attachment ids.
select lives_ok($$
  insert into storage.objects (bucket_id, name) values
    ('attachments', '22222222-2222-4222-8222-222222222222/aaaaaaaa-0000-4000-8000-000000000001/abababab-0000-4000-8000-000000000001/lecture-1.pdf')
$$, 'B may upload into B''s own folder');
do $$
begin
  update storage.objects set metadata = '{"hacked":true}'
  where name like '11111111-1111-4111-8111-111111111111/%';
  delete from storage.objects where name like '11111111-1111-4111-8111-111111111111/%';
exception when others then null;
end;
$$;

reset role;
select is((select name from public.attachments where id = 'abababab-0000-4000-8000-000000000001'),
          'Lecture one.pdf', 'B update of A''s attachment had no effect');
select is((select count(*)::int from public.attachments where id = 'abababab-0000-4000-8000-000000000002'), 1,
          'B delete of A''s attachment had no effect');
select is((select count(*)::int from storage.objects
           where name like '11111111-1111-4111-8111-111111111111/%' and metadata is null), 7,
          'B could neither update nor delete A''s objects');

-- ============================================================ C (note-only share) and D (stranger)
set local role authenticated;
set local request.jwt.claims to '{"sub":"33333333-3333-4333-8333-333333333333","role":"authenticated"}';
select is((select count(*)::int from public.notes), 1, 'C sees the shared note');
select is((select count(*)::int from public.attachments), 0, 'a note-only share does not expose attachments');
select is((select count(*)::int from storage.objects where bucket_id = 'attachments'), 0,
          'a note-only share does not expose attachment blobs');
select is((select count(*)::int from storage.objects where bucket_id = 'note-images'), 1,
          'C still reads the note image');

set local request.jwt.claims to '{"sub":"44444444-4444-4444-8444-444444444444","role":"authenticated"}';
select is((select count(*)::int from public.attachments), 0, 'stranger sees no attachments');
select is((select count(*)::int from storage.objects), 0, 'stranger reads no objects');

-- ============================================================ helper edge cases
set local request.jwt.claims to '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}';
select is(public.can_read_attachment_object(
  '22222222-2222-4222-8222-222222222222/aaaaaaaa-0000-4000-8000-000000000001/abababab-0000-4000-8000-000000000001/lecture-1.pdf'),
  false, 'planted blob under someone else''s attachment id is not readable through the helper');
select is((select count(*)::int from storage.objects where name like '22222222-2222-4222-8222-222222222222/%'), 0,
          'A does not see the blob B planted under A''s ids');
select is(public.can_read_attachment_object(null), false, 'null path -> false');
select is(public.can_read_attachment_object('a/b/c'), false, 'three segments -> false');
select is(public.can_read_attachment_object(
  '11111111-1111-4111-8111-111111111111/not-a-uuid/abababab-0000-4000-8000-000000000001/x'), false,
  'non-uuid subject segment -> false');
select is(public.can_read_attachment_object(
  '11111111-1111-4111-8111-111111111111/aaaaaaaa-0000-4000-8000-000000000001/zz/x'), false,
  'non-uuid attachment segment -> false');
select is(public.can_read_attachment_object(
  '11111111-1111-4111-8111-111111111111/aaaaaaaa-0000-4000-8000-000000000001/abababab-0000-4000-8000-000000000001/'), false,
  'empty file segment -> false');

-- ============================================================ soft delete hides from recipients
update public.attachments set deleted_at = now() where id = 'abababab-0000-4000-8000-000000000003';
select isnt((select deleted_at from public.attachments where id = 'abababab-0000-4000-8000-000000000003'), null,
            'owner still sees own attachment tombstone');
set local request.jwt.claims to '{"sub":"22222222-2222-4222-8222-222222222222","role":"authenticated"}';
select is((select count(*)::int from public.attachments where id = 'abababab-0000-4000-8000-000000000003'), 0,
          'recipient no longer sees the soft-deleted attachment');
select is((select count(*)::int from storage.objects
           where name like '%/abababab-0000-4000-8000-000000000003/%'), 0,
          'recipient can no longer read the blob of a soft-deleted attachment');

-- ============================================================ copy_subject (B)
reset role;
create temp table copied (kind text primary key, id uuid);
grant all on copied to authenticated;
set local role authenticated;
set local request.jwt.claims to '{"sub":"22222222-2222-4222-8222-222222222222","role":"authenticated"}';
select lives_ok($$
  insert into copied values ('subject', public.copy_subject('aaaaaaaa-0000-4000-8000-000000000001'))
$$, 'B copies the shared subject');
select results_eq(
  $$ select owner_id, name, mime_type, size_bytes, kind, extracted_text, deleted_at
     from public.attachments where subject_id = (select id from copied where kind = 'subject')
     order by name $$,
  $$ values
     ('22222222-2222-4222-8222-222222222222'::uuid, 'Lecture one.pdf'::text, 'application/pdf'::text, 1000::bigint,
      'pdf'::text, null::text, null::timestamptz),
     ('22222222-2222-4222-8222-222222222222'::uuid, 'notes v2.txt'::text, 'text/plain'::text, 5::bigint,
      'text'::text, 'hello'::text, null::timestamptz) $$,
  'live attachments are copied to B with the same fields (soft-deleted ones skipped)');
select is((select count(*)::int from public.attachments
           where subject_id = (select id from copied where kind = 'subject')
             and id in ('abababab-0000-4000-8000-000000000001', 'abababab-0000-4000-8000-000000000002')), 0,
          'copied attachments get new ids');
select is((select count(*)::int from public.attachments
           where subject_id = (select id from copied where kind = 'subject')
             and storage_path <> '22222222-2222-4222-8222-222222222222/' || subject_id || '/' || id || '/'
                                 || split_part(storage_path, '/', 4)), 0,
          'copied storage paths are {B}/{new subject}/{new id}/{file}');
select results_eq(
  $$ select c.bucket, c.from_path, c.to_path
     from public.note_image_copies c
     where c.bucket = 'attachments'
     order by c.from_path $$,
  $$ select 'attachments'::text, a.from_path, b.storage_path
     from (values
       ('11111111-1111-4111-8111-111111111111/aaaaaaaa-0000-4000-8000-000000000001/abababab-0000-4000-8000-000000000001/lecture-1.pdf'::text, 'lecture-1.pdf'::text),
       ('11111111-1111-4111-8111-111111111111/aaaaaaaa-0000-4000-8000-000000000001/abababab-0000-4000-8000-000000000002/notes.txt', 'notes.txt')
     ) a(from_path, file)
     join public.attachments b
       on b.subject_id = (select id from copied where kind = 'subject')
      and split_part(b.storage_path, '/', 4) = a.file
     order by a.from_path $$,
  'one queued attachments copy per live attachment, from the source path to the new path');
select results_eq(
  $$ select bucket, from_path from public.note_image_copies where bucket <> 'attachments' $$,
  $$ values ('note-images'::text,
             '11111111-1111-4111-8111-111111111111/bbbbbbbb-0000-4000-8000-000000000001/img.png'::text) $$,
  'note image copies still default to bucket note-images');
select is((select count(*)::int from public.attachments
           where owner_id = '11111111-1111-4111-8111-111111111111'
             and subject_id = 'aaaaaaaa-0000-4000-8000-000000000001'), 2,
          'B still sees A''s originals (2 live), untouched');
select lives_ok($$ delete from public.note_image_copies where bucket = 'attachments' $$,
                'B can clear processed attachment copy jobs');
select throws_ok($$
  insert into public.note_image_copies (bucket, from_path, to_path)
  values ('avatars', 'a/b/c', '22222222-2222-4222-8222-222222222222/x/y')
$$, '23514', null, 'queue bucket must be note-images or attachments');
select throws_ok($$
  insert into public.note_image_copies (bucket, from_path, to_path)
  values ('attachments', 'a/b/c/d', '11111111-1111-4111-8111-111111111111/x/y/z')
$$, '42501', null, 'cannot queue an attachment copy into someone else''s folder');

-- Storage copy (as the Storage API does it): B reads the source, writes own folder.
select is((select count(*)::int from storage.objects
           where bucket_id = 'attachments'
             and name = '11111111-1111-4111-8111-111111111111/aaaaaaaa-0000-4000-8000-000000000001/abababab-0000-4000-8000-000000000001/lecture-1.pdf'), 1,
          'B can read the copy source');
select lives_ok($$
  insert into storage.objects (bucket_id, name)
  select 'attachments', storage_path from public.attachments
  where subject_id = (select id from copied where kind = 'subject')
$$, 'B can write the copy targets');

-- C (note-only) cannot copy the subject (and thus never gets its attachments).
set local request.jwt.claims to '{"sub":"33333333-3333-4333-8333-333333333333","role":"authenticated"}';
select throws_ok($$ select public.copy_subject('aaaaaaaa-0000-4000-8000-000000000001') $$,
                 'P0002', null, 'note-only recipient cannot copy the subject');

-- ============================================================ soft-deleting / revoking the subject
set local request.jwt.claims to '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}';
update public.subjects set deleted_at = now() where id = 'aaaaaaaa-0000-4000-8000-000000000001';
reset role;
select is((select count(*)::int from public.shares where id = 'ffffffff-0000-4000-8000-000000000001'), 0,
          'soft-deleting the subject deletes its shares');
set local role authenticated;
set local request.jwt.claims to '{"sub":"22222222-2222-4222-8222-222222222222","role":"authenticated"}';
select is((select count(*)::int from public.attachments
           where owner_id = '11111111-1111-4111-8111-111111111111'), 0,
          'B no longer sees attachments of the soft-deleted subject');
select is((select count(*)::int from storage.objects
           where name like '11111111-1111-4111-8111-111111111111/%'), 0,
          'B can no longer read their blobs');
select is((select count(*)::int from public.attachments), 2, 'B keeps the copied attachments');
select is(public.can_read_attachment('abababab-0000-4000-8000-000000000001'), false,
          'can_read_attachment is false under a soft-deleted subject');

set local request.jwt.claims to '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}';
select is((select count(*)::int from public.attachments where subject_id = 'aaaaaaaa-0000-4000-8000-000000000001'), 3,
          'owner still sees attachments under own soft-deleted subject');

-- ============================================================ hard delete cascades; anon
select lives_ok($$ delete from public.subjects where id = 'aaaaaaaa-0000-4000-8000-000000000002' $$,
                'owner hard-deletes subject S2');
select is((select count(*)::int from public.attachments where subject_id = 'aaaaaaaa-0000-4000-8000-000000000002'), 0,
          'hard-deleting a subject deletes its attachment rows');

reset role;
set local role anon;
select throws_ok($$ select count(*) from public.attachments $$, '42501', null, 'anon has no table access');
select throws_ok($$ select public.can_read_attachment('abababab-0000-4000-8000-000000000001') $$, '42501', null,
                 'anon cannot execute attachment helpers');
reset role;

select * from finish();
rollback;
