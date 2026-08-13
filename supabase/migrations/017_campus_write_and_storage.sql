-- =============================================================================
-- Expand site access to parent campus + fix storage RLS for photo uploads
-- Migration: 017_campus_write_and_storage.sql
-- =============================================================================
-- Issue: USA is often granted on the campus (parent) only. Checklist units
-- (children) are used as inspection.site_id / storage path segment. Helpers
-- only matched exact site_id → can_write_site false → storage insert denied.
-- Also storage policies still used bare is_super_admin() (global).

create or replace function public.has_site_access(p_site_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
set row_security = off
as $$
  select
    public.is_platform_owner()
    or exists (
      select 1 from public.sites s
      where s.id = p_site_id
        and public.is_org_super_admin(s.organization_id)
    )
    or (
      public.is_approved_active_user()
      and exists (
        select 1
        from public.user_site_access usa
        left join public.sites child on child.id = p_site_id
        where usa.user_id = auth.uid()
          and usa.can_read = true
          and (
            usa.site_id = p_site_id
            or (child.parent_site_id is not null and usa.site_id = child.parent_site_id)
          )
      )
    );
$$;

create or replace function public.can_write_site(p_site_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
set row_security = off
as $$
  select
    public.is_platform_owner()
    or exists (
      select 1 from public.sites s
      where s.id = p_site_id
        and public.is_org_super_admin(s.organization_id)
    )
    or (
      public.is_approved_active_user()
      and exists (
        select 1
        from public.user_site_access usa
        left join public.sites child on child.id = p_site_id
        where usa.user_id = auth.uid()
          and usa.can_write = true
          and (
            usa.site_id = p_site_id
            or (child.parent_site_id is not null and usa.site_id = child.parent_site_id)
          )
      )
    );
$$;

create or replace function public.can_manage_site(p_site_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
set row_security = off
as $$
  select
    public.is_platform_owner()
    or exists (
      select 1 from public.sites s
      where s.id = p_site_id
        and public.is_org_super_admin(s.organization_id)
    )
    or (
      public.is_approved_active_user()
      and public.is_site_admin()
      and exists (
        select 1
        from public.user_site_access usa
        left join public.sites child on child.id = p_site_id
        where usa.user_id = auth.uid()
          and usa.can_manage = true
          and (
            usa.site_id = p_site_id
            or (child.parent_site_id is not null and usa.site_id = child.parent_site_id)
          )
      )
    );
$$;

create or replace function public.storage_path_valid(path text)
returns boolean
language sql
stable
security definer
set search_path = public
set row_security = off
as $$
  select exists (
    select 1 from public.sites s
    where s.id = public.storage_path_site_id(path)
      and s.organization_id = public.storage_path_organization_id(path)
  );
$$;

drop policy if exists checklist_media_select on storage.objects;
drop policy if exists checklist_media_insert on storage.objects;
drop policy if exists checklist_media_update on storage.objects;
drop policy if exists checklist_media_delete on storage.objects;

create policy checklist_media_select on storage.objects
  for select to authenticated
  using (
    bucket_id = 'checklist-media'
    and public.storage_path_valid(name)
    and (
      public.is_platform_owner()
      or public.has_site_access(public.storage_path_site_id(name))
    )
  );

create policy checklist_media_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'checklist-media'
    and public.storage_path_valid(name)
    and (
      public.is_platform_owner()
      or public.can_write_site(public.storage_path_site_id(name))
    )
  );

create policy checklist_media_update on storage.objects
  for update to authenticated
  using (
    bucket_id = 'checklist-media'
    and (
      public.is_platform_owner()
      or public.can_write_site(public.storage_path_site_id(name))
    )
  )
  with check (
    bucket_id = 'checklist-media'
    and public.storage_path_valid(name)
    and (
      public.is_platform_owner()
      or public.can_write_site(public.storage_path_site_id(name))
    )
  );

create policy checklist_media_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'checklist-media'
    and (
      public.is_platform_owner()
      or public.can_manage_site(public.storage_path_site_id(name))
    )
  );
