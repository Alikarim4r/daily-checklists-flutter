-- Historical signatures and photos are append-only evidence.
--
-- Migration 027 blocked technicians but still allowed a manager to detach and
-- delete stored evidence before approval. It also checked only objects beneath
-- the current inspection prefix, which missed carried-forward issue photos
-- whose authoritative object belongs to an earlier inspection. This migration
-- closes both paths while preserving controlled cleanup of genuine orphans.

create or replace function public.guard_checklist_inspection_mutation()
returns trigger
language plpgsql
security definer
set search_path = public, storage
set row_security = off
as $$
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

    -- Empty prefix deliberately checks every object named by the trusted old
    -- row, including legacy or carried-forward storage paths.
    if public.checklist_stored_evidence_removed(
      old.signature_path,
      new.signature_path,
      ''
    ) then
      raise exception
        'stored signature evidence is part of inspection history and cannot be removed';
    end if;
  end if;
  return new;
end;
$$;

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
begin
  v_inspection_id := case when tg_op = 'INSERT' then new.inspection_id
    else old.inspection_id end;

  select inspection.site_id, inspection.review_status
  into v_site_id, v_review_status
  from public.checklist_inspections inspection
  where inspection.id = v_inspection_id;

  -- A cascading parent deletion reaches this trigger after the parent row is
  -- gone. The parent guard/RPC has already authorized that operation.
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
      raise exception
        'stored photo evidence is part of inspection history and cannot be removed';
    end if;
  end if;

  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

-- Storage deletion is allowed only for a manager cleaning up a genuine orphan
-- in a non-approved inspection. Any path still referenced by a header, item,
-- or active evidence ledger row remains protected.
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
    )
    and not exists (
      select 1
      from public.checklist_inspections inspection
      where inspection.signature_path = path
    )
    and not exists (
      select 1
      from public.checklist_inspection_items item
      where position(path in concat_ws('|',
        item.image_path, item.issue_image_path, item.fix_image_path
      )) > 0
    )
    and not exists (
      select 1
      from public.checklist_media_evidence evidence
      where evidence.storage_path = path
        and evidence.deactivated_at is null
    );
$$;

revoke all on function public.can_delete_checklist_media(text) from public;
grant execute on function public.can_delete_checklist_media(text)
  to authenticated;

