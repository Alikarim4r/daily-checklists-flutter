-- GLOB-001 P1-00: archive entitlement enforced by privileged, scoped helper.
-- No archived content is returned by this helper; it only returns boolean.
-- Handles RLS on profiles without granting users read access to other profiles.
create or replace function public.can_read_global_library_revision(
  p_library_template_id uuid
)
returns boolean
language plpgsql stable
security definer
set search_path = public
set row_security = off
as $$
declare
  v_organization_id uuid;
begin
  if auth.uid() is null then return false; end if;
  if public.is_platform_owner() then return true; end if;
  if not coalesce(public.is_approved_active_user(),false) then return false; end if;
  select p.home_organization_id into v_organization_id
    from public.profiles p where p.id=auth.uid();
  if v_organization_id is null then return false; end if;
  return coalesce(public.can_access_library_template(
    p_library_template_id, v_organization_id
  ),false);
end;
$$;
revoke all on function public.can_read_global_library_revision(uuid)
  from public,anon;
grant execute on function public.can_read_global_library_revision(uuid)
  to authenticated;

drop policy if exists checklist_library_revisions_read
  on public.checklist_library_revisions;
create policy checklist_library_revisions_read
  on public.checklist_library_revisions
  for select to authenticated
  using (
    public.can_read_global_library_revision(library_template_id)
  );
comment on policy checklist_library_revisions_read
  on public.checklist_library_revisions is
  'GLOB-001: owner or active home-organization entitlement required for archived content, including revoked purchases.';
