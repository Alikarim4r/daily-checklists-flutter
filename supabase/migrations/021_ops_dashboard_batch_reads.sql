-- =============================================================================
-- Scoped, batched reads for the operations dashboard
-- Migration: 021_ops_dashboard_batch_reads.sql
-- =============================================================================

-- Read-only viewers see approved records. Writers and managers can still read
-- in-progress records needed by Entry/Review, but only within their site scope.
drop policy if exists checklist_inspections_select on public.checklist_inspections;
create policy checklist_inspections_select on public.checklist_inspections
  for select to authenticated
  using (
    public.has_site_access(site_id)
    and (
      review_status = 'approved'
      or public.can_write_site(site_id)
      or public.can_manage_site(site_id)
    )
  );

-- Parse path UUIDs defensively. Storage policies also run while listing a
-- bucket, so malformed legacy names must be denied instead of failing a query.
create or replace function public.storage_path_organization_id(path text)
returns uuid
language sql
immutable
set search_path = public
as $$
  select case
    when split_part(path, '/', 1) ~*
      '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      then split_part(path, '/', 1)::uuid
    else null
  end;
$$;

create or replace function public.storage_path_site_id(path text)
returns uuid
language sql
immutable
set search_path = public
as $$
  select case
    when split_part(path, '/', 2) ~*
      '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      then split_part(path, '/', 2)::uuid
    else null
  end;
$$;

create or replace function public.storage_path_inspection_id(path text)
returns uuid
language sql
immutable
set search_path = public
as $$
  select case
    when split_part(path, '/', 3) ~*
      '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      then split_part(path, '/', 3)::uuid
    else null
  end;
$$;

create or replace function public.can_read_checklist_media(path text)
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
        and (
          inspection.review_status = 'approved'
          or public.can_write_site(inspection.site_id)
          or public.can_manage_site(inspection.site_id)
        )
    );
$$;

create or replace function public.can_write_checklist_media(path text)
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
        and (
          (
            inspection.status = 'draft'
            and inspection.review_status = 'draft'
            and public.can_write_site(inspection.site_id)
          )
          or (
            inspection.review_status = 'submitted'
            and public.can_manage_site(inspection.site_id)
          )
        )
    );
$$;

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
      (
        public.can_manage_site(public.storage_path_site_id(path))
        and not exists (
          select 1
          from public.checklist_inspections approved
          where approved.id = public.storage_path_inspection_id(path)
            and approved.site_id = public.storage_path_site_id(path)
            and approved.review_status = 'approved'
        )
      )
      or exists (
        select 1
        from public.checklist_inspections inspection
        where inspection.id = public.storage_path_inspection_id(path)
          and inspection.site_id = public.storage_path_site_id(path)
          and inspection.status = 'draft'
          and inspection.review_status = 'draft'
          and public.can_write_site(inspection.site_id)
      )
    );
$$;

revoke all on function public.storage_path_organization_id(text) from public;
revoke all on function public.storage_path_site_id(text) from public;
revoke all on function public.storage_path_inspection_id(text) from public;
revoke all on function public.can_read_checklist_media(text) from public;
revoke all on function public.can_write_checklist_media(text) from public;
revoke all on function public.can_delete_checklist_media(text) from public;
grant execute on function public.storage_path_organization_id(text)
  to authenticated;
grant execute on function public.storage_path_site_id(text)
  to authenticated;
grant execute on function public.storage_path_inspection_id(text)
  to authenticated;
grant execute on function public.can_read_checklist_media(text)
  to authenticated;
grant execute on function public.can_write_checklist_media(text)
  to authenticated;
grant execute on function public.can_delete_checklist_media(text)
  to authenticated;

drop policy if exists checklist_media_select on storage.objects;
create policy checklist_media_select on storage.objects
  for select to authenticated
  using (
    bucket_id = 'checklist-media'
    and public.can_read_checklist_media(name)
  );

drop policy if exists checklist_media_insert on storage.objects;
create policy checklist_media_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'checklist-media'
    and public.can_write_checklist_media(name)
  );

drop policy if exists checklist_media_update on storage.objects;
create policy checklist_media_update on storage.objects
  for update to authenticated
  using (
    bucket_id = 'checklist-media'
    and public.can_write_checklist_media(name)
  )
  with check (
    bucket_id = 'checklist-media'
    and public.can_write_checklist_media(name)
  );

drop policy if exists checklist_media_delete on storage.objects;
create policy checklist_media_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'checklist-media'
    and public.can_delete_checklist_media(name)
  );

create or replace function public.list_latest_checklist_inspections(
  p_site_ids uuid[],
  p_approved_only boolean default false
)
returns table (payload jsonb)
language sql
stable
security invoker
set search_path = public
as $$
  with latest as (
    select distinct on (inspection.site_id) inspection.*
    from public.checklist_inspections inspection
    where inspection.site_id = any(coalesce(p_site_ids, array[]::uuid[]))
      and (not p_approved_only or inspection.review_status = 'approved')
    order by
      inspection.site_id,
      inspection.inspection_date desc,
      inspection.created_at desc
  )
  select
    to_jsonb(latest)
    || jsonb_build_object(
      'sites', to_jsonb(site),
      'items', coalesce((
        select jsonb_agg(to_jsonb(item) order by item.item_index)
        from public.checklist_inspection_items item
        where item.inspection_id = latest.id
      ), '[]'::jsonb)
    ) as payload
  from latest
  join public.sites site on site.id = latest.site_id;
$$;

revoke all on function public.list_latest_checklist_inspections(uuid[], boolean)
  from public;
grant execute on function public.list_latest_checklist_inspections(
  uuid[], boolean
) to authenticated;

create or replace function public.list_checklist_inspection_history(
  p_ranges jsonb,
  p_approved_only boolean default false
)
returns table (payload jsonb)
language sql
stable
security invoker
set search_path = public
as $$
  with requested as (
    select request.*
    from jsonb_to_recordset(coalesce(p_ranges, '[]'::jsonb)) as request(
      site_id uuid,
      date_from date,
      date_to date
    )
  ), selected as (
    select inspection.*
    from requested request
    join public.checklist_inspections inspection
      on inspection.site_id = request.site_id
     and inspection.inspection_date >= request.date_from
     and inspection.inspection_date <= request.date_to
    where not p_approved_only or inspection.review_status = 'approved'
  )
  select
    to_jsonb(selected)
    || jsonb_build_object(
      'sites', to_jsonb(site),
      'items', coalesce((
        select jsonb_agg(to_jsonb(item) order by item.item_index)
        from public.checklist_inspection_items item
        where item.inspection_id = selected.id
      ), '[]'::jsonb)
    ) as payload
  from selected
  join public.sites site on site.id = selected.site_id
  order by
    selected.site_id,
    selected.inspection_date desc,
    selected.created_at desc;
$$;

revoke all on function public.list_checklist_inspection_history(jsonb, boolean)
  from public;
grant execute on function public.list_checklist_inspection_history(
  jsonb, boolean
) to authenticated;
