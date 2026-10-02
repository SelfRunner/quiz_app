-- =============================================================================
-- Storage: private bucket `note-images`, object path {owner_id}/{note_id}/{file}
-- =============================================================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('note-images', 'note-images', false, 10485760, array['image/*'])
on conflict (id) do nothing;

-- True when `p_name` has the exact shape {owner_uuid}/{note_uuid}/{file},
-- the note exists, is owned by {owner_uuid}, and the caller can read it.
-- Malformed paths (wrong depth, non-uuid segment) return false, never error.
create function public.can_read_note_object(p_name text)
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
  v_note_id uuid;
begin
  if p_name is null
     or coalesce(array_length(v_parts, 1), 0) <> 3
     or v_parts[3] = ''
     or v_parts[2] !~ v_uuid_re then
    return false;
  end if;
  v_note_id := v_parts[2]::uuid;

  return exists (
    select 1 from public.notes n
    where n.id = v_note_id and n.owner_id::text = v_parts[1]
  ) and public.can_read_note(v_note_id);
end;
$$;

revoke execute on function public.can_read_note_object(text) from public, anon;
grant execute on function public.can_read_note_object(text) to authenticated, service_role;

-- Writes: only inside the caller's own top-level folder.
create policy "note-images: owner insert" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'note-images'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy "note-images: owner update" on storage.objects
  for update to authenticated
  using (
    bucket_id = 'note-images'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  )
  with check (
    bucket_id = 'note-images'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy "note-images: owner delete" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'note-images'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

-- Reads: own folder, or any object of a note the caller can read.
create policy "note-images: read own or shared" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'note-images'
    and (
      (storage.foldername(name))[1] = (select auth.uid())::text
      or public.can_read_note_object(name)
    )
  );
