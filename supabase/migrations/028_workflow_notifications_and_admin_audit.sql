-- =============================================================================
-- Extended workflow, relevant notifications, and administrative audit events
-- Migration: 028_workflow_notifications_and_admin_audit.sql
-- =============================================================================

alter type public.checklist_review_status add value if not exists 'returned';
alter type public.checklist_review_status add value if not exists 'rejected';
alter type public.checklist_review_status add value if not exists 'canceled';

alter table public.checklist_inspections
  add column if not exists workflow_note text,
  add column if not exists workflow_changed_at timestamptz,
  add column if not exists workflow_changed_by uuid;

create table if not exists public.checklist_notifications (
  id bigint generated always as identity primary key,
  user_id uuid not null,
  inspection_id uuid,
  site_id uuid,
  kind text not null,
  title_en text not null,
  title_ar text not null,
  body_en text not null default '',
  body_ar text not null default '',
  read_at timestamptz,
  created_at timestamptz not null default now(),
  constraint checklist_notifications_kind_not_blank
    check (length(trim(kind)) > 0)
);

create index if not exists checklist_notifications_user_unread_idx
  on public.checklist_notifications (user_id, created_at desc)
  where read_at is null;
create index if not exists checklist_notifications_inspection_idx
  on public.checklist_notifications (inspection_id, created_at desc)
  where inspection_id is not null;

alter table public.checklist_notifications enable row level security;
revoke all privileges on table public.checklist_notifications
  from public, anon, authenticated;
grant select on table public.checklist_notifications to authenticated;
grant update (read_at) on table public.checklist_notifications
  to authenticated;

drop policy if exists checklist_notifications_select_own
  on public.checklist_notifications;
create policy checklist_notifications_select_own
  on public.checklist_notifications
  for select to authenticated
  using (user_id = auth.uid());

drop policy if exists checklist_notifications_mark_read
  on public.checklist_notifications;
create policy checklist_notifications_mark_read
  on public.checklist_notifications
  for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create or replace function public.notify_checklist_workflow_change()
returns trigger
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
declare
  v_parent_site_id uuid;
begin
  if new.review_status is not distinct from old.review_status then
    return new;
  end if;

  select site.parent_site_id into v_parent_site_id
  from public.sites site where site.id = new.site_id;

  if new.review_status = 'submitted' then
    insert into public.checklist_notifications (
      user_id, inspection_id, site_id, kind,
      title_en, title_ar, body_en, body_ar
    )
    select distinct
      recipient.user_id,
      new.id,
      new.site_id,
      'inspection_submitted',
      'Inspection awaiting review',
      'فحص بانتظار المراجعة',
      new.building_code || ' · ' || new.inspector_name,
      new.building_code || ' · ' || new.inspector_name
    from (
      select access.user_id
      from public.user_site_access access
      join public.profiles profile on profile.id = access.user_id
      where access.can_manage = true
        and access.site_id in (new.site_id, v_parent_site_id)
        and profile.is_active = true
        and profile.approval_status = 'approved'
      union
      select owner_row.user_id from public.platform_owners owner_row
    ) recipient
    where recipient.user_id is distinct from auth.uid();
  elsif new.inspector_user_id is not null
        and new.review_status in ('approved', 'returned', 'rejected', 'canceled') then
    insert into public.checklist_notifications (
      user_id, inspection_id, site_id, kind,
      title_en, title_ar, body_en, body_ar
    ) values (
      new.inspector_user_id,
      new.id,
      new.site_id,
      'inspection_' || new.review_status::text,
      case new.review_status
        when 'approved' then 'Inspection approved'
        when 'returned' then 'Inspection returned for correction'
        when 'rejected' then 'Inspection rejected'
        else 'Inspection canceled'
      end,
      case new.review_status
        when 'approved' then 'تم اعتماد الفحص'
        when 'returned' then 'أُعيد الفحص للتصحيح'
        when 'rejected' then 'تم رفض الفحص'
        else 'تم إلغاء الفحص'
      end,
      coalesce(new.workflow_note, new.building_code),
      coalesce(new.workflow_note, new.building_code)
    );
  end if;
  return new;
end;
$$;

drop trigger if exists checklist_inspections_notify_workflow
  on public.checklist_inspections;
create trigger checklist_inspections_notify_workflow
  after update of review_status on public.checklist_inspections
  for each row execute function public.notify_checklist_workflow_change();

create or replace function public.manager_return_checklist_inspection(
  p_inspection_id uuid,
  p_expected_version bigint,
  p_reason text
)
returns bigint
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
  if nullif(trim(p_reason), '') is null then
    raise exception 'a reason is required to return an inspection';
  end if;
  select inspection.site_id, inspection.version, inspection.review_status
  into v_site_id, v_version, v_review_status
  from public.checklist_inspections inspection
  where inspection.id = p_inspection_id
  for update;
  if v_site_id is null then raise exception 'inspection not found'; end if;
  if p_expected_version is distinct from v_version then
    raise exception using errcode = '40001',
      message = 'inspection was changed by another session; reload and retry';
  end if;
  if v_review_status <> 'submitted' then
    raise exception 'only a submitted inspection can be returned';
  end if;
  if not public.can_manage_site(v_site_id) then
    raise exception 'not allowed to return this inspection';
  end if;

  perform set_config('app.audit_reason', trim(p_reason), true);
  update public.checklist_inspections
  set status = 'draft',
      review_status = 'returned',
      workflow_note = trim(p_reason),
      workflow_changed_at = now(),
      workflow_changed_by = auth.uid(),
      version = version + 1
  where id = p_inspection_id
  returning version into v_version;
  return v_version;
end;
$$;

revoke all on function public.manager_return_checklist_inspection(
  uuid, bigint, text
) from public;
grant execute on function public.manager_return_checklist_inspection(
  uuid, bigint, text
) to authenticated;

create or replace function public.manager_reject_checklist_inspection(
  p_inspection_id uuid,
  p_expected_version bigint,
  p_reason text
)
returns bigint
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
  if nullif(trim(p_reason), '') is null then
    raise exception 'a reason is required to reject an inspection';
  end if;
  select inspection.site_id, inspection.version, inspection.review_status
  into v_site_id, v_version, v_review_status
  from public.checklist_inspections inspection
  where inspection.id = p_inspection_id
  for update;
  if v_site_id is null then raise exception 'inspection not found'; end if;
  if p_expected_version is distinct from v_version then
    raise exception using errcode = '40001',
      message = 'inspection was changed by another session; reload and retry';
  end if;
  if v_review_status <> 'submitted' then
    raise exception 'only a submitted inspection can be rejected';
  end if;
  if not public.can_manage_site(v_site_id) then
    raise exception 'not allowed to reject this inspection';
  end if;

  perform set_config('app.audit_reason', trim(p_reason), true);
  update public.checklist_inspections
  set review_status = 'rejected',
      workflow_note = trim(p_reason),
      workflow_changed_at = now(),
      workflow_changed_by = auth.uid(),
      version = version + 1
  where id = p_inspection_id
  returning version into v_version;
  return v_version;
end;
$$;

revoke all on function public.manager_reject_checklist_inspection(
  uuid, bigint, text
) from public;
grant execute on function public.manager_reject_checklist_inspection(
  uuid, bigint, text
) to authenticated;

create or replace function public.owner_cancel_checklist_inspection(
  p_inspection_id uuid,
  p_expected_version bigint,
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
  if not public.is_platform_owner() then
    raise exception 'only the platform owner can cancel an inspection';
  end if;
  if nullif(trim(p_reason), '') is null then
    raise exception 'a reason is required to cancel an inspection';
  end if;
  select inspection.version, inspection.review_status
  into v_version, v_review_status
  from public.checklist_inspections inspection
  where inspection.id = p_inspection_id
  for update;
  if v_version is null then raise exception 'inspection not found'; end if;
  if p_expected_version is distinct from v_version then
    raise exception using errcode = '40001',
      message = 'inspection was changed by another session; reload and retry';
  end if;
  if v_review_status = 'approved' then
    raise exception 'approved inspections are immutable';
  end if;

  perform set_config('app.audit_reason', trim(p_reason), true);
  update public.checklist_inspections
  set status = 'submitted',
      review_status = 'canceled',
      workflow_note = trim(p_reason),
      workflow_changed_at = now(),
      workflow_changed_by = auth.uid(),
      version = version + 1
  where id = p_inspection_id
  returning version into v_version;
  return v_version;
end;
$$;

revoke all on function public.owner_cancel_checklist_inspection(
  uuid, bigint, text
) from public;
grant execute on function public.owner_cancel_checklist_inspection(
  uuid, bigint, text
) to authenticated;

-- Returned inspections are editable drafts and can be resubmitted. Other
-- workflow validation and optimistic locking remain identical to migration 020.
create or replace function public.submit_checklist_inspection(
  p_inspection_id uuid,
  p_expected_version bigint
)
returns bigint
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
declare
  v_site_id uuid;
  v_status public.checklist_inspection_status;
  v_review_status public.checklist_review_status;
  v_version bigint;
begin
  select inspection.site_id, inspection.status,
         inspection.review_status, inspection.version
  into v_site_id, v_status, v_review_status, v_version
  from public.checklist_inspections inspection
  where inspection.id = p_inspection_id
  for update;

  if v_site_id is null then raise exception 'inspection not found'; end if;
  if p_expected_version is distinct from v_version then
    raise exception using errcode = '40001',
      message = 'inspection was changed by another session; reload and retry';
  end if;
  if v_status <> 'draft' or v_review_status not in ('draft', 'returned') then
    raise exception 'only a draft or returned inspection can be submitted';
  end if;
  if not public.can_write_site(v_site_id) then
    raise exception 'not allowed to submit this inspection';
  end if;

  perform public.validate_checklist_inspection_for_submit(p_inspection_id);
  update public.checklist_inspections
  set status = 'submitted',
      review_status = 'submitted',
      submitted_at = now(),
      submitted_by = auth.uid(),
      workflow_note = null,
      workflow_changed_at = now(),
      workflow_changed_by = auth.uid(),
      version = version + 1
  where id = p_inspection_id
  returning version into v_version;
  return v_version;
end;
$$;

revoke all on function public.submit_checklist_inspection(uuid, bigint)
  from public;
grant execute on function public.submit_checklist_inspection(uuid, bigint)
  to authenticated;

-- Rejected and canceled records are terminal history, just like approved rows.
create or replace function public.guard_terminal_checklist_workflow()
returns trigger
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
begin
  if old.review_status in ('rejected', 'canceled') then
    raise exception 'terminal inspections are immutable';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

drop trigger if exists checklist_inspections_guard_terminal
  on public.checklist_inspections;
create trigger checklist_inspections_guard_terminal
  before update or delete on public.checklist_inspections
  for each row execute function public.guard_terminal_checklist_workflow();

create or replace function public.guard_terminal_checklist_item()
returns trigger
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
declare
  v_inspection_id uuid := case when tg_op = 'INSERT'
    then new.inspection_id else old.inspection_id end;
  v_review_status public.checklist_review_status;
begin
  select inspection.review_status into v_review_status
  from public.checklist_inspections inspection
  where inspection.id = v_inspection_id;
  if v_review_status in ('rejected', 'canceled') then
    raise exception 'terminal inspections are immutable';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

drop trigger if exists checklist_inspection_items_guard_terminal
  on public.checklist_inspection_items;
create trigger checklist_inspection_items_guard_terminal
  before insert or update or delete on public.checklist_inspection_items
  for each row execute function public.guard_terminal_checklist_item();

create or replace function public.record_session_audit(
  p_action text,
  p_metadata jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if p_action not in ('login', 'logout', 'biometric_unlock', 'session_refresh') then
    raise exception 'unsupported session audit action';
  end if;
  perform public.append_checklist_audit(
    'session.' || p_action,
    'session',
    auth.uid()::text,
    null,
    null,
    null,
    null,
    null,
    coalesce(p_metadata, '{}'::jsonb)
  );
end;
$$;

revoke all on function public.record_session_audit(text, jsonb) from public;
grant execute on function public.record_session_audit(text, jsonb)
  to authenticated;

-- One generic trigger covers the main administration/configuration tables.
create or replace function public.audit_checklist_admin_change()
returns trigger
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
declare
  v_old jsonb := case when tg_op = 'INSERT' then null else to_jsonb(old) end;
  v_new jsonb := case when tg_op = 'DELETE' then null else to_jsonb(new) end;
  v_row jsonb := coalesce(v_new, v_old);
  v_entity_id text := coalesce(v_row->>'id', v_row->>'organization_id');
  v_site_id uuid;
  v_org_id uuid;
begin
  if tg_table_name = 'sites' then
    v_site_id := nullif(v_row->>'id', '')::uuid;
    v_org_id := nullif(v_row->>'organization_id', '')::uuid;
  elsif tg_table_name in ('user_site_access', 'site_checklist_items') then
    v_site_id := nullif(v_row->>'site_id', '')::uuid;
    select site.organization_id into v_org_id
    from public.sites site where site.id = v_site_id;
  elsif tg_table_name = 'zones' then
    v_org_id := nullif(v_row->>'organization_id', '')::uuid;
  elsif tg_table_name in ('organizations', 'checklist_org_policies') then
    v_org_id := nullif(
      coalesce(v_row->>'id', v_row->>'organization_id'),
      ''
    )::uuid;
  end if;

  perform public.append_checklist_audit(
    'admin.' || tg_table_name || '.' || lower(tg_op),
    tg_table_name,
    v_entity_id,
    v_site_id,
    v_org_id,
    v_old,
    v_new,
    nullif(current_setting('app.audit_reason', true), ''),
    '{}'::jsonb
  );
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'profiles',
    'user_site_access',
    'organizations',
    'zones',
    'sites',
    'checklist_templates',
    'checklist_template_items',
    'site_checklist_items',
    'checklist_org_policies'
  ] loop
    execute format('drop trigger if exists %I on public.%I',
      'audit_' || v_table || '_change', v_table);
    execute format(
      'create trigger %I after insert or update or delete on public.%I '
      'for each row execute function public.audit_checklist_admin_change()',
      'audit_' || v_table || '_change', v_table
    );
  end loop;
end;
$$;

-- Replace the inspection audit mapper so the new workflow states are explicit.
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
    when new.review_status is distinct from old.review_status
      then 'inspection.' || new.review_status::text
    else 'inspection.updated'
  end;
  perform public.append_checklist_audit(
    v_action, 'inspection', v_row.id::text, v_row.site_id, v_org_id,
    case when tg_op = 'INSERT' then null else jsonb_build_object(
      'inspection_date', old.inspection_date,
      'status', old.status,
      'review_status', old.review_status,
      'version', old.version,
      'workflow_note', old.workflow_note
    ) end,
    case when tg_op = 'DELETE' then null else jsonb_build_object(
      'inspection_date', new.inspection_date,
      'status', new.status,
      'review_status', new.review_status,
      'version', new.version,
      'workflow_note', new.workflow_note
    ) end,
    v_reason,
    '{}'::jsonb
  );
  return v_row;
end;
$$;
