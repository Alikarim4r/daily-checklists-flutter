-- =============================================================================
-- Report logos: org AR/EN header + zone/site footer slots
-- Migration: 014_report_logos.sql
-- Positions:
--   Org logo (locale): top (right in AR layout, right/outer in EN header)
--   Zone logo: bottom-right EN, bottom-left AR
--   Site logo: bottom-left EN, bottom-right AR
--   Site logo resolution: checklist unit → parent campus → blank
-- =============================================================================

alter table public.organizations
  add column if not exists logo_en_path text,
  add column if not exists logo_ar_path text;

alter table public.zones
  add column if not exists report_logo_path text;

alter table public.sites
  add column if not exists report_logo_path text;

comment on column public.organizations.logo_en_path is
  'Org header logo for English UI/PDF. Path in report-logos bucket.';
comment on column public.organizations.logo_ar_path is
  'Org header logo for Arabic UI/PDF. Path in report-logos bucket.';
comment on column public.zones.report_logo_path is
  'Zone footer logo. EN: bottom-right; AR: bottom-left.';
comment on column public.sites.report_logo_path is
  'Site/campus/unit footer logo. EN: bottom-left; AR: bottom-right. '
  'Units inherit campus logo when unset.';

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'report-logos',
  'report-logos',
  false,
  5242880,
  array['image/png', 'image/jpeg', 'image/jpg', 'image/webp']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- Path: {organization_id}/...
create or replace function public.report_logo_org_id(path text)
returns uuid
language sql
immutable
as $$
  select nullif(split_part(path, '/', 1), '')::uuid;
$$;

create or replace function public.can_manage_report_logos(org_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_platform_owner()
    or public.is_super_admin()
    or exists (
      select 1
      from public.user_site_access usa
      join public.sites s on s.id = usa.site_id
      where usa.user_id = auth.uid()
        and s.organization_id = org_id
        and usa.can_manage = true
    );
$$;

grant execute on function public.report_logo_org_id(text) to authenticated;
grant execute on function public.can_manage_report_logos(uuid) to authenticated;

drop policy if exists report_logos_select on storage.objects;
create policy report_logos_select on storage.objects
  for select to authenticated
  using (
    bucket_id = 'report-logos'
    and (
      public.is_platform_owner()
      or public.is_approved_active_user()
    )
  );

drop policy if exists report_logos_insert on storage.objects;
create policy report_logos_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'report-logos'
    and public.can_manage_report_logos(public.report_logo_org_id(name))
  );

drop policy if exists report_logos_update on storage.objects;
create policy report_logos_update on storage.objects
  for update to authenticated
  using (
    bucket_id = 'report-logos'
    and public.can_manage_report_logos(public.report_logo_org_id(name))
  )
  with check (
    bucket_id = 'report-logos'
    and public.can_manage_report_logos(public.report_logo_org_id(name))
  );

drop policy if exists report_logos_delete on storage.objects;
create policy report_logos_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'report-logos'
    and public.can_manage_report_logos(public.report_logo_org_id(name))
  );
