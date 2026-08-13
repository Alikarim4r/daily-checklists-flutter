-- =============================================================================
-- Security hardening: immutable platform-owner identity + org-scoped checklist RLS
-- Migration: 019_security_hardening.sql
-- =============================================================================

-- Platform ownership is an explicit UUID membership. The email lookup below is
-- only a one-time migration bridge for the existing account; runtime checks never
-- trust public.profiles.email. On a fresh deployment, provision the Auth user and
-- insert its UUID into this table through the trusted SQL/service-role channel.
create table if not exists public.platform_owners (
  user_id uuid primary key references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);

comment on table public.platform_owners is
  'Platform-owner UUID membership. Manage only through trusted SQL/service role.';

alter table public.platform_owners enable row level security;

revoke all privileges on table public.platform_owners
  from public, anon, authenticated;

insert into public.platform_owners (user_id)
select u.id
from auth.users u
where lower(trim(u.email)) = 'alikarim4r@gmail.com'
on conflict (user_id) do nothing;

create or replace function public.is_platform_owner()
returns boolean
language sql
stable
security definer
set search_path = public
set row_security = off
as $$
  select auth.uid() is not null
    and exists (
      select 1
      from public.platform_owners po
      where po.user_id = auth.uid()
    );
$$;

comment on function public.is_platform_owner() is
  'True only when auth.uid() has protected platform-owner UUID membership.';

revoke all on function public.is_platform_owner() from public;
grant execute on function public.is_platform_owner() to authenticated;

-- The admin UI needs to mark owner rows, but the membership table itself remains
-- inaccessible. This function exposes only owner UUIDs to signed-in users.
create or replace function public.list_platform_owner_ids()
returns table (user_id uuid)
language sql
stable
security definer
set search_path = public
set row_security = off
as $$
  select po.user_id
  from public.platform_owners po
  where auth.uid() is not null;
$$;

revoke all on function public.list_platform_owner_ids() from public;
grant execute on function public.list_platform_owner_ids() to authenticated;

-- Repair any profile-email tampering and keep the display copy synchronized with
-- the authoritative Auth record. Profile email is no longer client-writable.
update public.profiles p
set email = u.email, updated_at = now()
from auth.users u
where u.id = p.id
  and p.email is distinct from u.email;

update public.profiles p
set
  role = 'super_admin',
  is_active = true,
  approval_status = 'approved',
  home_organization_id = null,
  updated_at = now()
from public.platform_owners po
where po.user_id = p.id;

create or replace function public.sync_profile_email_from_auth()
returns trigger
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
begin
  if new.email is distinct from old.email then
    update public.profiles
    set email = new.email, updated_at = now()
    where id = new.id;
  end if;
  return new;
end;
$$;

drop trigger if exists on_auth_user_email_updated on auth.users;
create trigger on_auth_user_email_updated
  after update of email on auth.users
  for each row execute function public.sync_profile_email_from_auth();

-- RLS controls rows, not columns. Remove table-level mutations and grant only the
-- harmless self-service column; administrative mutations continue through the
-- existing SECURITY DEFINER RPCs.
drop policy if exists profiles_update_own on public.profiles;
drop policy if exists profiles_update_own_safe on public.profiles;

revoke insert, update, delete on table public.profiles
  from public, anon, authenticated;
grant update (full_name) on table public.profiles to authenticated;

create policy profiles_update_own_safe on public.profiles
  for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

-- Defense in depth: an admin RPC invoked by a non-owner may never mutate or
-- delete an actual platform-owner profile.
create or replace function public.protect_platform_owner_profile()
returns trigger
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
begin
  if auth.uid() is not null
     and exists (
       select 1 from public.platform_owners po where po.user_id = old.id
     )
     and not public.is_platform_owner() then
    raise exception 'Platform owner profile can only be changed by a platform owner';
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_protect_platform_owner on public.profiles;
create trigger profiles_protect_platform_owner
  before update or delete on public.profiles
  for each row execute function public.protect_platform_owner_profile();

-- Replace the legacy email-based owner guard in the status RPC. Protection is
-- now based exclusively on the immutable UUID membership above.
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

  select role, home_organization_id
  into v_target_role, v_target_home
  from public.profiles
  where id = p_user_id
  for update;

  if not found then
    raise exception 'User not found';
  end if;
  if exists (
    select 1 from public.platform_owners owner_row
    where owner_row.user_id = p_user_id
  ) then
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
         from public.user_site_access access_row
         join public.sites site on site.id = access_row.site_id
         where access_row.user_id = p_user_id
           and site.organization_id = public.current_home_organization_id()
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

revoke all on function public.admin_set_user_status(
  uuid, public.approval_status, text
) from public;
grant execute on function public.admin_set_user_status(
  uuid, public.approval_status, text
) to authenticated;

-- ---------------------------------------------------------------------------
-- Checklist helpers and RLS. All elevated access is resolved through site/org
-- aware helpers; bare is_super_admin() is never a global bypass.
-- ---------------------------------------------------------------------------

create or replace function public.can_edit_checklist_inspection(
  p_inspection_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
set row_security = off
as $$
  select exists (
    select 1
    from public.checklist_inspections i
    where i.id = p_inspection_id
      and i.status = 'draft'
      and public.can_write_site(i.site_id)
  );
$$;

create or replace function public.can_admin_correct_checklist(p_site_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
set row_security = off
as $$
  select public.can_manage_site(p_site_id);
$$;

create or replace function public.can_delete_checklist_inspection(p_site_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
set row_security = off
as $$
  select public.is_platform_owner()
    or exists (
      select 1
      from public.sites s
      where s.id = p_site_id
        and public.is_org_super_admin(s.organization_id)
    );
$$;

revoke all on function public.can_edit_checklist_inspection(uuid) from public;
revoke all on function public.can_admin_correct_checklist(uuid) from public;
revoke all on function public.can_delete_checklist_inspection(uuid) from public;
grant execute on function public.can_edit_checklist_inspection(uuid) to authenticated;
grant execute on function public.can_admin_correct_checklist(uuid) to authenticated;
grant execute on function public.can_delete_checklist_inspection(uuid) to authenticated;

drop policy if exists checklist_inspections_select on public.checklist_inspections;
create policy checklist_inspections_select on public.checklist_inspections
  for select to authenticated
  using (public.has_site_access(site_id));

drop policy if exists checklist_inspections_insert on public.checklist_inspections;
create policy checklist_inspections_insert on public.checklist_inspections
  for insert to authenticated
  with check (
    (public.is_platform_owner() or public.is_approved_active_user())
    and public.can_write_site(site_id)
  );

drop policy if exists checklist_inspections_update on public.checklist_inspections;
create policy checklist_inspections_update on public.checklist_inspections
  for update to authenticated
  using (
    public.can_admin_correct_checklist(site_id)
    or (public.can_write_site(site_id) and status = 'draft')
  )
  with check (
    public.can_admin_correct_checklist(site_id)
    or public.can_write_site(site_id)
  );

drop policy if exists checklist_inspections_delete on public.checklist_inspections;
create policy checklist_inspections_delete on public.checklist_inspections
  for delete to authenticated
  using (public.can_delete_checklist_inspection(site_id));

drop policy if exists checklist_items_select on public.checklist_inspection_items;
create policy checklist_items_select on public.checklist_inspection_items
  for select to authenticated
  using (
    exists (
      select 1
      from public.checklist_inspections i
      where i.id = inspection_id
        and public.has_site_access(i.site_id)
    )
  );

drop policy if exists checklist_items_insert on public.checklist_inspection_items;
create policy checklist_items_insert on public.checklist_inspection_items
  for insert to authenticated
  with check (public.can_edit_checklist_inspection(inspection_id));

drop policy if exists checklist_items_update on public.checklist_inspection_items;
create policy checklist_items_update on public.checklist_inspection_items
  for update to authenticated
  using (
    public.can_edit_checklist_inspection(inspection_id)
    or exists (
      select 1
      from public.checklist_inspections i
      where i.id = inspection_id
        and public.can_admin_correct_checklist(i.site_id)
    )
  )
  with check (
    public.can_edit_checklist_inspection(inspection_id)
    or exists (
      select 1
      from public.checklist_inspections i
      where i.id = inspection_id
        and public.can_admin_correct_checklist(i.site_id)
    )
  );

drop policy if exists checklist_items_delete on public.checklist_inspection_items;
create policy checklist_items_delete on public.checklist_inspection_items
  for delete to authenticated
  using (
    public.can_edit_checklist_inspection(inspection_id)
    or exists (
      select 1
      from public.checklist_inspections i
      where i.id = inspection_id
        and public.can_admin_correct_checklist(i.site_id)
    )
  );

drop policy if exists checklist_corrections_select on public.checklist_corrections;
create policy checklist_corrections_select on public.checklist_corrections
  for select to authenticated
  using (
    exists (
      select 1
      from public.checklist_inspections i
      where i.id = inspection_id
        and public.can_admin_correct_checklist(i.site_id)
    )
  );

drop policy if exists checklist_corrections_insert on public.checklist_corrections;
create policy checklist_corrections_insert on public.checklist_corrections
  for insert to authenticated
  with check (
    corrected_by = auth.uid()
    and exists (
      select 1
      from public.checklist_inspections i
      where i.id = inspection_id
        and public.can_admin_correct_checklist(i.site_id)
    )
  );

-- Global templates are owner-managed; per-site and per-org settings are scoped.
drop policy if exists checklist_templates_write on public.checklist_templates;
create policy checklist_templates_write on public.checklist_templates
  for all to authenticated
  using (public.is_platform_owner())
  with check (public.is_platform_owner());

drop policy if exists checklist_template_items_write on public.checklist_template_items;
create policy checklist_template_items_write on public.checklist_template_items
  for all to authenticated
  using (public.is_platform_owner())
  with check (public.is_platform_owner());

drop policy if exists site_checklist_items_select on public.site_checklist_items;
create policy site_checklist_items_select on public.site_checklist_items
  for select to authenticated
  using (public.has_site_access(site_id));

drop policy if exists site_checklist_items_write on public.site_checklist_items;
create policy site_checklist_items_write on public.site_checklist_items
  for all to authenticated
  using (public.can_manage_site(site_id))
  with check (public.can_manage_site(site_id));

drop policy if exists checklist_org_policies_select on public.checklist_org_policies;
create policy checklist_org_policies_select on public.checklist_org_policies
  for select to authenticated
  using (public.can_access_organization(organization_id));

drop policy if exists checklist_org_policies_write on public.checklist_org_policies;
create policy checklist_org_policies_write on public.checklist_org_policies
  for all to authenticated
  using (
    public.is_platform_owner()
    or public.is_org_super_admin(organization_id)
  )
  with check (
    public.is_platform_owner()
    or public.is_org_super_admin(organization_id)
  );

-- Approval remains available to owner, the site's org admin, or a site admin
-- with can_manage on that site. A super admin from another organization fails
-- can_manage_site() and cannot cross the tenant boundary.
create or replace function public.admin_approve_inspection(
  p_inspection_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
declare
  v_site_id uuid;
begin
  if not (public.is_platform_owner() or public.is_approved_active_user()) then
    raise exception 'not allowed';
  end if;

  select site_id
  into v_site_id
  from public.checklist_inspections
  where id = p_inspection_id;

  if v_site_id is null then
    raise exception 'inspection not found';
  end if;

  if not public.can_manage_site(v_site_id) then
    raise exception 'not allowed to approve this inspection';
  end if;

  update public.checklist_inspections
  set
    review_status = 'approved',
    status = 'submitted',
    approved_at = now(),
    approved_by = auth.uid(),
    submitted_at = coalesce(submitted_at, now()),
    submitted_by = coalesce(submitted_by, auth.uid())
  where id = p_inspection_id;
end;
$$;

revoke all on function public.admin_approve_inspection(uuid) from public;
grant execute on function public.admin_approve_inspection(uuid) to authenticated;

create or replace function public.can_manage_report_logos(org_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
set row_security = off
as $$
  select public.is_platform_owner()
    or public.is_org_super_admin(org_id)
    or exists (
      select 1
      from public.user_site_access usa
      join public.sites s on s.id = usa.site_id
      where usa.user_id = auth.uid()
        and s.organization_id = org_id
        and usa.can_manage = true
    );
$$;

revoke all on function public.can_manage_report_logos(uuid) from public;
grant execute on function public.can_manage_report_logos(uuid) to authenticated;

drop policy if exists report_logos_select on storage.objects;
create policy report_logos_select on storage.objects
  for select to authenticated
  using (
    bucket_id = 'report-logos'
    and public.can_access_organization(public.report_logo_org_id(name))
  );
