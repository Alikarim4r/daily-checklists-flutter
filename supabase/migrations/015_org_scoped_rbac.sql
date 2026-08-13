-- =============================================================================
-- Org-scoped RBAC: Owner (all) / Super Admin (one org) / Site Admin (sites)
-- Migration: 015_org_scoped_rbac.sql
-- =============================================================================

alter table public.profiles
  add column if not exists home_organization_id uuid
    references public.organizations (id) on delete set null;

create index if not exists profiles_home_organization_id_idx
  on public.profiles (home_organization_id)
  where home_organization_id is not null;

comment on column public.profiles.home_organization_id is
  'Primary organization for org-scoped super_admin (one org). Null for owner.';

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

create or replace function public.current_home_organization_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select home_organization_id from public.profiles where id = auth.uid() limit 1;
$$;

grant execute on function public.current_home_organization_id() to authenticated;

-- True role check (does NOT include platform owner bypass)
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
      and not public.is_platform_owner()
  );
$$;

create or replace function public.is_org_super_admin(p_organization_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_super_admin()
    and public.current_home_organization_id() is not null
    and public.current_home_organization_id() = p_organization_id;
$$;

grant execute on function public.is_org_super_admin(uuid) to authenticated;

create or replace function public.is_site_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid()
      and role = 'site_admin'
      and is_active = true
      and approval_status = 'approved'
  );
$$;

grant execute on function public.is_site_admin() to authenticated;

-- Elevated for OWNER only (global). Org super_admin is scoped separately.
create or replace function public.is_elevated_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_platform_owner();
$$;

grant execute on function public.is_elevated_admin() to authenticated;

create or replace function public.can_access_organization(p_organization_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
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

grant execute on function public.can_access_organization(uuid) to authenticated;

create or replace function public.has_site_access(p_site_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
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

-- Owner / org super_admin: full site CRUD in org.
-- Site admin: only update/delete sites they can_manage (not org-wide).
create or replace function public.can_write_sites_in_organization(p_organization_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_platform_owner()
    or public.is_org_super_admin(p_organization_id);
$$;

grant execute on function public.can_write_sites_in_organization(uuid) to authenticated;

-- Site admin may insert a site under a managed parent campus, or in a zone
-- where they already manage at least one site.
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

grant execute on function public.can_insert_site(uuid, uuid, uuid) to authenticated;

create or replace function public.can_write_zones_in_organization(p_organization_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_platform_owner()
    or public.is_org_super_admin(p_organization_id);
$$;

grant execute on function public.can_write_zones_in_organization(uuid) to authenticated;

create or replace function public.site_admin_may_manage_site(p_site_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.can_manage_site(p_site_id);
$$;

-- ---------------------------------------------------------------------------
-- RLS: organizations
-- ---------------------------------------------------------------------------
drop policy if exists organizations_select on public.organizations;
create policy organizations_select on public.organizations
  for select to authenticated
  using (
    public.is_platform_owner()
    or public.can_access_organization(id)
  );

drop policy if exists organizations_admin_write on public.organizations;
create policy organizations_admin_write on public.organizations
  for all to authenticated
  using (public.is_platform_owner())
  with check (public.is_platform_owner());

-- ---------------------------------------------------------------------------
-- RLS: zones
-- ---------------------------------------------------------------------------
drop policy if exists zones_select on public.zones;
create policy zones_select on public.zones
  for select to authenticated
  using (
    public.is_platform_owner()
    or public.can_access_organization(organization_id)
  );

drop policy if exists zones_admin_write on public.zones;
create policy zones_admin_write on public.zones
  for all to authenticated
  using (public.can_write_zones_in_organization(organization_id))
  with check (public.can_write_zones_in_organization(organization_id));

-- ---------------------------------------------------------------------------
-- RLS: sites
-- ---------------------------------------------------------------------------
drop policy if exists sites_select on public.sites;
create policy sites_select on public.sites
  for select to authenticated
  using (
    public.is_platform_owner()
    or public.is_org_super_admin(organization_id)
    or public.has_site_access(id)
  );

drop policy if exists sites_admin_write on public.sites;
drop policy if exists sites_insert on public.sites;
drop policy if exists sites_update on public.sites;
drop policy if exists sites_delete on public.sites;

create policy sites_insert on public.sites
  for insert to authenticated
  with check (
    public.can_insert_site(organization_id, zone_id, parent_site_id)
  );

create policy sites_update on public.sites
  for update to authenticated
  using (
    public.can_write_sites_in_organization(organization_id)
    or public.can_manage_site(id)
  )
  with check (
    public.can_write_sites_in_organization(organization_id)
    or public.can_manage_site(id)
  );

create policy sites_delete on public.sites
  for delete to authenticated
  using (
    public.can_write_sites_in_organization(organization_id)
    or public.can_manage_site(id)
  );

-- ---------------------------------------------------------------------------
-- RLS: profiles — owner sees all; org super_admin sees users with sites in org;
-- site_admin sees self + users they manage on shared sites
-- ---------------------------------------------------------------------------
drop policy if exists profiles_select_own_or_admin on public.profiles;
drop policy if exists profiles_update_own on public.profiles;
drop policy if exists profiles_admin_all on public.profiles;
drop policy if exists profiles_select_scoped on public.profiles;
drop policy if exists profiles_owner_all on public.profiles;

create policy profiles_select_scoped on public.profiles
  for select to authenticated
  using (
    id = auth.uid()
    or public.is_platform_owner()
    or (
      public.is_super_admin()
      and (
        home_organization_id = public.current_home_organization_id()
        or exists (
          select 1
          from public.user_site_access usa
          join public.sites s on s.id = usa.site_id
          where usa.user_id = profiles.id
            and s.organization_id = public.current_home_organization_id()
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
          and theirs.user_id = profiles.id
      )
    )
  );

create policy profiles_update_own on public.profiles
  for update to authenticated
  using (id = auth.uid() or public.is_platform_owner())
  with check (id = auth.uid() or public.is_platform_owner());

create policy profiles_owner_all on public.profiles
  for all to authenticated
  using (public.is_platform_owner())
  with check (public.is_platform_owner());

-- ---------------------------------------------------------------------------
-- RLS: user_site_access
-- ---------------------------------------------------------------------------
drop policy if exists usa_select on public.user_site_access;
drop policy if exists usa_admin_write on public.user_site_access;

create policy usa_select on public.user_site_access
  for select to authenticated
  using (
    user_id = auth.uid()
    or public.is_platform_owner()
    or exists (
      select 1 from public.sites s
      where s.id = site_id
        and public.is_org_super_admin(s.organization_id)
    )
    or (
      public.is_site_admin()
      and exists (
        select 1 from public.user_site_access mine
        where mine.user_id = auth.uid()
          and mine.site_id = user_site_access.site_id
          and mine.can_manage = true
      )
    )
  );

create policy usa_admin_write on public.user_site_access
  for all to authenticated
  using (
    public.is_platform_owner()
    or exists (
      select 1 from public.sites s
      where s.id = site_id
        and public.is_org_super_admin(s.organization_id)
    )
    or (
      public.is_site_admin()
      and exists (
        select 1 from public.user_site_access mine
        where mine.user_id = auth.uid()
          and mine.site_id = user_site_access.site_id
          and mine.can_manage = true
      )
      -- site_admin may only manage technician/viewer rows, not other admins
      and user_site_access.role in ('technician', 'viewer', 'technician_request')
    )
  )
  with check (
    public.is_platform_owner()
    or exists (
      select 1 from public.sites s
      where s.id = site_id
        and public.is_org_super_admin(s.organization_id)
    )
    or (
      public.is_site_admin()
      and exists (
        select 1 from public.user_site_access mine
        where mine.user_id = auth.uid()
          and mine.site_id = user_site_access.site_id
          and mine.can_manage = true
      )
      and user_site_access.role in ('technician', 'viewer', 'technician_request')
    )
  );

-- ---------------------------------------------------------------------------
-- Approve RPC: org-scoped + home_organization_id for super_admin
-- ---------------------------------------------------------------------------
create or replace function public.admin_approve_user(
  p_user_id uuid,
  p_role public.user_role,
  p_site_ids uuid[],
  p_note text default null,
  p_organization_id uuid default null
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
  v_home_org uuid;
  v_site_org uuid;
begin
  if v_actor is null then
    raise exception 'Not authenticated';
  end if;
  if p_user_id = v_actor then
    raise exception 'Users cannot approve themselves';
  end if;

  -- Role ceilings
  if p_role = 'super_admin' then
    if not public.is_platform_owner() then
      raise exception 'Only platform owner can approve as super_admin';
    end if;
    if p_organization_id is null then
      raise exception 'Organization required when approving super_admin';
    end if;
    v_home_org := p_organization_id;
  elsif p_role = 'site_admin' then
    if not (public.is_platform_owner() or public.is_super_admin()) then
      raise exception 'Only owner or super_admin can approve site_admin';
    end if;
  elsif p_role in ('technician', 'viewer') then
    if not (
      public.is_platform_owner()
      or public.is_super_admin()
      or public.is_site_admin()
    ) then
      raise exception 'Not allowed to approve role %', p_role;
    end if;
  else
    raise exception 'Invalid role for approval: %', p_role;
  end if;

  if p_role in ('technician', 'viewer', 'site_admin') then
    if p_site_ids is null or cardinality(p_site_ids) = 0 then
      raise exception 'Site assignment required for role %', p_role;
    end if;
  end if;

  -- Validate sites are within actor scope
  if p_site_ids is not null then
    foreach v_site_id in array p_site_ids loop
      select organization_id into v_site_org from public.sites where id = v_site_id;
      if v_site_org is null then
        raise exception 'Unknown site %', v_site_id;
      end if;
      if public.is_platform_owner() then
        null;
      elsif public.is_super_admin() then
        if v_site_org <> public.current_home_organization_id() then
          raise exception 'Site outside your organization';
        end if;
      elsif public.is_site_admin() then
        if not public.can_manage_site(v_site_id) then
          raise exception 'You cannot assign site %', v_site_id;
        end if;
        if p_role = 'site_admin' then
          raise exception 'Site admin cannot approve another site_admin';
        end if;
      end if;
    end loop;
  end if;

  if public.is_super_admin() and p_role = 'site_admin' then
    v_home_org := public.current_home_organization_id();
  end if;

  select approval_status into v_prev_status
  from public.profiles where id = p_user_id for update;
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
    home_organization_id = case
      when p_role = 'super_admin' then v_home_org
      when p_role = 'site_admin' then coalesce(
        v_home_org,
        (select s.organization_id from public.sites s where s.id = p_site_ids[1] limit 1)
      )
      else home_organization_id
    end,
    updated_at = now()
  where id = p_user_id;

  delete from public.user_site_access where user_id = p_user_id;

  if p_role = 'super_admin' then
    -- Grant all current sites in home org
    insert into public.user_site_access (user_id, site_id, role, can_read, can_write, can_manage)
    select p_user_id, s.id, 'super_admin', true, true, true
    from public.sites s
    where s.organization_id = v_home_org and s.is_active = true
    on conflict (user_id, site_id) do update set
      role = excluded.role,
      can_read = true,
      can_write = true,
      can_manage = true;
  elsif p_site_ids is not null then
    foreach v_site_id in array p_site_ids loop
      insert into public.user_site_access (user_id, site_id, role, can_read, can_write, can_manage)
      values (p_user_id, v_site_id, p_role, true, v_can_write, v_can_manage)
      on conflict (user_id, site_id) do update set
        role = excluded.role,
        can_read = true,
        can_write = excluded.can_write,
        can_manage = excluded.can_manage;
    end loop;
  end if;
end;
$$;

revoke all on function public.admin_approve_user(uuid, public.user_role, uuid[], text, uuid) from public;
grant execute on function public.admin_approve_user(uuid, public.user_role, uuid[], text, uuid) to authenticated;

-- Keep old 4-arg signature as wrapper for existing clients
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
as $$
begin
  perform public.admin_approve_user(p_user_id, p_role, p_site_ids, p_note, null);
end;
$$;

revoke all on function public.admin_approve_user(uuid, public.user_role, uuid[], text) from public;
grant execute on function public.admin_approve_user(uuid, public.user_role, uuid[], text) to authenticated;

-- Owner stays unbound; clear home org for platform owner profile
update public.profiles
set home_organization_id = null, updated_at = now()
where lower(trim(email)) = 'alikarim4r@gmail.com';

-- Bind existing non-owner super_admins to Awqaf org (org separation rollout)
update public.profiles
set
  home_organization_id = 'b0000000-0000-4000-8000-000000000001',
  updated_at = now()
where role = 'super_admin'
  and lower(trim(email)) <> 'alikarim4r@gmail.com'
  and home_organization_id is null
  and exists (
    select 1 from public.organizations o
    where o.id = 'b0000000-0000-4000-8000-000000000001'
  );

-- Pending users created by an org super_admin inherit that org so they stay visible.
create or replace function public.admin_create_user(
  p_email text,
  p_password text,
  p_full_name text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_user_id uuid := gen_random_uuid();
  v_email text := lower(trim(p_email));
  v_home uuid;
begin
  if not (public.is_platform_owner() or public.is_super_admin()) then
    raise exception 'Only platform owner / super_admin can create users';
  end if;

  if v_email is null or position('@' in v_email) < 2 then
    raise exception 'Invalid email address';
  end if;

  if coalesce(length(p_password), 0) < 8 then
    raise exception 'Password must be at least 8 characters';
  end if;

  if exists (select 1 from auth.users where lower(email) = v_email) then
    raise exception 'A user with this email already exists';
  end if;

  if public.is_super_admin() then
    v_home := public.current_home_organization_id();
    if v_home is null then
      raise exception 'Super admin must be bound to an organization';
    end if;
  end if;

  insert into auth.users (
    id,
    instance_id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at,
    confirmation_token,
    recovery_token,
    email_change_token_new,
    email_change
  )
  values (
    v_user_id,
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    v_email,
    extensions.crypt(p_password, extensions.gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object('full_name', coalesce(p_full_name, '')),
    now(),
    now(),
    '',
    '',
    '',
    ''
  );

  insert into auth.identities (
    id,
    user_id,
    provider_id,
    identity_data,
    provider,
    last_sign_in_at,
    created_at,
    updated_at
  )
  values (
    gen_random_uuid(),
    v_user_id,
    v_user_id::text,
    jsonb_build_object(
      'sub', v_user_id::text,
      'email', v_email,
      'email_verified', true
    ),
    'email',
    now(),
    now(),
    now()
  );

  -- handle_new_user trigger may have inserted profile; upsert to pending + home org
  insert into public.profiles (
    id,
    full_name,
    email,
    role,
    is_active,
    approval_status,
    home_organization_id
  )
  values (
    v_user_id,
    coalesce(nullif(trim(p_full_name), ''), split_part(v_email, '@', 1)),
    v_email,
    'viewer',
    false,
    'pending',
    v_home
  )
  on conflict (id) do update set
    full_name = excluded.full_name,
    email = excluded.email,
    role = 'viewer',
    is_active = false,
    approval_status = 'pending',
    home_organization_id = coalesce(public.profiles.home_organization_id, excluded.home_organization_id),
    updated_at = now();

  return v_user_id;
end;
$$;

revoke all on function public.admin_create_user(text, text, text) from public;
grant execute on function public.admin_create_user(text, text, text) to authenticated;

-- Status changes: owner anywhere; org super_admin within home org; site_admin on technicians
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
  v_target_home uuid;
begin
  if v_actor is null then
    raise exception 'Not authenticated';
  end if;

  if p_user_id = v_actor then
    raise exception 'Cannot change your own status here';
  end if;

  if p_status not in ('rejected', 'suspended', 'pending') then
    raise exception 'Invalid status for this RPC: %', p_status;
  end if;

  select role, lower(trim(email)), home_organization_id
  into v_target_role, v_target_email, v_target_home
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

  if public.is_platform_owner() then
    null;
  elsif public.is_super_admin() then
    if v_target_home is distinct from public.current_home_organization_id()
       and not exists (
         select 1
         from public.user_site_access usa
         join public.sites s on s.id = usa.site_id
         where usa.user_id = p_user_id
           and s.organization_id = public.current_home_organization_id()
       ) then
      raise exception 'User is outside your organization';
    end if;
  elsif public.is_site_admin() then
    if v_target_role not in ('technician', 'viewer', 'technician_request') then
      raise exception 'Site admin can only change technician/viewer status';
    end if;
    if not exists (
      select 1
      from public.user_site_access mine
      join public.user_site_access theirs on theirs.site_id = mine.site_id
      where mine.user_id = v_actor
        and mine.can_manage = true
        and theirs.user_id = p_user_id
    ) then
      raise exception 'User is outside your managed sites';
    end if;
  else
    raise exception 'Not allowed';
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
