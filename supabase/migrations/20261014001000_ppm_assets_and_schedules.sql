-- GLOB-001 P2: additive asset register, PPM plans, work orders and immutable event history.
-- No existing table or checklist structure is rewritten.
create table if not exists public.fm_assets (
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete restrict,
 site_id uuid references public.sites(id) on delete restrict,
 building_id uuid references public.facility_buildings(id) on delete restrict,
 floor_id uuid references public.facility_floors(id) on delete restrict,
 area_id uuid references public.facility_areas(id) on delete restrict,
 asset_code text not null check (length(btrim(asset_code)) between 1 and 80),
 name_en text not null check (length(btrim(name_en)) between 1 and 250),
 name_ar text,
 asset_type text not null default 'other',
 manufacturer text, model text, serial_number text,
 criticality text not null default 'medium' check (criticality in ('low','medium','high','critical')),
 status text not null default 'operational' check (status in ('operational','out_of_service','retired')),
 notes text,
 created_by uuid default auth.uid(),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(organization_id,asset_code)
);
create index if not exists fm_assets_org_site_idx on public.fm_assets(organization_id,site_id);
create table if not exists public.fm_ppm_plans (
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete restrict,
 asset_id uuid not null references public.fm_assets(id) on delete restrict,
 checklist_assignment_id uuid references public.checklist_assignments(id) on delete restrict,
 title_en text not null check (length(btrim(title_en)) between 1 and 250),
 title_ar text,
 instructions text,
 timezone_id text not null default 'UTC',
 frequency text not null check (frequency in ('daily','weekly','monthly','quarterly','biannual','annual')),
 interval_count integer not null default 1 check (interval_count between 1 and 24),
 anchor_date date not null,
 occurrence_index integer not null default 0 check (occurrence_index>=0),
 next_due_on date not null,
 is_active boolean not null default true,
 created_by uuid default auth.uid(),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index if not exists fm_ppm_plan_org_due_idx on public.fm_ppm_plans(organization_id,is_active,next_due_on);
create index if not exists fm_ppm_plan_asset_idx on public.fm_ppm_plans(asset_id);
create table if not exists public.fm_ppm_jobs (
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete restrict,
 plan_id uuid not null references public.fm_ppm_plans(id) on delete restrict,
 asset_id uuid not null references public.fm_assets(id) on delete restrict,
 site_id uuid references public.sites(id) on delete restrict,
 checklist_assignment_id uuid references public.checklist_assignments(id) on delete restrict,
 due_on date not null,
 status text not null default 'scheduled' check(status in ('scheduled','in_progress','completed','skipped')),
 assigned_to uuid references public.profiles(id) on delete set null,
 execution_notes text,
 readings jsonb not null default '{}'::jsonb check(jsonb_typeof(readings)='object'),
 inspection_id uuid references public.checklist_inspections(id) on delete restrict,
 started_at timestamptz,
 completed_at timestamptz,
 completed_by uuid references public.profiles(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(plan_id,due_on)
);
create index if not exists fm_ppm_jobs_org_due_idx on public.fm_ppm_jobs(organization_id,status,due_on);
create index if not exists fm_ppm_jobs_asset_due_idx on public.fm_ppm_jobs(asset_id,due_on desc);
create index if not exists fm_ppm_jobs_assignee_due_idx on public.fm_ppm_jobs(assigned_to,due_on);
-- Execute PPM overdue calculation in the plan's local timezone, not user's device clock.
create or replace view public.fm_ppm_jobs_view
with (security_invoker=true) as
select j.*,
  (j.status not in ('completed','skipped') and
   j.due_on < (clock_timestamp() at time zone p.timezone_id)::date) as is_overdue
from public.fm_ppm_jobs j
join public.fm_ppm_plans p on p.id=j.plan_id;
revoke all on public.fm_ppm_jobs_view from public,anon;
grant select on public.fm_ppm_jobs_view to authenticated;

create table if not exists public.fm_ppm_job_events (
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete restrict,
 job_id uuid not null references public.fm_ppm_jobs(id) on delete restrict,
 action text not null check(action in ('created','started','completed','skipped','assigned')),
 actor_id uuid references public.profiles(id) on delete set null,
 notes text,
 inspection_id uuid references public.checklist_inspections(id) on delete restrict,
 readings jsonb not null default '{}'::jsonb,
 recorded_at timestamptz not null default now()
);
create index if not exists fm_ppm_events_job_idx on public.fm_ppm_job_events(job_id,recorded_at);

-- Enforce location integrity at the database, including optional full hierarchy.
create or replace function public.fm_verify_asset_location()
returns trigger language plpgsql set search_path=public as $$
declare v_site uuid; v_building uuid; v_floor uuid;
begin
 if new.site_id is null then
   if new.building_id is not null or new.floor_id is not null or new.area_id is not null
   then raise exception 'site required when asset location children set'; end if;
 else
   if not exists(select 1 from public.sites s where s.id=new.site_id and s.organization_id=new.organization_id)
   then raise exception 'asset site does not belong to organization'; end if;
 end if;
 if new.building_id is not null then
   select b.site_id into v_site from public.facility_buildings b where b.id=new.building_id;
   if v_site is distinct from new.site_id then raise exception 'asset building site mismatch'; end if;
 end if;
 if new.floor_id is not null then
   select f.building_id into v_building from public.facility_floors f where f.id=new.floor_id;
   if new.building_id is null or v_building is distinct from new.building_id then raise exception 'asset floor building mismatch'; end if;
 end if;
 if new.area_id is not null then
   select a.floor_id into v_floor from public.facility_areas a where a.id=new.area_id;
   if new.floor_id is null or v_floor is distinct from new.floor_id then raise exception 'asset area floor mismatch'; end if;
 end if;
 new.updated_at=now(); return new;
end;
$$;
create trigger fm_asset_location_guard before insert or update on public.fm_assets
for each row execute function public.fm_verify_asset_location();

-- PPM schedule date function: month-end anchoring never drifts (Jan31 -> Feb28 -> Mar31).
create or replace function public.fm_ppm_due_date(p_anchor date,p_frequency text,p_every int,p_index int)
returns date language plpgsql immutable set search_path=public as $$
declare v_months int; v_month date; v_last int; v_anchor_day int;
begin
 if p_anchor is null or p_index<0 or p_every<1 then raise exception 'invalid PPM recurrence inputs'; end if;
 if p_frequency='daily' then return p_anchor+p_index*p_every; end if;
 if p_frequency='weekly' then return p_anchor+p_index*p_every*7; end if;
 v_months:=case p_frequency when 'monthly' then 1 when 'quarterly' then 3 when 'biannual' then 6 when 'annual' then 12 else 0 end;
 if v_months=0 then raise exception 'unsupported PPM recurrence'; end if;
 v_month:=date_trunc('month',p_anchor::timestamp)::date + (v_months*p_every*p_index || ' months')::interval;
 v_anchor_day:=extract(day from p_anchor)::integer;
 v_last:=extract(day from (v_month+interval '1 month'-interval '1 day'))::integer;
 return v_month+least(v_anchor_day,v_last)-1;
end;
$$;

-- Reject forged tenant / asset / assignment linkages even if server write paths change.
create or replace function public.fm_verify_ppm_plan()
returns trigger language plpgsql set search_path=public as $$
declare v_asset public.fm_assets%rowtype; v_ass public.checklist_assignments%rowtype;
begin
 select * into v_asset from public.fm_assets where id=new.asset_id;
 if not found or v_asset.organization_id<>new.organization_id then
   raise exception 'PPM plan asset and organization mismatch'; end if;
 if new.checklist_assignment_id is not null then
   select * into v_ass from public.checklist_assignments where id=new.checklist_assignment_id;
   if not found or v_ass.organization_id<>new.organization_id or
      (v_asset.site_id is not null and v_ass.site_id<>v_asset.site_id) then
      raise exception 'PPM checklist assignment tenant/site mismatch'; end if;
 end if;
 if not exists(select 1 from pg_timezone_names where name=new.timezone_id) then
   raise exception 'invalid PPM IANA timezone'; end if;
 if tg_op='UPDATE' and (new.asset_id is distinct from old.asset_id
    or new.checklist_assignment_id is distinct from old.checklist_assignment_id)
    and exists(select 1 from public.fm_ppm_jobs where plan_id=old.id) then
   raise exception 'cannot move a plan with existing jobs to another asset or assignment';
 end if;
 if tg_op='INSERT' then new.occurrence_index:=0; new.next_due_on:=new.anchor_date;
 elsif (new.anchor_date,new.frequency,new.interval_count) is distinct from
       (old.anchor_date,old.frequency,old.interval_count) then
   if exists(select 1 from public.fm_ppm_jobs j where j.plan_id=old.id) then
     raise exception 'cannot change recurrence of a plan with generated jobs; archive and create new plan';
   end if;
   new.occurrence_index:=0; new.next_due_on:=new.anchor_date;
 end if;
 new.updated_at=now(); return new;
end;
$$;
create trigger fm_ppm_plan_guard before insert or update on public.fm_ppm_plans
for each row execute function public.fm_verify_ppm_plan();

-- Enforce statuses and row integrity independent of client UI.
create or replace function public.fm_verify_ppm_job()
returns trigger language plpgsql set search_path=public as $$
declare v_plan public.fm_ppm_plans%rowtype; v_asset public.fm_assets%rowtype;
begin
 select * into v_plan from public.fm_ppm_plans where id=new.plan_id;
 select * into v_asset from public.fm_assets where id=new.asset_id;
 if v_plan.id is null or v_asset.id is null or
    new.organization_id<>v_plan.organization_id or new.asset_id<>v_plan.asset_id
    or new.site_id is distinct from v_asset.site_id or
    new.checklist_assignment_id is distinct from v_plan.checklist_assignment_id then
   raise exception 'PPM job tenant/asset/assignment mismatch'; end if;
 if tg_op='UPDATE' and old.status in ('completed','skipped') and
      new is distinct from old then
   raise exception 'terminal PPM work records are immutable';
 end if;
 if new.inspection_id is not null and not exists(
   select 1 from public.checklist_inspections i
   join public.sites s on s.id=i.site_id
   where i.id=new.inspection_id and i.status='submitted'
     and s.organization_id=new.organization_id
     and (new.checklist_assignment_id is null or i.checklist_assignment_id=new.checklist_assignment_id)
 ) then raise exception 'inspection evidence must be submitted in matching organization/assignment';
 end if;
 new.updated_at=now(); return new;
end;
$$;
create trigger fm_ppm_job_guard before insert or update on public.fm_ppm_jobs
for each row execute function public.fm_verify_ppm_job();

create or replace function public.fm_ppm_event_immutable()
returns trigger language plpgsql set search_path=public as $$
begin raise exception 'PPM audit events are immutable'; end;
$$;
create trigger fm_ppm_event_no_change before update or delete on public.fm_ppm_job_events
for each row execute function public.fm_ppm_event_immutable();

-- Helper avoids granting broad direct DB table access to operational staff.
create or replace function public.fm_ppm_can_manage(p_org uuid)
returns boolean language sql stable security definer set search_path=public
as $$ select auth.uid() is not null and
 (coalesce(public.is_platform_owner(),false) or
  (coalesce(public.is_approved_active_user(),false) and
   coalesce(public.is_org_super_admin(p_org),false))) $$;
create or replace function public.fm_ppm_can_read(p_org uuid,p_site uuid)
returns boolean language sql stable security definer set search_path=public
as $$
 select auth.uid() is not null and
 (public.fm_ppm_can_manage(p_org) or
  (coalesce(public.is_approved_active_user(),false) and
   p_site is not null and coalesce(public.has_site_access(p_site),false)))
$$;
create or replace function public.fm_ppm_can_execute(p_org uuid,p_site uuid)
returns boolean language sql stable security definer set search_path=public
as $$
 select auth.uid() is not null and
 (public.fm_ppm_can_manage(p_org) or
  (coalesce(public.is_approved_active_user(),false) and
   p_site is not null and coalesce(public.can_write_site(p_site),false)))
$$;

alter table public.fm_assets enable row level security;
alter table public.fm_ppm_plans enable row level security;
alter table public.fm_ppm_jobs enable row level security;
alter table public.fm_ppm_job_events enable row level security;
create policy fm_assets_select on public.fm_assets
 for select to authenticated using (public.fm_ppm_can_read(organization_id,site_id));
create policy fm_plans_select on public.fm_ppm_plans
 for select to authenticated using (
  exists(select 1 from public.fm_assets a where a.id=asset_id and public.fm_ppm_can_read(organization_id,a.site_id))
 );
create policy fm_jobs_select on public.fm_ppm_jobs
 for select to authenticated using (public.fm_ppm_can_read(organization_id,site_id));
create policy fm_events_select on public.fm_ppm_job_events
 for select to authenticated using (
  exists(select 1 from public.fm_ppm_jobs j where j.id=job_id and public.fm_ppm_can_read(organization_id,j.site_id))
 );
revoke all on public.fm_assets,public.fm_ppm_plans,public.fm_ppm_jobs,public.fm_ppm_job_events from public,anon,authenticated;
grant select on public.fm_assets,public.fm_ppm_plans,public.fm_ppm_jobs,public.fm_ppm_job_events to authenticated;
revoke all on function public.fm_ppm_can_manage(uuid),public.fm_ppm_can_read(uuid,uuid),public.fm_ppm_can_execute(uuid,uuid)
 from public,anon;
grant execute on function public.fm_ppm_can_manage(uuid),public.fm_ppm_can_read(uuid,uuid),public.fm_ppm_can_execute(uuid,uuid) to authenticated;
