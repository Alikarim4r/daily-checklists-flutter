-- =============================================================================
-- Daily Checklists — storage
-- Migration: 004_storage.sql
-- Path: {organization_id}/{site_id}/{inspection_id}/{filename}
-- =============================================================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'checklist-media',
  'checklist-media',
  false,
  10485760,
  array['image/jpeg', 'image/jpg', 'image/png', 'image/webp', 'image/gif']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create or replace function public.storage_path_organization_id(path text)
returns uuid language sql immutable as $$
  select nullif(split_part(path, '/', 1), '')::uuid;
$$;

create or replace function public.storage_path_site_id(path text)
returns uuid language sql immutable as $$
  select nullif(split_part(path, '/', 2), '')::uuid;
$$;

create or replace function public.storage_path_valid(path text)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.sites s
    where s.id = public.storage_path_site_id(path)
      and s.organization_id = public.storage_path_organization_id(path)
  );
$$;

create policy checklist_media_select on storage.objects
  for select to authenticated
  using (
    bucket_id = 'checklist-media'
    and public.storage_path_valid(name)
    and (public.is_super_admin() or public.has_site_access(public.storage_path_site_id(name)))
  );

create policy checklist_media_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'checklist-media'
    and public.storage_path_valid(name)
    and (public.is_super_admin() or public.can_write_site(public.storage_path_site_id(name)))
  );

create policy checklist_media_update on storage.objects
  for update to authenticated
  using (
    bucket_id = 'checklist-media'
    and (public.is_super_admin() or public.can_write_site(public.storage_path_site_id(name)))
  )
  with check (
    bucket_id = 'checklist-media'
    and (public.is_super_admin() or public.can_write_site(public.storage_path_site_id(name)))
  );

create policy checklist_media_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'checklist-media'
    and (public.is_super_admin() or public.can_manage_site(public.storage_path_site_id(name)))
  );
