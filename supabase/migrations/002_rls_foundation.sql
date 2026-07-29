-- =============================================================================
-- Daily Checklists — RLS helpers + table policies (foundation)
-- Migration: 002_rls_foundation.sql
-- =============================================================================

create or replace function public.is_approved_active_user()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid()
      and is_active = true
      and approval_status = 'approved'
  );
$$;

create or replace function public.is_super_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid()
      and role = 'super_admin'
      and is_active = true
      and approval_status = 'approved'
  );
$$;

create or replace function public.has_site_access(p_site_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_super_admin()
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
as $$
  select public.is_super_admin()
    or (
      public.is_approved_active_user()
      and exists (
        select 1 from public.user_site_access usa
        where usa.user_id = auth.uid()
          and usa.site_id = p_site_id
          and usa.can_write = true
          and usa.role in ('site_admin', 'technician')
      )
    );
$$;

create or replace function public.can_manage_site(p_site_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_super_admin()
    or (
      public.is_approved_active_user()
      and exists (
        select 1 from public.user_site_access usa
        where usa.user_id = auth.uid()
          and usa.site_id = p_site_id
          and usa.can_manage = true
          and usa.role = 'site_admin'
      )
    );
$$;

alter table public.organizations enable row level security;
alter table public.zones enable row level security;
alter table public.sites enable row level security;
alter table public.profiles enable row level security;
alter table public.user_site_access enable row level security;

-- Profiles
create policy profiles_select_own_or_admin on public.profiles
  for select to authenticated
  using (id = auth.uid() or public.is_super_admin());

create policy profiles_update_own on public.profiles
  for update to authenticated
  using (id = auth.uid() or public.is_super_admin())
  with check (id = auth.uid() or public.is_super_admin());

create policy profiles_admin_all on public.profiles
  for all to authenticated
  using (public.is_super_admin())
  with check (public.is_super_admin());

-- Organizations / zones / sites readable when approved
create policy organizations_select on public.organizations
  for select to authenticated
  using (public.is_approved_active_user());

create policy organizations_admin_write on public.organizations
  for all to authenticated
  using (public.is_super_admin())
  with check (public.is_super_admin());

create policy zones_select on public.zones
  for select to authenticated
  using (public.is_approved_active_user());

create policy zones_admin_write on public.zones
  for all to authenticated
  using (public.is_super_admin())
  with check (public.is_super_admin());

create policy sites_select on public.sites
  for select to authenticated
  using (
    public.is_super_admin()
    or public.has_site_access(id)
    or public.is_approved_active_user()
  );

create policy sites_admin_write on public.sites
  for all to authenticated
  using (public.is_super_admin())
  with check (public.is_super_admin());

-- Site access
create policy usa_select on public.user_site_access
  for select to authenticated
  using (user_id = auth.uid() or public.is_super_admin());

create policy usa_admin_write on public.user_site_access
  for all to authenticated
  using (public.is_super_admin())
  with check (public.is_super_admin());
