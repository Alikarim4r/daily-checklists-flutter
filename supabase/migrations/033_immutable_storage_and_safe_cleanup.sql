-- Make checklist evidence objects immutable and make whole-draft cleanup a
-- deliberate server-authorized workflow. Approved inspections remain
-- immutable and can never create a cleanup authorization.

-- Extract every canonical checklist-media path from legacy scalar, tagged,
-- delimited, or v2 JSON values without trusting the client representation.
create or replace function public.checklist_evidence_paths(p_value text)
returns setof text
language sql
immutable
set search_path = public
as $$
  select distinct capture[1]
  from regexp_matches(
    coalesce(p_value, ''),
    '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/[^"|,\\]\\s}]+)',
    'g'
  ) as capture;
$$;

revoke all on function public.checklist_evidence_paths(text)
  from public, anon, authenticated;

-- Complete the legacy evidence ledger. Migration 029 only covered the legacy
-- image_path column and therefore missed v2 issue/fix pairs.
insert into public.checklist_media_evidence (
  organization_id, site_id, inspection_id, inspection_item_id, storage_path,
  media_kind, reference_no, uploaded_by, uploaded_at
)
select
  site.organization_id,
  inspection.site_id,
  inspection.id,
  item.id,
  paths.storage_path,
  case
    when position(paths.storage_path in coalesce(item.fix_image_path, '')) > 0
      or lower(paths.storage_path) like '%_fix_%'
      then 'fix_photo'
    else 'issue_photo'
  end,
  item.item_index::text || '.legacy.' ||
    row_number() over (
      partition by item.id order by paths.storage_path
    )::text,
  inspection.inspector_user_id,
  item.created_at
from public.checklist_inspection_items item
join public.checklist_inspections inspection
  on inspection.id = item.inspection_id
join public.sites site on site.id = inspection.site_id
cross join lateral public.checklist_evidence_paths(concat_ws(
  '|', item.image_path, item.issue_image_path, item.fix_image_path
)) as paths(storage_path)
where exists (
  select 1
  from storage.objects object
  where object.bucket_id = 'checklist-media'
    and object.name = paths.storage_path
)
on conflict (storage_path) do nothing;

-- A ledger entry must not claim that missing bytes are active evidence.
update public.checklist_media_evidence evidence
set deactivated_at = coalesce(evidence.deactivated_at, now())
where evidence.deactivated_at is null
  and not exists (
    select 1
    from storage.objects object
    where object.bucket_id = 'checklist-media'
      and object.name = evidence.storage_path
  );

-- Evidence metadata follows a deliberately deleted non-approved inspection.
-- This removes the former FK deadlock while approved records are still
-- protected by the inspection trigger and delete RPC.
alter table public.checklist_media_evidence
  drop constraint if exists checklist_media_evidence_inspection_item_id_fkey;
alter table public.checklist_media_evidence
  add constraint checklist_media_evidence_inspection_item_id_fkey
  foreign key (inspection_item_id)
  references public.checklist_inspection_items (id)
  on delete cascade;

alter table public.checklist_media_evidence
  drop constraint if exists checklist_media_evidence_inspection_id_fkey;
alter table public.checklist_media_evidence
  add constraint checklist_media_evidence_inspection_id_fkey
  foreign key (inspection_id)
  references public.checklist_inspections (id)
  on delete cascade;

create table if not exists public.checklist_media_cleanup_requests (
  storage_path text primary key,
  organization_id uuid not null,
  site_id uuid not null,
  inspection_id uuid not null,
  requested_by uuid not null,
  requested_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '24 hours'),
  completed_at timestamptz,
  constraint checklist_media_cleanup_path_valid
    check (public.storage_path_valid(storage_path)),
  constraint checklist_media_cleanup_expiry_valid
    check (expires_at > requested_at)
);

alter table public.checklist_media_cleanup_requests enable row level security;
revoke all on public.checklist_media_cleanup_requests
  from public, anon, authenticated;

create index if not exists checklist_media_cleanup_expiry_idx
  on public.checklist_media_cleanup_requests (expires_at)
  where completed_at is null;

-- Storage bytes are immutable. New objects may be inserted, and a whole-draft
-- deletion receives a short-lived, path-specific delete authorization.
drop policy if exists checklist_media_update on storage.objects;

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
    and (
      exists (
        select 1
        from public.checklist_media_cleanup_requests request
        where request.storage_path = trim(path)
          and request.requested_by = auth.uid()
          and request.completed_at is null
          and request.expires_at > now()
      )
      or (
        exists (
          select 1
          from public.checklist_inspections inspection
          where inspection.id = public.storage_path_inspection_id(path)
            and inspection.site_id = public.storage_path_site_id(path)
            and inspection.review_status <> 'approved'
            and (
              public.can_manage_site(inspection.site_id)
              or public.can_write_checklist_media(path)
            )
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
        )
      )
    );
$$;

revoke all on function public.can_delete_checklist_media(text) from public;
grant execute on function public.can_delete_checklist_media(text)
  to authenticated;

drop policy if exists checklist_media_delete on storage.objects;
create policy checklist_media_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'checklist-media'
    and public.can_delete_checklist_media(name)
  );

create or replace function public.perform_delete_checklist_inspection(
  p_inspection_id uuid,
  p_expected_version bigint
)
returns text[]
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
declare
  v_site_id uuid;
  v_org_id uuid;
  v_version bigint;
  v_review_status public.checklist_review_status;
  v_paths text[] := '{}'::text[];
begin
  delete from public.checklist_media_cleanup_requests request
  where request.completed_at < now() - interval '7 days'
     or request.expires_at < now() - interval '7 days';

  select inspection.site_id, site.organization_id, inspection.version,
         inspection.review_status
  into v_site_id, v_org_id, v_version, v_review_status
  from public.checklist_inspections inspection
  join public.sites site on site.id = inspection.site_id
  where inspection.id = p_inspection_id
  for update of inspection;

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

  select coalesce(array_agg(distinct candidate.storage_path), '{}'::text[])
  into v_paths
  from (
    select evidence.storage_path
    from public.checklist_media_evidence evidence
    where evidence.inspection_id = p_inspection_id
    union all
    select paths.storage_path
    from public.checklist_inspections inspection
    cross join lateral public.checklist_evidence_paths(
      inspection.signature_path
    ) as paths(storage_path)
    where inspection.id = p_inspection_id
    union all
    select paths.storage_path
    from public.checklist_inspection_items item
    cross join lateral public.checklist_evidence_paths(concat_ws(
      '|', item.image_path, item.issue_image_path, item.fix_image_path
    )) as paths(storage_path)
    where item.inspection_id = p_inspection_id
  ) candidate;

  insert into public.checklist_media_cleanup_requests (
    storage_path, organization_id, site_id, inspection_id, requested_by,
    requested_at, expires_at, completed_at
  )
  select path, v_org_id, v_site_id, p_inspection_id, auth.uid(),
         now(), now() + interval '24 hours', null
  from unnest(v_paths) path
  where public.storage_path_valid(path)
  on conflict (storage_path) do update set
    requested_by = excluded.requested_by,
    requested_at = excluded.requested_at,
    expires_at = excluded.expires_at,
    completed_at = null;

  delete from public.checklist_inspections
  where id = p_inspection_id;

  return v_paths;
end;
$$;

revoke all on function public.perform_delete_checklist_inspection(uuid, bigint)
  from public, anon, authenticated;

create or replace function public.delete_checklist_inspection_with_cleanup(
  p_inspection_id uuid,
  p_expected_version bigint
)
returns text[]
language sql
security definer
set search_path = public
set row_security = off
as $$
  select public.perform_delete_checklist_inspection(
    p_inspection_id, p_expected_version
  );
$$;

revoke all on function public.delete_checklist_inspection_with_cleanup(
  uuid, bigint
) from public;
grant execute on function public.delete_checklist_inspection_with_cleanup(
  uuid, bigint
) to authenticated;

-- Keep the old RPC safe for older installed clients.
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
begin
  perform public.perform_delete_checklist_inspection(
    p_inspection_id, p_expected_version
  );
end;
$$;

revoke all on function public.delete_checklist_inspection(uuid, bigint)
  from public;
grant execute on function public.delete_checklist_inspection(uuid, bigint)
  to authenticated;

create or replace function public.complete_checklist_media_cleanup(
  p_paths text[]
)
returns void
language sql
security definer
set search_path = public
set row_security = off
as $$
  update public.checklist_media_cleanup_requests request
  set completed_at = now()
  where request.storage_path = any(coalesce(p_paths, '{}'::text[]))
    and request.requested_by = auth.uid()
    and request.completed_at is null;
$$;

revoke all on function public.complete_checklist_media_cleanup(text[])
  from public;
grant execute on function public.complete_checklist_media_cleanup(text[])
  to authenticated;

create or replace function public.list_my_pending_checklist_media_cleanup()
returns text[]
language sql
stable
security definer
set search_path = public
set row_security = off
as $$
  select coalesce(array_agg(request.storage_path order by request.requested_at),
                  '{}'::text[])
  from public.checklist_media_cleanup_requests request
  where request.requested_by = auth.uid()
    and request.completed_at is null
    and request.expires_at > now();
$$;

revoke all on function public.list_my_pending_checklist_media_cleanup()
  from public;
grant execute on function public.list_my_pending_checklist_media_cleanup()
  to authenticated;
