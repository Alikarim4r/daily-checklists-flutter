-- =============================================================================
-- Daily Checklists — platform owner, approve RPC, site_admin RLS
-- Migration: 006_admin_approval_and_owner.sql
-- Independent of smart-meters-platform.
-- =============================================================================

create or replace function public.is_platform_owner()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and lower(trim(p.email)) = any (array[
        'alikarim4r@gmail.com'
      ])
  );
$$;

comment on function public.is_platform_owner() is
  'True when the signed-in profile email is in the platform-owner allowlist.';

grant execute on function public.is_platform_owner() to authenticated;

-- Owner account is always approved super_admin when present.
update public.profiles
set
  role = 'super_admin',
  approval_status = 'approved',
  is_active = true,
  updated_at = now()
where lower(trim(email)) = 'alikarim4r@gmail.com';

create or replace function public.current_user_role()
returns public.user_role
language sql
stable
security definer
set search_path = public
as $$
  select role
  from public.profiles
  where id = auth.uid()
  limit 1;
$$;

grant execute on function public.current_user_role() to authenticated;

-- Elevated bypass: platform owner OR approved super_admin
create or replace function public.is_elevated_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_platform_owner() or public.is_super_admin();
$$;

grant execute on function public.is_elevated_admin() to authenticated;

-- site_admin may manage a site when can_manage on that site
create or replace function public.site_admin_may_manage_site(p_site_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_elevated_admin()
    or (
      public.is_approved_active_user()
      and public.current_user_role() = 'site_admin'
      and exists (
        select 1 from public.user_site_access usa
        where usa.user_id = auth.uid()
          and usa.site_id = p_site_id
          and usa.can_manage = true
      )
    );
$$;

grant execute on function public.site_admin_may_manage_site(uuid) to authenticated;

-- Refresh access helpers to include platform owner
create or replace function public.has_site_access(p_site_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_elevated_admin()
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
  select public.is_elevated_admin()
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
as $$
  select public.is_elevated_admin()
    or (
      public.is_approved_active_user()
      and exists (
        select 1 from public.user_site_access usa
        where usa.user_id = auth.uid()
          and usa.site_id = p_site_id
          and usa.can_manage = true
      )
    );
$$;

-- Atomic approve: role + sites + default flags
create or replace function public.admin_approve_user(
  p_user_id uuid,
  p_role public.user_role,
  p_site_ids uuid[],
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
declare
  v_actor uuid := auth.uid();
  v_prev_status public.approval_status;
  v_site_id uuid;
  v_can_write boolean;
  v_can_manage boolean;
begin
  if v_actor is null then
    raise exception 'Not authenticated';
  end if;

  if p_user_id = v_actor then
    raise exception 'Users cannot approve themselves';
  end if;

  if p_role = 'super_admin' then
    if not public.is_platform_owner() then
      raise exception 'Only platform owner can approve as super_admin';
    end if;
  elsif p_role not in ('technician', 'viewer', 'site_admin') then
    raise exception 'Invalid role for approval: %', p_role;
  end if;

  if not public.is_elevated_admin() then
    if public.current_user_role() <> 'site_admin' then
      raise exception 'Only super_admin or site_admin can approve users';
    end if;
  end if;

  if p_role in ('technician', 'viewer', 'site_admin') then
    if p_site_ids is null or cardinality(p_site_ids) = 0 then
      raise exception
        'Site assignment required: select at least one site for role %',
        p_role;
    end if;
  end if;

  select approval_status
  into v_prev_status
  from public.profiles
  where id = p_user_id
  for update;

  if not found then
    raise exception 'User not found';
  end if;

  if v_prev_status not in ('pending', 'suspended', 'rejected') then
    raise exception 'User is not in approvable state: %', v_prev_status;
  end if;

  v_can_write := p_role in ('technician', 'site_admin', 'super_admin');
  v_can_manage := p_role in ('site_admin', 'super_admin');

  update public.profiles
  set
    role = p_role,
    approval_status = 'approved',
    is_active = true,
    approval_note = p_note,
    approved_at = now(),
    approved_by = v_actor,
    updated_at = now()
  where id = p_user_id;

  delete from public.user_site_access where user_id = p_user_id;

  if p_site_ids is not null then
    foreach v_site_id in array p_site_ids loop
      if not public.is_elevated_admin()
         and not public.site_admin_may_manage_site(v_site_id) then
        raise exception 'Cannot assign site %', v_site_id;
      end if;

      insert into public.user_site_access (
        user_id, site_id, role, can_read, can_write, can_manage
      ) values (
        p_user_id, v_site_id, p_role, true, v_can_write, v_can_manage
      );
    end loop;
  end if;
end;
$$;

revoke all on function public.admin_approve_user(uuid, public.user_role, uuid[], text) from public;
grant execute on function public.admin_approve_user(uuid, public.user_role, uuid[], text) to authenticated;

create or replace function public.admin_set_user_status(
  p_user_id uuid,
  p_status public.approval_status,
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
declare
  v_actor uuid := auth.uid();
  v_target_role public.user_role;
  v_target_email text;
begin
  if v_actor is null then
    raise exception 'Not authenticated';
  end if;

  if p_user_id = v_actor then
    raise exception 'Cannot change your own status here';
  end if;

  if not public.is_elevated_admin()
     and public.current_user_role() <> 'site_admin' then
    raise exception 'Not allowed';
  end if;

  if p_status not in ('rejected', 'suspended', 'pending') then
    raise exception 'Invalid status for this RPC: %', p_status;
  end if;

  select role, lower(trim(email))
  into v_target_role, v_target_email
  from public.profiles
  where id = p_user_id
  for update;

  if not found then
    raise exception 'User not found';
  end if;

  if v_target_email = 'alikarim4r@gmail.com' then
    raise exception 'Cannot change platform owner status';
  end if;

  if v_target_role = 'super_admin' and not public.is_platform_owner() then
    raise exception 'Cannot change another super_admin status';
  end if;

  update public.profiles
  set
    approval_status = p_status,
    is_active = false,
    approval_note = p_note,
    updated_at = now()
  where id = p_user_id;
end;
$$;

revoke all on function public.admin_set_user_status(uuid, public.approval_status, text) from public;
grant execute on function public.admin_set_user_status(uuid, public.approval_status, text) to authenticated;

-- Replace profile / USA policies to allow site_admin within managed sites
drop policy if exists profiles_select_own_or_admin on public.profiles;
drop policy if exists profiles_update_own on public.profiles;
drop policy if exists profiles_admin_all on public.profiles;

create policy profiles_select_own_or_admin on public.profiles
  for select to authenticated
  using (
    id = auth.uid()
    or public.is_elevated_admin()
    or (
      public.current_user_role() = 'site_admin'
      and public.is_approved_active_user()
    )
  );

create policy profiles_update_own on public.profiles
  for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

-- Writes to profiles go through RPCs (security definer). Keep elevated direct write.
create policy profiles_elevated_all on public.profiles
  for all to authenticated
  using (public.is_elevated_admin())
  with check (public.is_elevated_admin());

drop policy if exists usa_select on public.user_site_access;
drop policy if exists usa_admin_write on public.user_site_access;

create policy usa_select on public.user_site_access
  for select to authenticated
  using (
    user_id = auth.uid()
    or public.is_elevated_admin()
    or public.site_admin_may_manage_site(site_id)
  );

create policy usa_admin_write on public.user_site_access
  for all to authenticated
  using (
    public.is_elevated_admin()
    or public.site_admin_may_manage_site(site_id)
  )
  with check (
    public.is_elevated_admin()
    or public.site_admin_may_manage_site(site_id)
  );

-- Sites: elevated can write; site_admin read via access
drop policy if exists sites_select on public.sites;
create policy sites_select on public.sites
  for select to authenticated
  using (
    public.is_elevated_admin()
    or public.has_site_access(id)
    or (
      public.is_approved_active_user()
      and public.current_user_role() in ('super_admin', 'site_admin')
    )
  );

drop policy if exists sites_admin_write on public.sites;
create policy sites_admin_write on public.sites
  for all to authenticated
  using (public.is_elevated_admin())
  with check (public.is_elevated_admin());
