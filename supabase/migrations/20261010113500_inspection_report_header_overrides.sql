-- Allow editing report header labels while an inspection is an editable draft.
-- Does not modify public.sites or the canonical hierarchy, and preserves
-- the version check, reviewer workflow and approved-report immutability.
-- NULL pin_override reads the existing site PIN for historical rows.
alter table public.checklist_inspections
  add column if not exists pin_override text;

comment on column public.checklist_inspections.pin_override is
  'Inspection-specific printable PIN; NULL falls back to sites.pin; independent of master site';

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
    v_status = 'draft'
    and v_review_status in ('draft', 'returned')
    and public.can_write_site(v_site_id)
  ) then
    raise exception 'submitted and terminal inspections are read-only; return the inspection for correction first';
  end if;
  if jsonb_typeof(p_header) is distinct from 'object'
     or jsonb_typeof(p_items) is distinct from 'array'
     or jsonb_array_length(p_items) = 0 then
    raise exception 'invalid inspection payload';
  end if;

  if p_header ? 'location_label' and (
       length(btrim(coalesce(p_header->>'location_label', ''))) = 0
       or length(p_header->>'location_label') > 240
     ) then
    raise exception 'enter a valid report location (1–240 characters)';
  end if;
  if p_header ? 'building_code' and (
       length(btrim(coalesce(p_header->>'building_code', ''))) = 0
       or length(p_header->>'building_code') > 80
     ) then
    raise exception 'enter a valid building number (1–80 characters)';
  end if;
  if p_header ? 'pin_override' and
     length(coalesce(p_header->>'pin_override', '')) > 50 then
    raise exception 'PIN number must be 50 characters or fewer';
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
    end,
    -- Inspection-level values only; the site master record is untouched.
    location_label = case
      when p_header ? 'location_label'
        then btrim(coalesce(p_header->>'location_label', ''))
      else location_label
    end,
    building_code = case
      when p_header ? 'building_code'
        then btrim(coalesce(p_header->>'building_code', ''))
      else building_code
    end,
    pin_override = case
      when p_header ? 'pin_override'
        then btrim(coalesce(p_header->>'pin_override', ''))
      else pin_override
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


revoke all on function public.save_checklist_inspection(uuid,bigint,jsonb,jsonb)
  from public, anon;
grant execute on function public.save_checklist_inspection(uuid,bigint,jsonb,jsonb)
  to authenticated;
