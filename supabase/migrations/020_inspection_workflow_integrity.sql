-- =============================================================================
-- Atomic checklist workflow, optimistic locking, and server-side validation
-- Migration: 020_inspection_workflow_integrity.sql
-- =============================================================================

alter table public.checklist_inspections
  add column if not exists version bigint not null default 1,
  add column if not exists client_reference text;

create unique index if not exists checklist_inspections_client_reference_uidx
  on public.checklist_inspections (inspector_user_id, client_reference)
  where client_reference is not null;

alter table public.checklist_inspections
  drop constraint if exists checklist_inspections_version_positive;
alter table public.checklist_inspections
  add constraint checklist_inspections_version_positive check (version > 0);

-- Evidence must point to an object that actually exists below this inspection's
-- Storage prefix. Searching the serialized payload also supports legacy arrays
-- and the v2 issue/fix-pair JSON without trusting arbitrary non-empty text.
create or replace function public.checklist_has_storage_evidence(
  p_primary text,
  p_secondary text,
  p_prefix text
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
    from storage.objects o
    where o.bucket_id = 'checklist-media'
      and o.name like p_prefix || '%'
      and (
        position(o.name in coalesce(p_primary, '')) > 0
        or position(o.name in coalesce(p_secondary, '')) > 0
      )
  );
$$;

revoke all on function public.checklist_has_storage_evidence(text, text, text)
  from public;

create or replace function public.validate_checklist_inspection_for_submit(
  p_inspection_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, storage
set row_security = off
as $$
declare
  v_site_id uuid;
  v_org_id uuid;
  v_inspector_name text;
  v_inspection_time text;
  v_signature_path text;
  v_prefix text;
  v_photo_required boolean;
  v_photo_severity public.policy_severity;
  v_require_fix boolean;
  v_missing_indexes text;
begin
  select
    i.site_id,
    s.organization_id,
    i.inspector_name,
    i.inspection_time,
    i.signature_path
  into
    v_site_id,
    v_org_id,
    v_inspector_name,
    v_inspection_time,
    v_signature_path
  from public.checklist_inspections i
  join public.sites s on s.id = i.site_id
  where i.id = p_inspection_id;

  if v_site_id is null then
    raise exception 'inspection not found';
  end if;

  if nullif(trim(v_inspector_name), '') is null then
    raise exception 'inspector name is required';
  end if;
  if nullif(trim(v_inspection_time), '') is null then
    raise exception 'inspection time is required';
  end if;

  v_prefix := v_org_id::text || '/' || v_site_id::text || '/'
    || p_inspection_id::text || '/';

  if nullif(trim(v_signature_path), '') is null
     or v_signature_path not like v_prefix || '%'
     or not exists (
       select 1
       from storage.objects o
       where o.bucket_id = 'checklist-media'
         and o.name = v_signature_path
     ) then
    raise exception 'a valid signature is required before submit';
  end if;

  if not exists (
    select 1
    from public.checklist_inspection_items item
    where item.inspection_id = p_inspection_id
  ) then
    raise exception 'inspection must contain at least one item';
  end if;

  select string_agg(item.item_index::text, ', ' order by item.item_index)
  into v_missing_indexes
  from public.checklist_inspection_items item
  where item.inspection_id = p_inspection_id
    and item.response is null;

  if v_missing_indexes is not null then
    raise exception 'all checklist items must be answered; missing: %',
      v_missing_indexes;
  end if;

  select
    coalesce((
      select p.photo_required_on_problem
      from public.checklist_org_policies p
      where p.organization_id = v_org_id
    ), true),
    coalesce((
      select p.missing_photo_severity
      from public.checklist_org_policies p
      where p.organization_id = v_org_id
    ), 'critical'::public.policy_severity),
    coalesce((
      select p.require_fix_photo
      from public.checklist_org_policies p
      where p.organization_id = v_org_id
    ), false)
  into v_photo_required, v_photo_severity, v_require_fix;

  if v_photo_required and v_photo_severity = 'critical' then
    select string_agg(item.item_index::text, ', ' order by item.item_index)
    into v_missing_indexes
    from public.checklist_inspection_items item
    where item.inspection_id = p_inspection_id
      and item.response <> 'na'
      and (
        (upper(item.default_answer) = 'Y' and item.response = 'no')
        or (upper(item.default_answer) = 'N' and item.response = 'yes')
      )
      and not public.checklist_has_storage_evidence(
        item.issue_image_path,
        item.image_path,
        v_prefix
      );

    if v_missing_indexes is not null then
      raise exception 'problem photo required for items: %', v_missing_indexes;
    end if;
  end if;

  if v_require_fix then
    select string_agg(item.item_index::text, ', ' order by item.item_index)
    into v_missing_indexes
    from public.checklist_inspection_items item
    where item.inspection_id = p_inspection_id
      and item.response <> 'na'
      and (
        (upper(item.default_answer) = 'Y' and item.response = 'yes')
        or (upper(item.default_answer) = 'N' and item.response = 'no')
      )
      and public.checklist_has_storage_evidence(
        item.issue_image_path,
        item.image_path,
        v_prefix
      )
      and not public.checklist_has_storage_evidence(
        item.fix_image_path,
        null,
        v_prefix
      );

    if v_missing_indexes is not null then
      raise exception 'repair photo required for items: %', v_missing_indexes;
    end if;
  end if;
end;
$$;

revoke all on function public.validate_checklist_inspection_for_submit(uuid)
  from public;

create or replace function public.create_checklist_inspection_draft(
  p_site_id uuid,
  p_inspection_date date,
  p_inspector_name text,
  p_inspection_time text,
  p_floor_label text,
  p_items jsonb,
  p_client_reference text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
declare
  v_inspection_id uuid;
  v_building_code text;
  v_location text;
  v_checklist_type text;
  v_template_id uuid;
  v_template_max_index int;
  v_item_count int;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;
  if not public.can_write_site(p_site_id) then
    raise exception 'not allowed to create an inspection for this site';
  end if;
  if p_items is not null and jsonb_typeof(p_items) is distinct from 'array' then
    raise exception 'invalid inspection items payload';
  end if;

  if nullif(trim(p_client_reference), '') is not null then
    select i.id
    into v_inspection_id
    from public.checklist_inspections i
    where i.inspector_user_id = auth.uid()
      and i.client_reference = trim(p_client_reference)
    limit 1;
    if v_inspection_id is not null then
      return v_inspection_id;
    end if;
  end if;

  select
    s.building_code,
    s.location,
    coalesce(nullif(trim(s.checklist_type), ''), 'DEFAULT')
  into v_building_code, v_location, v_checklist_type
  from public.sites s
  where s.id = p_site_id
    and s.is_active = true;

  if nullif(trim(v_building_code), '') is null then
    raise exception 'site is inactive or is not a checklist unit';
  end if;

  begin
    insert into public.checklist_inspections (
      site_id,
      building_code,
      inspection_date,
      inspection_time,
      floor_label,
      location_label,
      inspector_name,
      inspector_user_id,
      status,
      review_status,
      version,
      client_reference
    )
    values (
      p_site_id,
      v_building_code,
      p_inspection_date,
      coalesce(trim(p_inspection_time), ''),
      coalesce(nullif(trim(p_floor_label), ''), 'ALL'),
      coalesce(nullif(trim(v_location), ''), 'MOEHE Permanent Headquarters'),
      coalesce(trim(p_inspector_name), ''),
      auth.uid(),
      'draft',
      'draft',
      1,
      nullif(trim(p_client_reference), '')
    )
    returning id into v_inspection_id;
  exception when unique_violation then
    if nullif(trim(p_client_reference), '') is null then
      raise;
    end if;
    select i.id
    into v_inspection_id
    from public.checklist_inspections i
    where i.inspector_user_id = auth.uid()
      and i.client_reference = trim(p_client_reference)
    limit 1;
    if v_inspection_id is null then
      raise;
    end if;
    return v_inspection_id;
  end;

  -- Static checklist metadata is copied from the server-side catalog. The
  -- caller cannot alter the expected answer to evade problem-photo rules.
  select t.id
  into v_template_id
  from public.checklist_templates t
  where t.code = v_checklist_type
    and t.is_active = true;

  if v_template_id is null then
    raise exception 'active checklist template % was not found',
      v_checklist_type;
  end if;

  insert into public.checklist_inspection_items (
    inspection_id,
    item_index,
    description,
    description_ar,
    default_answer,
    is_custom,
    overdue_after_days
  )
  select
    v_inspection_id,
    item.item_index,
    item.description_en,
    item.description_ar,
    item.default_answer,
    false,
    item.overdue_after_days
  from public.checklist_template_items item
  where item.template_id = v_template_id
    and item.is_active = true;

  select coalesce(max(item.item_index), 0)
  into v_template_max_index
  from public.checklist_template_items item
  where item.template_id = v_template_id
    and item.is_active = true;

  insert into public.checklist_inspection_items (
    inspection_id,
    item_index,
    description,
    description_ar,
    default_answer,
    is_custom,
    overdue_after_days
  )
  select
    v_inspection_id,
    (
      v_template_max_index
      + row_number() over (order by item.sort_order, item.item_index, item.id)
    )::int,
    item.description_en,
    item.description_ar,
    item.default_answer,
    true,
    item.overdue_after_days
  from public.site_checklist_items item
  where item.site_id = p_site_id
    and item.is_active = true;

  select count(*)
  into v_item_count
  from public.checklist_inspection_items item
  where item.inspection_id = v_inspection_id;
  if v_item_count = 0 then
    raise exception 'active checklist template % has no items',
      v_checklist_type;
  end if;

  return v_inspection_id;
end;
$$;

revoke all on function public.create_checklist_inspection_draft(
  uuid, date, text, text, text, jsonb, text
) from public;
grant execute on function public.create_checklist_inspection_draft(
  uuid, date, text, text, text, jsonb, text
) to authenticated;

create or replace function public.save_checklist_inspection(
  p_inspection_id uuid,
  p_expected_version bigint,
  p_header jsonb,
  p_items jsonb
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
  v_item jsonb;
  v_item_index int;
  v_item_exists boolean;
  v_requested_custom boolean;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  select i.site_id, i.status, i.review_status, i.version
  into v_site_id, v_status, v_review_status, v_version
  from public.checklist_inspections i
  where i.id = p_inspection_id
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
  if not (
    (v_status = 'draft' and public.can_write_site(v_site_id))
    or (v_review_status = 'submitted' and public.can_manage_site(v_site_id))
  ) then
    raise exception 'not allowed to edit this inspection';
  end if;
  if jsonb_typeof(p_header) is distinct from 'object'
     or jsonb_typeof(p_items) is distinct from 'array'
     or jsonb_array_length(p_items) = 0 then
    raise exception 'invalid inspection payload';
  end if;

  update public.checklist_inspections
  set
    inspector_name = case
      when p_header ? 'inspector_name'
        then coalesce(p_header->>'inspector_name', '')
      else inspector_name
    end,
    inspection_time = case
      when p_header ? 'inspection_time'
        then coalesce(p_header->>'inspection_time', '')
      else inspection_time
    end,
    floor_label = case
      when p_header ? 'floor_label'
        then coalesce(nullif(p_header->>'floor_label', ''), 'ALL')
      else floor_label
    end,
    signature_path = case
      when p_header ? 'signature_path'
        then nullif(p_header->>'signature_path', '')
      else signature_path
    end
  where id = p_inspection_id;

  for v_item in select value from jsonb_array_elements(p_items) loop
    v_item_index := nullif(v_item->>'item_index', '')::int;
    if v_item_index is null or v_item_index < 1 then
      raise exception 'invalid checklist item index';
    end if;
    select exists (
      select 1
      from public.checklist_inspection_items existing
      where existing.inspection_id = p_inspection_id
        and existing.item_index = v_item_index
    ) into v_item_exists;
    v_requested_custom := coalesce((v_item->>'is_custom')::boolean, false);
    if not v_item_exists and (
      not v_requested_custom or not public.can_manage_site(v_site_id)
    ) then
      raise exception 'only site managers can add custom inspection items';
    end if;

    insert into public.checklist_inspection_items (
      inspection_id,
      item_index,
      description,
      description_ar,
      response,
      actions_taken,
      image_path,
      issue_image_path,
      fix_image_path,
      default_answer,
      is_custom,
      overdue_after_days
    )
    values (
      p_inspection_id,
      v_item_index,
      coalesce(nullif(trim(v_item->>'description'), ''), 'Item ' || v_item_index),
      nullif(trim(v_item->>'description_ar'), ''),
      nullif(v_item->>'response', '')::public.checklist_response,
      coalesce(v_item->>'actions_taken', ''),
      nullif(v_item->>'image_path', ''),
      nullif(v_item->>'issue_image_path', ''),
      nullif(v_item->>'fix_image_path', ''),
      case upper(coalesce(v_item->>'default_answer', 'Y'))
        when 'N' then 'N'
        else 'Y'
      end,
      coalesce((v_item->>'is_custom')::boolean, false),
      greatest(0, coalesce((v_item->>'overdue_after_days')::int, 3))
    )
    on conflict (inspection_id, item_index) do update set
      description = public.checklist_inspection_items.description,
      description_ar = public.checklist_inspection_items.description_ar,
      response = excluded.response,
      actions_taken = excluded.actions_taken,
      image_path = excluded.image_path,
      issue_image_path = excluded.issue_image_path,
      fix_image_path = excluded.fix_image_path,
      default_answer = public.checklist_inspection_items.default_answer,
      overdue_after_days = public.checklist_inspection_items.overdue_after_days;
  end loop;

  update public.checklist_inspections
  set version = version + 1
  where id = p_inspection_id
  returning version into v_version;

  return v_version;
end;
$$;

revoke all on function public.save_checklist_inspection(
  uuid, bigint, jsonb, jsonb
) from public;
grant execute on function public.save_checklist_inspection(
  uuid, bigint, jsonb, jsonb
) to authenticated;

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
  select i.site_id, i.status, i.review_status, i.version
  into v_site_id, v_status, v_review_status, v_version
  from public.checklist_inspections i
  where i.id = p_inspection_id
  for update;

  if v_site_id is null then
    raise exception 'inspection not found';
  end if;
  if p_expected_version is distinct from v_version then
    raise exception using
      errcode = '40001',
      message = 'inspection was changed by another session; reload and retry';
  end if;
  if v_status <> 'draft' or v_review_status <> 'draft' then
    raise exception 'only a draft inspection can be submitted';
  end if;
  if not public.can_write_site(v_site_id) then
    raise exception 'not allowed to submit this inspection';
  end if;

  perform public.validate_checklist_inspection_for_submit(p_inspection_id);

  update public.checklist_inspections
  set
    status = 'submitted',
    review_status = 'submitted',
    submitted_at = now(),
    submitted_by = auth.uid(),
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

drop function if exists public.admin_approve_inspection(uuid);
create or replace function public.admin_approve_inspection(
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
  select i.site_id, i.status, i.review_status, i.version
  into v_site_id, v_status, v_review_status, v_version
  from public.checklist_inspections i
  where i.id = p_inspection_id
  for update;

  if v_site_id is null then
    raise exception 'inspection not found';
  end if;
  if p_expected_version is distinct from v_version then
    raise exception using
      errcode = '40001',
      message = 'inspection was changed by another session; reload and retry';
  end if;
  if v_status <> 'submitted' or v_review_status <> 'submitted' then
    raise exception 'only a submitted inspection can be approved';
  end if;
  if not public.can_manage_site(v_site_id) then
    raise exception 'not allowed to approve this inspection';
  end if;

  perform public.validate_checklist_inspection_for_submit(p_inspection_id);

  update public.checklist_inspections
  set
    review_status = 'approved',
    approved_at = now(),
    approved_by = auth.uid(),
    version = version + 1
  where id = p_inspection_id
  returning version into v_version;

  return v_version;
end;
$$;

revoke all on function public.admin_approve_inspection(uuid, bigint)
  from public;
grant execute on function public.admin_approve_inspection(uuid, bigint)
  to authenticated;

create or replace function public.correct_checklist_inspection_item(
  p_item_id uuid,
  p_expected_version bigint,
  p_field_name text,
  p_new_value text,
  p_reason text default ''
)
returns bigint
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
declare
  v_inspection_id uuid;
  v_site_id uuid;
  v_review_status public.checklist_review_status;
  v_version bigint;
  v_old_value text;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  select
    item.inspection_id,
    i.site_id,
    i.review_status,
    i.version,
    case p_field_name
      when 'response' then item.response::text
      when 'actions_taken' then item.actions_taken
      when 'image_path' then item.image_path
      when 'issue_image_path' then item.issue_image_path
      when 'fix_image_path' then item.fix_image_path
      else null
    end
  into
    v_inspection_id,
    v_site_id,
    v_review_status,
    v_version,
    v_old_value
  from public.checklist_inspection_items item
  join public.checklist_inspections i on i.id = item.inspection_id
  where item.id = p_item_id
  for update of i;

  if v_inspection_id is null then
    raise exception 'inspection item not found';
  end if;
  if p_field_name is null or p_field_name not in (
    'response',
    'actions_taken',
    'image_path',
    'issue_image_path',
    'fix_image_path'
  ) then
    raise exception 'field cannot be corrected';
  end if;
  if p_expected_version is distinct from v_version then
    raise exception using
      errcode = '40001',
      message = 'inspection was changed by another session; reload and retry';
  end if;
  if v_review_status = 'approved' then
    raise exception 'approved inspections are immutable';
  end if;
  if not public.can_manage_site(v_site_id) then
    raise exception 'not allowed to correct this inspection';
  end if;
  if p_field_name = 'response'
     and p_new_value is not null
     and p_new_value not in ('yes', 'no', 'na') then
    raise exception 'invalid checklist response';
  end if;

  update public.checklist_inspection_items item
  set
    response = case
      when p_field_name = 'response'
        then nullif(p_new_value, '')::public.checklist_response
      else item.response
    end,
    actions_taken = case
      when p_field_name = 'actions_taken' then coalesce(p_new_value, '')
      else item.actions_taken
    end,
    image_path = case
      when p_field_name = 'image_path' then nullif(p_new_value, '')
      else item.image_path
    end,
    issue_image_path = case
      when p_field_name = 'issue_image_path' then nullif(p_new_value, '')
      else item.issue_image_path
    end,
    fix_image_path = case
      when p_field_name = 'fix_image_path' then nullif(p_new_value, '')
      else item.fix_image_path
    end
  where item.id = p_item_id;

  insert into public.checklist_corrections (
    inspection_id,
    item_id,
    field_name,
    old_value,
    new_value,
    reason,
    corrected_by
  )
  values (
    v_inspection_id,
    p_item_id,
    p_field_name,
    v_old_value,
    p_new_value,
    coalesce(p_reason, ''),
    auth.uid()
  );

  update public.checklist_inspections
  set version = version + 1
  where id = v_inspection_id
  returning version into v_version;
  return v_version;
end;
$$;

revoke all on function public.correct_checklist_inspection_item(
  uuid, bigint, text, text, text
) from public;
grant execute on function public.correct_checklist_inspection_item(
  uuid, bigint, text, text, text
) to authenticated;

create or replace function public.delete_checklist_inspection_item(
  p_item_id uuid,
  p_expected_version bigint
)
returns bigint
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
declare
  v_inspection_id uuid;
  v_site_id uuid;
  v_status public.checklist_inspection_status;
  v_review_status public.checklist_review_status;
  v_version bigint;
  v_is_custom boolean;
begin
  select
    item.inspection_id,
    item.is_custom,
    i.site_id,
    i.status,
    i.review_status,
    i.version
  into
    v_inspection_id,
    v_is_custom,
    v_site_id,
    v_status,
    v_review_status,
    v_version
  from public.checklist_inspection_items item
  join public.checklist_inspections i on i.id = item.inspection_id
  where item.id = p_item_id
  for update of i;

  if v_inspection_id is null then
    raise exception 'inspection item not found';
  end if;
  if not v_is_custom then
    raise exception 'catalog items cannot be deleted from an inspection';
  end if;
  if p_expected_version is distinct from v_version then
    raise exception using
      errcode = '40001',
      message = 'inspection was changed by another session; reload and retry';
  end if;
  if v_review_status = 'approved' then
    raise exception 'approved inspections are immutable';
  end if;
  if not public.can_manage_site(v_site_id) then
    raise exception 'not allowed to delete this item';
  end if;

  delete from public.checklist_inspection_items where id = p_item_id;
  update public.checklist_inspections
  set version = version + 1
  where id = v_inspection_id
  returning version into v_version;
  return v_version;
end;
$$;

revoke all on function public.delete_checklist_inspection_item(uuid, bigint)
  from public;
grant execute on function public.delete_checklist_inspection_item(uuid, bigint)
  to authenticated;

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
begin
  select i.site_id, i.version
  into v_site_id, v_version
  from public.checklist_inspections i
  where i.id = p_inspection_id
  for update;

  if v_site_id is null then
    raise exception 'inspection not found';
  end if;
  if p_expected_version is distinct from v_version then
    raise exception using
      errcode = '40001',
      message = 'inspection was changed by another session; reload and retry';
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

-- The public API is now read-only for workflow tables. All mutations above run
-- as SECURITY DEFINER and validate row scope, state transition, and version.
revoke insert, update, delete on table public.checklist_inspections
  from public, anon, authenticated;
revoke insert, update, delete on table public.checklist_inspection_items
  from public, anon, authenticated;
revoke insert, update, delete on table public.checklist_corrections
  from public, anon, authenticated;
