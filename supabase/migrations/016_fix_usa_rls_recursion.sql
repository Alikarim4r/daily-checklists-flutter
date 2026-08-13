-- =============================================================================
-- Fix infinite RLS recursion on user_site_access / sites / profiles
-- Migration: 016_fix_usa_rls_recursion.sql
-- =============================================================================
-- Cause: usa policies queried user_site_access (self) and sites; sites policies
-- called has_site_access() which queried user_site_access again under RLS.
-- Fix: all auth helper functions bypass RLS (row_security = off), and USA
-- policies call those helpers instead of joining protected tables.

create or replace function public.is_platform_owner()
returns boolean
language sql
stable
security definer
set search_path = public
set row_security = off
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid()
      and lower(trim(email)) = 'alikarim4r@gmail.com'
  );
$$;

create or replace function public.is_approved_active_user()
returns boolean
language sql
stable
security definer
set search_path = public
set row_security = off
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid()
      and is_active = true
      and approval_status = 'approved'
  );
$$;

create or replace function public.current_user_role()
returns public.user_role
language sql
stable
security definer
set search_path = public
set row_security = off
as $$
  select role from public.profiles where id = auth.uid() limit 1;
$$;

create or replace function public.current_home_organization_id()
returns uuid
language sql
stable
security definer
set search_path = public
set row_security = off
as $$
  select home_organization_id from public.profiles where id = auth.uid() limit 1;
$$;

create or replace function public.is_super_admin()
returns boolean
language sql
stable
security definer
set search_path = public
set row_security = off
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid()
      and role = 'super_admin'
      and is_active = true
      and approval_status = 'approved'
      and not public.is_platform_owner()
  );
$$;

create or replace function public.is_org_super_admin(p_organization_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
set row_security = off
as $$
  select public.is_super_admin()
    and public.current_home_organization_id() is not null
    and public.current_home_organization_id() = p_organization_id;
$$;

create or replace function public.is_site_admin()
returns boolean
language sql
stable
security definer
set search_path = public
set row_security = off
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid()
      and role = 'site_admin'
      and is_active = true
      and approval_status = 'approved'
  );
$$;

create or replace function public.is_elevated_admin()
returns boolean
language sql
stable
security definer
set search_path = public
set row_security = off
as $$
  select public.is_platform_owner();
$$;

create or replace function public.can_access_organization(p_organization_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
set row_security = off
as $$
  select
    public.is_platform_owner()
    or public.is_org_super_admin(p_organization_id)
    or (
      public.is_approved_active_user()
      and exists (
        select 1
        from public.user_site_access usa
        join public.sites s on s.id = usa.site_id
        where usa.user_id = auth.uid()
          and s.organization_id = p_organization_id
          and usa.can_read = true
      )
    );
$$;

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
        select 1 from public.user_site_access usa
        where usa.user_id = auth.uid()
          and usa.site_id = p_site_id
          and usa.can_read = true
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
        select 1 from public.user_site_access usa
        where usa.user_id = auth.uid()
          and usa.site_id = p_site_id
          and usa.can_write = true
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
        select 1 from public.user_site_access usa
        where usa.user_id = auth.uid()
          and usa.site_id = p_site_id
          and usa.can_manage = true
      )
    );
$$;

create or replace function public.can_write_sites_in_organization(p_organization_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
set row_security = off
as $$
  select public.is_platform_owner()
    or public.is_org_super_admin(p_organization_id);
$$;

create or replace function public.can_insert_site(
  p_organization_id uuid,
  p_zone_id uuid,
  p_parent_site_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
set row_security = off
as $$
  select
    public.is_platform_owner()
    or public.is_org_super_admin(p_organization_id)
    or (
      public.is_site_admin()
      and (
        (
          p_parent_site_id is not null
          and public.can_manage_site(p_parent_site_id)
        )
        or (
          p_parent_site_id is null
          and p_zone_id is not null
          and exists (
            select 1
            from public.user_site_access usa
            join public.sites s on s.id = usa.site_id
            where usa.user_id = auth.uid()
              and usa.can_manage = true
              and s.organization_id = p_organization_id
              and s.zone_id = p_zone_id
          )
        )
      )
    );
$$;

create or replace function public.can_write_zones_in_organization(p_organization_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
set row_security = off
as $$
  select public.is_platform_owner()
    or public.is_org_super_admin(p_organization_id);
$$;

-- Helpers used only from USA policies (no self-join under RLS)
create or replace function public.usa_row_visible(p_user_id uuid, p_site_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
set row_security = off
as $$
  select
    p_user_id = auth.uid()
    or public.is_platform_owner()
    or exists (
      select 1 from public.sites s
      where s.id = p_site_id
        and public.is_org_super_admin(s.organization_id)
    )
    or (
      public.is_site_admin()
      and exists (
        select 1 from public.user_site_access mine
        where mine.user_id = auth.uid()
          and mine.site_id = p_site_id
          and mine.can_manage = true
      )
    );
$$;

grant execute on function public.usa_row_visible(uuid, uuid) to authenticated;

create or replace function public.usa_row_writable(
  p_user_id uuid,
  p_site_id uuid,
  p_role public.user_role
)
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
      public.is_site_admin()
      and p_role in ('technician', 'viewer', 'technician_request')
      and exists (
        select 1 from public.user_site_access mine
        where mine.user_id = auth.uid()
          and mine.site_id = p_site_id
          and mine.can_manage = true
      )
    );
$$;

grant execute on function public.usa_row_writable(uuid, uuid, public.user_role) to authenticated;

create or replace function public.profile_row_visible(p_profile_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
set row_security = off
as $$
  select
    p_profile_id = auth.uid()
    or public.is_platform_owner()
    or (
      public.is_super_admin()
      and exists (
        select 1 from public.profiles p
        where p.id = p_profile_id
          and (
            p.home_organization_id = public.current_home_organization_id()
            or exists (
              select 1
              from public.user_site_access usa
              join public.sites s on s.id = usa.site_id
              where usa.user_id = p.id
                and s.organization_id = public.current_home_organization_id()
            )
          )
      )
    )
    or (
      public.is_site_admin()
      and exists (
        select 1
        from public.user_site_access mine
        join public.user_site_access theirs on theirs.site_id = mine.site_id
        where mine.user_id = auth.uid()
          and mine.can_manage = true
          and theirs.user_id = p_profile_id
      )
    );
$$;

grant execute on function public.profile_row_visible(uuid) to authenticated;

-- Rebuild policies to use helpers (no recursive table scans under RLS)
drop policy if exists usa_select on public.user_site_access;
drop policy if exists usa_admin_write on public.user_site_access;

create policy usa_select on public.user_site_access
  for select to authenticated
  using (public.usa_row_visible(user_id, site_id));

create policy usa_admin_write on public.user_site_access
  for all to authenticated
  using (public.usa_row_writable(user_id, site_id, role))
  with check (public.usa_row_writable(user_id, site_id, role));

drop policy if exists profiles_select_scoped on public.profiles;
create policy profiles_select_scoped on public.profiles
  for select to authenticated
  using (public.profile_row_visible(id));
