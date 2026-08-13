-- =============================================================================
-- Critical production guardrails and append-only audit trail
-- Migration: 027_critical_guardrails_and_audit.sql
-- =============================================================================

-- Audit rows deliberately do not use cascading foreign keys. An audit event
-- must survive the later removal of the actor or the business record itself.
create table if not exists public.checklist_audit_log (
  id bigint generated always as identity primary key,
  actor_user_id uuid,
  actor_name text,
  actor_role text,
  action text not null,
  entity_type text not null,
  entity_id text,
  organization_id uuid,
  site_id uuid,
  old_value jsonb,
  new_value jsonb,
  reason text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint checklist_audit_log_action_not_blank
    check (length(trim(action)) > 0),
  constraint checklist_audit_log_entity_not_blank
    check (length(trim(entity_type)) > 0)
);

create index if not exists checklist_audit_log_created_idx
  on public.checklist_audit_log (created_at desc);
create index if not exists checklist_audit_log_entity_idx
  on public.checklist_audit_log (entity_type, entity_id, created_at desc);
create index if not exists checklist_audit_log_site_idx
  on public.checklist_audit_log (site_id, created_at desc)
  where site_id is not null;
create index if not exists checklist_audit_log_actor_idx
  on public.checklist_audit_log (actor_user_id, created_at desc)
  where actor_user_id is not null;

alter table public.checklist_audit_log enable row level security;

revoke all privileges on table public.checklist_audit_log
  from public, anon, authenticated;
grant select on table public.checklist_audit_log to authenticated;

drop policy if exists checklist_audit_log_select on public.checklist_audit_log;
create policy checklist_audit_log_select on public.checklist_audit_log
  for select to authenticated
  using (
    public.is_platform_owner()
    or (site_id is not null and public.can_manage_site(site_id))
  );

-- Only trusted trigger/RPC code may append audit events. It snapshots actor
-- display data so later profile edits cannot rewrite history.
create or replace function public.append_checklist_audit(
  p_action text,
  p_entity_type text,
  p_entity_id text default null,
  p_site_id uuid default null,
  p_organization_id uuid default null,
  p_old_value jsonb default null,
  p_new_value jsonb default null,
  p_reason text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
declare
  v_actor uuid := auth.uid();
  v_actor_name text;
  v_actor_role text;
begin
  select profile.full_name, profile.role::text
  into v_actor_name, v_actor_role
  from public.profiles profile
  where profile.id = v_actor;

  insert into public.checklist_audit_log (
    actor_user_id,
    actor_name,
    actor_role,
    action,
    entity_type,
    entity_id,
    organization_id,
    site_id,
    old_value,
    new_value,
    reason,
    metadata
  ) values (
    v_actor,
    v_actor_name,
    v_actor_role,
    trim(p_action),
    trim(p_entity_type),
    p_entity_id,
    p_organization_id,
    p_site_id,
    p_old_value,
    p_new_value,
    nullif(trim(p_reason), ''),
    coalesce(p_metadata, '{}'::jsonb)
  );
end;
$$;

revoke all on function public.append_checklist_audit(
  text, text, text, uuid, uuid, jsonb, jsonb, text, jsonb
) from public, anon, authenticated;

-- Return true only when a real Storage object referenced by the old serialized
-- evidence value disappeared from the new value. This supports legacy strings,
-- JSON arrays, and the v2 issue/fix-pair JSON without trusting the client.
create or replace function public.checklist_stored_evidence_removed(
  p_old_value text,
  p_new_value text,
  p_storage_prefix text
)
returns boolean
language sql
stable
security definer
set search_path = public, storage
set row_security = off
as $$
  select exists (
    select 1
    from storage.objects object
    where object.bucket_id = 'checklist-media'
      and object.name like p_storage_prefix || '%'
      and position(object.name in coalesce(p_old_value, '')) > 0
      and position(object.name in coalesce(p_new_value, '')) = 0
  );
$$;

revoke all on function public.checklist_stored_evidence_removed(
  text, text, text
) from public, anon, authenticated;

-- Database-level invariants. They protect the records even if a future client
-- or SECURITY DEFINER RPC accidentally omits one of these checks.
create or replace function public.guard_checklist_inspection_mutation()
returns trigger
language plpgsql
security definer
set search_path = public, storage
set row_security = off
as $$
declare
  v_org_id uuid;
  v_prefix text;
begin
  if tg_op = 'DELETE' then
    if old.review_status = 'approved' then
      raise exception 'approved inspections are immutable';
    end if;
    return old;
  end if;

  if new.inspection_date > public.current_business_date() then
    raise exception 'future inspection dates are not allowed';
  end if;

  if tg_op = 'UPDATE' then
    if old.review_status = 'approved' then
      raise exception 'approved inspections are immutable';
    end if;
    if new.inspection_date is distinct from old.inspection_date
       and not public.is_platform_owner() then
      raise exception 'only the platform owner can change an inspection date';
    end if;

    select site.organization_id
    into v_org_id
    from public.sites site
    where site.id = old.site_id;
    v_prefix := v_org_id::text || '/' || old.site_id::text || '/'
      || old.id::text || '/';

    if not public.can_manage_site(old.site_id)
       and public.checklist_stored_evidence_removed(
         old.signature_path,
         new.signature_path,
         v_prefix
       ) then
      raise exception 'stored signature evidence can only be removed by a manager';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists checklist_inspections_guard_mutation
  on public.checklist_inspections;
create trigger checklist_inspections_guard_mutation
  before insert or update or delete on public.checklist_inspections
  for each row execute function public.guard_checklist_inspection_mutation();

create or replace function public.guard_checklist_item_mutation()
returns trigger
language plpgsql
security definer
set search_path = public, storage
set row_security = off
as $$
declare
  v_inspection_id uuid;
  v_site_id uuid;
  v_org_id uuid;
  v_review_status public.checklist_review_status;
  v_prefix text;
  v_old_evidence text;
  v_new_evidence text;
begin
  v_inspection_id := case when tg_op = 'INSERT' then new.inspection_id
    else old.inspection_id end;

  select inspection.site_id, site.organization_id, inspection.review_status
  into v_site_id, v_org_id, v_review_status
  from public.checklist_inspections inspection
  join public.sites site on site.id = inspection.site_id
  where inspection.id = v_inspection_id;

  -- Cascading cleanup of a non-approved parent can reach this trigger after the
  -- parent is no longer visible. The parent guard already authorized that path.
  if v_site_id is null then
    return case when tg_op = 'DELETE' then old else new end;
  end if;

  if v_review_status = 'approved' then
    raise exception 'approved inspections are immutable';
  end if;

  if tg_op = 'UPDATE' and not public.can_manage_site(v_site_id) then
    v_prefix := v_org_id::text || '/' || v_site_id::text || '/'
      || v_inspection_id::text || '/';
    v_old_evidence := concat_ws('|',
      old.image_path, old.issue_image_path, old.fix_image_path
    );
    v_new_evidence := concat_ws('|',
      new.image_path, new.issue_image_path, new.fix_image_path
    );
    if public.checklist_stored_evidence_removed(
      v_old_evidence,
      v_new_evidence,
      v_prefix
    ) then
      raise exception 'stored photo evidence can only be removed by a manager';
    end if;
  end if;

  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

drop trigger if exists checklist_inspection_items_guard_mutation
  on public.checklist_inspection_items;
create trigger checklist_inspection_items_guard_mutation
  before insert or update or delete on public.checklist_inspection_items
  for each row execute function public.guard_checklist_item_mutation();

-- A technician may upload new draft evidence but cannot delete a stored object.
-- Managers retain deletion rights only until the inspection is approved.
create or replace function public.can_delete_checklist_media(path text)
returns boolean
language sql
stable
security definer
set search_path = public
set row_security = off
as $$
  select
    auth.uid() is not null
    and public.storage_path_valid(path)
    and exists (
      select 1
      from public.checklist_inspections inspection
      where inspection.id = public.storage_path_inspection_id(path)
        and inspection.site_id = public.storage_path_site_id(path)
        and inspection.review_status <> 'approved'
        and public.can_manage_site(inspection.site_id)
    );
$$;

revoke all on function public.can_delete_checklist_media(text) from public;
grant execute on function public.can_delete_checklist_media(text)
  to authenticated;

-- Record the actual Storage deletion. This remains effective when an authorized
-- manager calls the Storage API directly instead of going through app UI code.
create or replace function public.audit_checklist_media_delete()
returns trigger
language plpgsql
security definer
set search_path = public, storage
set row_security = off
as $$
begin
  if old.bucket_id = 'checklist-media' then
    perform public.append_checklist_audit(
      'evidence.deleted',
      'storage_object',
      old.name,
      public.storage_path_site_id(old.name),
      public.storage_path_organization_id(old.name),
      jsonb_build_object('path', old.name, 'bucket', old.bucket_id),
      null,
      null,
      jsonb_build_object(
        'inspection_id', public.storage_path_inspection_id(old.name)
      )
    );
  end if;
  return old;
end;
$$;

drop trigger if exists checklist_media_audit_delete on storage.objects;
create trigger checklist_media_audit_delete
  after delete on storage.objects
  for each row execute function public.audit_checklist_media_delete();

create or replace function public.audit_checklist_inspection_change()
returns trigger
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
declare
  v_row public.checklist_inspections%rowtype;
  v_org_id uuid;
  v_action text;
  v_reason text := nullif(current_setting('app.audit_reason', true), '');
begin
  v_row := case when tg_op = 'DELETE' then old else new end;
  select site.organization_id into v_org_id
  from public.sites site where site.id = v_row.site_id;

  v_action := case
    when tg_op = 'INSERT' then 'inspection.created'
    when tg_op = 'DELETE' then 'inspection.deleted'
    when new.inspection_date is distinct from old.inspection_date
      then 'inspection.date_changed'
    when new.review_status = 'approved' and old.review_status <> 'approved'
      then 'inspection.approved'
    when new.review_status = 'submitted' and old.review_status <> 'submitted'
      then 'inspection.submitted'
    else 'inspection.updated'
  end;

  perform public.append_checklist_audit(
    v_action,
    'inspection',
    v_row.id::text,
    v_row.site_id,
    v_org_id,
    case when tg_op = 'INSERT' then null else jsonb_build_object(
      'inspection_date', old.inspection_date,
      'status', old.status,
      'review_status', old.review_status,
      'version', old.version,
      'signature_path', old.signature_path
    ) end,
    case when tg_op = 'DELETE' then null else jsonb_build_object(
      'inspection_date', new.inspection_date,
      'status', new.status,
      'review_status', new.review_status,
      'version', new.version,
      'signature_path', new.signature_path
    ) end,
    v_reason,
    '{}'::jsonb
  );
  return v_row;
end;
$$;

drop trigger if exists checklist_inspections_audit_change
  on public.checklist_inspections;
create trigger checklist_inspections_audit_change
  after insert or update or delete on public.checklist_inspections
  for each row execute function public.audit_checklist_inspection_change();

create or replace function public.audit_checklist_item_change()
returns trigger
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
declare
  v_row public.checklist_inspection_items%rowtype;
  v_site_id uuid;
  v_org_id uuid;
begin
  v_row := case when tg_op = 'DELETE' then old else new end;
  select inspection.site_id, site.organization_id
  into v_site_id, v_org_id
  from public.checklist_inspections inspection
  join public.sites site on site.id = inspection.site_id
  where inspection.id = v_row.inspection_id;

  perform public.append_checklist_audit(
    'inspection_item.' || lower(tg_op),
    'inspection_item',
    v_row.id::text,
    v_site_id,
    v_org_id,
    case when tg_op = 'INSERT' then null else to_jsonb(old) end,
    case when tg_op = 'DELETE' then null else to_jsonb(new) end,
    nullif(current_setting('app.audit_reason', true), ''),
    jsonb_build_object('inspection_id', v_row.inspection_id)
  );
  return v_row;
end;
$$;

drop trigger if exists checklist_inspection_items_audit_change
  on public.checklist_inspection_items;
create trigger checklist_inspection_items_audit_change
  after insert or update or delete on public.checklist_inspection_items
  for each row execute function public.audit_checklist_item_change();

-- Owner-only correction of a date. The optimistic version and mandatory reason
-- make the operation explicit and auditable; approved records remain locked.
create or replace function public.owner_change_inspection_date(
  p_inspection_id uuid,
  p_expected_version bigint,
  p_new_date date,
  p_reason text
)
returns bigint
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
declare
  v_version bigint;
  v_review_status public.checklist_review_status;
begin
  if auth.uid() is null or not public.is_platform_owner() then
    raise exception 'only the platform owner can change an inspection date';
  end if;
  if p_new_date is null or p_new_date > public.current_business_date() then
    raise exception 'future inspection dates are not allowed';
  end if;
  if nullif(trim(p_reason), '') is null then
    raise exception 'a reason is required to change an inspection date';
  end if;

  select inspection.version, inspection.review_status
  into v_version, v_review_status
  from public.checklist_inspections inspection
  where inspection.id = p_inspection_id
  for update;

  if v_version is null then
    raise exception 'inspection not found';
  end if;
  if p_expected_version is distinct from v_version then
    raise exception using
      errcode = '40001',
      message = 'inspection was changed by another session; reload and retry';
  end if;
  if v_review_status = 'approved' then
    raise exception 'approved inspections are immutable';
  end if;

  perform set_config('app.audit_reason', trim(p_reason), true);
  update public.checklist_inspections
  set inspection_date = p_new_date, version = version + 1
  where id = p_inspection_id
  returning version into v_version;
  return v_version;
end;
$$;

revoke all on function public.owner_change_inspection_date(
  uuid, bigint, date, text
) from public;
grant execute on function public.owner_change_inspection_date(
  uuid, bigint, date, text
) to authenticated;

-- Make the existing delete RPC obey the approved-record preservation rule even
-- before its DELETE reaches the defense-in-depth trigger.
create or replace function public.delete_checklist_inspection(
  p_inspection_id uuid,
  p_expected_version bigint
)
returns void
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
declare
  v_site_id uuid;
  v_version bigint;
  v_review_status public.checklist_review_status;
begin
  select inspection.site_id, inspection.version, inspection.review_status
  into v_site_id, v_version, v_review_status
  from public.checklist_inspections inspection
  where inspection.id = p_inspection_id
  for update;

  if v_site_id is null then
    raise exception 'inspection not found';
  end if;
  if p_expected_version is distinct from v_version then
    raise exception using
      errcode = '40001',
      message = 'inspection was changed by another session; reload and retry';
  end if;
  if v_review_status = 'approved' then
    raise exception 'approved inspections are immutable';
  end if;
  if not public.can_delete_checklist_inspection(v_site_id) then
    raise exception 'not allowed to delete this inspection';
  end if;

  delete from public.checklist_inspections where id = p_inspection_id;
end;
$$;

revoke all on function public.delete_checklist_inspection(uuid, bigint)
  from public;
grant execute on function public.delete_checklist_inspection(uuid, bigint)
  to authenticated;

