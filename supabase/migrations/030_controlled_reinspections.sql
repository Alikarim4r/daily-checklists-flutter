-- Controlled duplicate prevention: first daily site/list inspection is normal;
-- an intentional same-day reinspection requires an explicit recorded reason.

alter table public.checklist_inspections
  add column if not exists reinspection_reason text,
  add column if not exists reinspection_authorized_by uuid
    references public.profiles (id) on delete set null;

create index if not exists checklist_inspections_duplicate_period_idx
  on public.checklist_inspections (site_id, inspection_date, template_id);

create or replace function public.guard_duplicate_checklist_inspection()
returns trigger
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
declare
  v_reason text := nullif(trim(current_setting(
    'app.reinspection_reason', true
  )), '');
begin
  if exists (
    select 1
    from public.checklist_inspections existing
    where existing.site_id = new.site_id
      and existing.inspection_date = new.inspection_date
      and existing.review_status <> 'canceled'
  ) then
    if v_reason is null then
      raise exception 'a reinspection reason is required for another checklist in this period';
    end if;
    new.reinspection_reason := v_reason;
    new.reinspection_authorized_by := auth.uid();
  end if;
  return new;
end;
$$;

drop trigger if exists checklist_inspections_guard_duplicate
  on public.checklist_inspections;
create trigger checklist_inspections_guard_duplicate
  before insert on public.checklist_inspections
  for each row execute function public.guard_duplicate_checklist_inspection();

create or replace function public.create_checklist_reinspection_draft(
  p_site_id uuid,
  p_inspection_date date,
  p_inspector_name text,
  p_inspection_time text,
  p_floor_label text,
  p_items jsonb,
  p_client_reference text,
  p_reinspection_reason text
)
returns uuid
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
declare
  v_id uuid;
begin
  if nullif(trim(p_reinspection_reason), '') is null then
    raise exception 'a reinspection reason is required';
  end if;
  if not public.can_write_site(p_site_id) then
    raise exception 'not allowed to create a reinspection for this site';
  end if;
  perform set_config('app.reinspection_reason', trim(p_reinspection_reason), true);
  perform set_config('app.audit_reason', trim(p_reinspection_reason), true);
  v_id := public.create_checklist_inspection_draft(
    p_site_id,
    p_inspection_date,
    p_inspector_name,
    p_inspection_time,
    p_floor_label,
    p_items,
    p_client_reference
  );
  return v_id;
end;
$$;

revoke all on function public.create_checklist_reinspection_draft(
  uuid, date, text, text, text, jsonb, text, text
) from public;
grant execute on function public.create_checklist_reinspection_draft(
  uuid, date, text, text, text, jsonb, text, text
) to authenticated;

