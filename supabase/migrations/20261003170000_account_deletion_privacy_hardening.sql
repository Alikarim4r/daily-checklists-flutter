-- Account deletion, privacy hardening, and unlinkable diagnostics.
-- Keeps immutable operational history while removing the deleted user's identity.

-- Historical rows must survive account deletion, but they must no longer block it.
alter table public.checklist_corrections
  alter column corrected_by drop not null;
alter table public.checklist_corrections
  drop constraint if exists checklist_corrections_corrected_by_fkey;
alter table public.checklist_corrections
  add constraint checklist_corrections_corrected_by_fkey
  foreign key (corrected_by) references public.profiles (id) on delete set null;

alter table public.checklist_corrective_actions
  alter column created_by drop not null;
alter table public.checklist_corrective_actions
  drop constraint if exists checklist_corrective_actions_created_by_fkey;
alter table public.checklist_corrective_actions
  add constraint checklist_corrective_actions_created_by_fkey
  foreign key (created_by) references public.profiles (id) on delete set null;

alter table public.checklist_corrective_action_comments
  alter column created_by drop not null;
alter table public.checklist_corrective_action_comments
  drop constraint if exists checklist_corrective_action_comments_created_by_fkey;
alter table public.checklist_corrective_action_comments
  add constraint checklist_corrective_action_comments_created_by_fkey
  foreign key (created_by) references public.profiles (id) on delete set null;

-- Diagnostics are useful without a durable account identifier.
alter table public.client_error_logs
  alter column user_id drop not null;
alter table public.client_error_logs
  drop constraint if exists client_error_logs_user_id_fkey;
alter table public.client_error_logs
  add constraint client_error_logs_user_id_fkey
  foreign key (user_id) references public.profiles (id) on delete set null;

update public.client_error_logs set user_id = null where user_id is not null;

create or replace function public.unlink_client_error_log_identity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  new.user_id := null;
  return new;
end;
$$;

drop trigger if exists client_error_logs_unlink_identity on public.client_error_logs;
create trigger client_error_logs_unlink_identity
  before insert or update of user_id on public.client_error_logs
  for each row execute function public.unlink_client_error_log_identity();

drop policy if exists client_error_logs_insert_own on public.client_error_logs;
create policy client_error_logs_insert_unlinked
  on public.client_error_logs for insert to authenticated
  with check (user_id is null);

-- Profile changes are audited without copying personal profile fields into the
-- immutable audit trail. Existing account-deletion cleanup below also scrubs
-- prior rows generated before this migration.
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
  v_row jsonb;
  v_entity_id text;
  v_site_id uuid;
  v_org_id uuid;
begin
  if tg_table_name = 'profiles' then
    v_old := v_old - 'id' - 'full_name' - 'email' - 'approval_note' - 'approved_by';
    v_new := v_new - 'id' - 'full_name' - 'email' - 'approval_note' - 'approved_by';
  end if;

  v_row := coalesce(v_new, v_old);
  v_entity_id := case
    when tg_table_name = 'profiles' then null
    else coalesce(v_row->>'id', v_row->>'organization_id')
  end;

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
    v_org_id := nullif(coalesce(v_row->>'id', v_row->>'organization_id'), '')::uuid;
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

-- Runs inside the same database transaction as the cascading profile deletion
-- caused by deleting auth.users. It removes direct identity while retaining the
-- operational inspection/audit evidence required for business integrity.
create or replace function public.prepare_profile_for_account_deletion()
returns trigger
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
declare
  v_user uuid := old.id;
  v_user_text text := old.id::text;
  v_deleted_label text := 'Deleted user';
begin
  -- Notifications sent to the account have no purpose after deletion.
  delete from public.checklist_notifications where user_id = v_user;

  -- Notifications sent to other reviewers may reference inspections completed
  -- by this user. Keep the event, but remove the display identity.
  update public.checklist_notifications n
  set body_en = coalesce(i.building_code, v_deleted_label),
      body_ar = coalesce(i.building_code, 'مستخدم محذوف')
  from public.checklist_inspections i
  where n.inspection_id = i.id
    and i.inspector_user_id = v_user;

  -- Preserve the business record while removing the account relationship/name.
  update public.checklist_inspections
  set inspector_user_id = null,
      inspector_name = v_deleted_label
  where inspector_user_id = v_user;

  -- Diagnostics are globally unlinked, but this also protects pre-migration rows.
  update public.client_error_logs set user_id = null where user_id = v_user;

  -- Remove direct actor identity and UUID/name/email copies from immutable audit
  -- JSON. The action itself remains available for governance and incident review.
  update public.checklist_audit_log
  set actor_user_id = null,
      actor_name = case when actor_user_id = v_user then v_deleted_label else actor_name end,
      entity_id = case when entity_id = v_user_text then null else entity_id end,
      old_value = case
        when entity_type = 'profiles' and (
          entity_id = v_user_text or coalesce(old_value->>'id', '') = v_user_text
        ) then null
        when old_value is null then null
        else replace(old_value::text, v_user_text, 'deleted-user')::jsonb
      end,
      new_value = case
        when entity_type = 'profiles' and (
          entity_id = v_user_text or coalesce(new_value->>'id', '') = v_user_text
        ) then null
        when new_value is null then null
        else replace(new_value::text, v_user_text, 'deleted-user')::jsonb
      end,
      metadata = replace(metadata::text, v_user_text, 'deleted-user')::jsonb
  where actor_user_id = v_user
     or entity_id = v_user_text
     or coalesce(old_value::text, '') like '%' || v_user_text || '%'
     or coalesce(new_value::text, '') like '%' || v_user_text || '%'
     or metadata::text like '%' || v_user_text || '%';

  return old;
end;
$$;

revoke all on function public.prepare_profile_for_account_deletion() from public, anon, authenticated;

drop trigger if exists profiles_prepare_account_deletion on public.profiles;
create trigger profiles_prepare_account_deletion
  before delete on public.profiles
  for each row execute function public.prepare_profile_for_account_deletion();
