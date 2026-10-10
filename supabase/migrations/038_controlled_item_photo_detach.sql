-- A wrongly attached image may be detached from an editable draft without
-- destroying the original photograph or compromising approved audit history.
-- Supports linked legacy photo paths that predate media ledger registration.
-- All removals are isolated to one approved RPC, one item and one path.
-- No stored image bytes or inspection rows are deleted by this migration.

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
  v_review_status public.checklist_review_status;
  v_old_evidence text;
  v_new_evidence text;
  v_allowed_path text := coalesce(
    nullif(current_setting('app.checklist_photo_detach_path', true), ''),
    nullif(current_setting('app.fix_photo_detach_path', true), '')
  );
  v_allowed_kind text := coalesce(
    nullif(current_setting('app.checklist_photo_detach_kind', true), ''),
    'fix_photo'
  );
begin
  v_inspection_id := case when tg_op = 'INSERT' then new.inspection_id
    else old.inspection_id end;

  select inspection.site_id, inspection.review_status
  into v_site_id, v_review_status
  from public.checklist_inspections inspection
  where inspection.id = v_inspection_id;

  if v_site_id is null then
    return case when tg_op = 'DELETE' then old else new end;
  end if;
  if v_review_status = 'approved' then
    raise exception 'approved inspections are immutable';
  end if;

  if tg_op <> 'INSERT' then
    v_old_evidence := concat_ws('|',
      old.image_path, old.issue_image_path, old.fix_image_path
    );
    v_new_evidence := case when tg_op = 'DELETE' then '' else concat_ws('|',
      new.image_path, new.issue_image_path, new.fix_image_path
    ) end;
    if public.checklist_stored_evidence_removed(
      v_old_evidence,
      v_new_evidence,
      ''
    ) then
      if tg_op <> 'UPDATE'
         or v_allowed_path is null
         or position(v_allowed_path in v_old_evidence) = 0
         or position(v_allowed_path in v_new_evidence) > 0
         or exists (
           select 1
           from public.checklist_media_evidence evidence
           where evidence.inspection_id = v_inspection_id
             and evidence.inspection_item_id = old.id
             and evidence.storage_path = v_allowed_path
             and evidence.media_kind <> v_allowed_kind
             and evidence.deactivated_at is null
         )
         or exists (
           select 1
           from storage.objects object
           where object.bucket_id = 'checklist-media'
             and object.name <> v_allowed_path
             and position(object.name in v_old_evidence) > 0
             and position(object.name in v_new_evidence) = 0
         ) then
        raise exception
          'stored photo evidence is part of inspection history and cannot be removed';
      end if;
    end if;
  end if;

  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

create or replace function public.detach_checklist_item_photo(
  p_inspection_id uuid,
  p_item_id uuid,
  p_storage_path text,
  p_media_kind text,
  p_image_path text,
  p_issue_image_path text,
  p_fix_image_path text,
  p_expected_version bigint
)
returns bigint
language plpgsql
security definer
set search_path = public, storage
set row_security = off
as $$
declare
  v_site_id uuid;
  v_org_id uuid;
  v_review_status public.checklist_review_status;
  v_version bigint;
  v_old_evidence text;
  v_new_evidence text := concat_ws('|',
    p_image_path, p_issue_image_path, p_fix_image_path
  );
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if p_media_kind not in ('issue_photo', 'fix_photo') then
    raise exception 'invalid photo kind';
  end if;
  if not public.storage_path_valid(trim(p_storage_path)) then
    raise exception 'invalid evidence path';
  end if;

  select inspection.site_id, site.organization_id,
         inspection.review_status, inspection.version
  into v_site_id, v_org_id, v_review_status, v_version
  from public.checklist_inspections inspection
  join public.sites site on site.id = inspection.site_id
  where inspection.id = p_inspection_id
  for update of inspection;

  if v_site_id is null then raise exception 'inspection not found'; end if;
  if p_expected_version is distinct from v_version then
    raise exception using
      errcode = 'P0001',
      message = 'inspection was changed by another session; reload and retry';
  end if;
  if v_review_status not in ('draft', 'returned') then
    raise exception 'photos can only be detached from an editable draft';
  end if;
  if not public.can_write_site(v_site_id) then
    raise exception 'not allowed to edit this inspection';
  end if;

  select concat_ws('|', item.image_path, item.issue_image_path,
                   item.fix_image_path)
  into v_old_evidence
  from public.checklist_inspection_items item
  where item.id = p_item_id and item.inspection_id = p_inspection_id
  for update;
  if v_old_evidence is null then raise exception 'inspection item not found'; end if;

  if position(trim(p_storage_path) in v_old_evidence) = 0
     or position(trim(p_storage_path) in v_new_evidence) > 0
     or not exists (
       select 1 from public.checklist_inspection_items item
       where item.id = p_item_id and item.inspection_id = p_inspection_id
         and position(trim(p_storage_path) in case
           when p_media_kind = 'issue_photo'
             then concat_ws('|', item.image_path, item.issue_image_path)
           else coalesce(item.fix_image_path, '') end) > 0
     )
     or exists (
       select 1 from public.checklist_media_evidence evidence
       where evidence.inspection_id = p_inspection_id
         and evidence.inspection_item_id = p_item_id
         and evidence.storage_path = trim(p_storage_path)
         and evidence.media_kind <> p_media_kind
         and evidence.deactivated_at is null
     )
     or exists (
       select 1 from storage.objects object
       where object.bucket_id = 'checklist-media'
         and object.name <> trim(p_storage_path)
         and position(object.name in v_old_evidence) > 0
         and position(object.name in v_new_evidence) = 0
     ) then
    raise exception 'invalid or protected photo detach request';
  end if;

  perform set_config('app.checklist_photo_detach_path', trim(p_storage_path), true);
  perform set_config('app.checklist_photo_detach_kind', p_media_kind, true);
  update public.checklist_inspection_items
  set image_path = nullif(p_image_path, ''),
      issue_image_path = nullif(p_issue_image_path, ''),
      fix_image_path = nullif(p_fix_image_path, '')
  where id = p_item_id and inspection_id = p_inspection_id;

  update public.checklist_inspections
  set version = version + 1
  where id = p_inspection_id
  returning version into v_version;

  perform public.append_checklist_audit(
    'evidence.photo_detached',
    'checklist_inspection_item',
    p_item_id::text,
    v_site_id,
    v_org_id,
    jsonb_build_object('storage_path', trim(p_storage_path)),
    null,
    'operator corrected draft image relationship',
    jsonb_build_object(
      'inspection_id', p_inspection_id,
      'evidence_preserved', true, 'photo_kind', p_media_kind
    )
  );
  return v_version;
end;
$$;

revoke all on function public.detach_checklist_item_photo(
  uuid, uuid, text, text, text, text, text, bigint
) from public, anon, authenticated;
grant execute on function public.detach_checklist_item_photo(
  uuid, uuid, text, text, text, text, text, bigint
) to authenticated;
