-- GLOB-001 P2: tenant-checked asset/plan CRUD and work execution RPCs.
-- Every write happens through a guarded transaction. No direct INSERT/UPDATE grants.
create or replace function public.fm_ppm_save_asset(
 p_org uuid,p_code text,p_name text,p_type text default 'other',
 p_site uuid default null,p_asset uuid default null,
 p_name_ar text default null,p_criticality text default 'medium',
 p_manufacturer text default null,p_model text default null,p_serial text default null,
 p_notes text default null,
 p_building uuid default null,p_floor uuid default null,p_area uuid default null
)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid;
begin
 if not public.fm_ppm_can_manage(p_org) then
   raise exception 'PPM asset administration denied' using errcode='42501'; end if;
 if p_code is null or btrim(p_code)='' or p_name is null or btrim(p_name)='' then
   raise exception 'asset code and name required'; end if;
 if p_asset is null then
  insert into public.fm_assets(organization_id,asset_code,name_en,name_ar,asset_type,
   site_id,building_id,floor_id,area_id,criticality,manufacturer,model,serial_number,notes)
  values(p_org,btrim(p_code),btrim(p_name),p_name_ar,coalesce(nullif(btrim(p_type),''),'other'),
    p_site,p_building,p_floor,p_area,p_criticality,p_manufacturer,p_model,p_serial,p_notes)
  returning id into v_id;
 else
  update public.fm_assets set asset_code=btrim(p_code),name_en=btrim(p_name),
   name_ar=p_name_ar,asset_type=coalesce(nullif(btrim(p_type),''),'other'),
   site_id=p_site,building_id=p_building,floor_id=p_floor,area_id=p_area,
   criticality=p_criticality,manufacturer=p_manufacturer,model=p_model,
   serial_number=p_serial,notes=p_notes where id=p_asset and organization_id=p_org
   returning id into v_id;
  if v_id is null then raise exception 'asset not found in organization' using errcode='42501'; end if;
  if exists(select 1 from public.fm_ppm_jobs where asset_id=v_id) then
   -- Reject moves which would rewrite the location underpinning historical jobs.
   if exists(select 1 from public.fm_ppm_jobs j where j.asset_id=v_id
        and j.site_id is distinct from p_site) then
      raise exception 'asset with historical jobs cannot be moved to another site';
   end if;
  end if;
 end if;
 return v_id;
end;
$$;

create or replace function public.fm_ppm_save_plan(
 p_org uuid,p_asset uuid,p_title text,p_frequency text,p_anchor date,
 p_every int default 1,p_plan uuid default null,p_title_ar text default null,
 p_instructions text default null,p_assignment uuid default null,
 p_timezone text default 'UTC'
)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid;
begin
 if not public.fm_ppm_can_manage(p_org) then
   raise exception 'PPM plan administration denied' using errcode='42501'; end if;
 if p_title is null or btrim(p_title)='' then raise exception 'plan title required'; end if;
 if p_anchor is null then raise exception 'PPM plan start date required'; end if;
 if p_plan is null then
  insert into public.fm_ppm_plans(organization_id,asset_id,title_en,title_ar,
    frequency,interval_count,anchor_date,next_due_on,instructions,checklist_assignment_id,timezone_id)
  values(p_org,p_asset,btrim(p_title),p_title_ar,
    p_frequency,p_every,p_anchor,p_anchor,p_instructions,p_assignment,p_timezone)
  returning id into v_id;
 else
  update public.fm_ppm_plans
  set asset_id=p_asset,title_en=btrim(p_title),title_ar=p_title_ar,
    frequency=p_frequency,interval_count=p_every,anchor_date=p_anchor,timezone_id=p_timezone,
    instructions=p_instructions,checklist_assignment_id=p_assignment
  where id=p_plan and organization_id=p_org returning id into v_id;
  if v_id is null then raise exception 'plan not found in organization' using errcode='42501'; end if;
 end if;
 return v_id;
end;
$$;

-- Bounded, repeatable generation with row lock and unique(plan_id,due_on).
-- New jobs retain their due date even if maintenance is finished late.
create or replace function public.fm_ppm_generate_due_jobs(
 p_org uuid,p_horizon_days integer default 45,p_max_jobs integer default 200
)
returns integer language plpgsql security definer set search_path=public as $$
declare
  v_plan record;
  v_asset public.fm_assets%rowtype;
  v_count int:=0;
  v_added int;
  v_job uuid;
  v_due date;
  v_index int;
  v_today date;
begin
 if not public.fm_ppm_can_manage(p_org) then
   raise exception 'PPM schedule management denied' using errcode='42501'; end if;
 if p_horizon_days<0 or p_horizon_days>90 or p_max_jobs<1 or p_max_jobs>1000 then
   raise exception 'PPM generation limits exceeded'; end if;
 for v_plan in select * from public.fm_ppm_plans
   where organization_id=p_org and is_active
     and next_due_on <= ((clock_timestamp() at time zone timezone_id)::date + p_horizon_days)
   order by next_due_on,id for update skip locked
 loop
   v_today:=(clock_timestamp() at time zone v_plan.timezone_id)::date;
   select * into v_asset from public.fm_assets where id=v_plan.asset_id;
   if v_asset.status='retired' then continue; end if;
   v_index:=v_plan.occurrence_index;
   v_due:=v_plan.next_due_on;
   while v_due<=v_today+p_horizon_days and v_count<p_max_jobs loop
     v_job:=null;
     insert into public.fm_ppm_jobs(
       organization_id,plan_id,asset_id,site_id,checklist_assignment_id,due_on)
       values(v_plan.organization_id,v_plan.id,v_plan.asset_id,v_asset.site_id,
              v_plan.checklist_assignment_id,v_due)
       on conflict (plan_id,due_on) do nothing returning id into v_job;
     if v_job is not null then
       insert into public.fm_ppm_job_events(organization_id,job_id,action,actor_id,notes)
       values(p_org,v_job,'created',auth.uid(),'Generated by PPM schedule');
       v_count:=v_count+1;
     end if;
     v_index:=v_index+1;
     v_due:=public.fm_ppm_due_date(v_plan.anchor_date,v_plan.frequency,
       v_plan.interval_count,v_index);
     if v_index>20000 then raise exception 'PPM recurrence has exceeded safety limit'; end if;
   end loop;
   update public.fm_ppm_plans
   set occurrence_index=v_index,next_due_on=v_due where id=v_plan.id;
   exit when v_count>=p_max_jobs;
 end loop;
 return v_count;
end;
$$;

create or replace function public.fm_ppm_start_job(p_job uuid)
returns void language plpgsql security definer set search_path=public as $$
declare v_job public.fm_ppm_jobs%rowtype;
begin
 select * into v_job from public.fm_ppm_jobs where id=p_job for update;
 if not found or not public.fm_ppm_can_execute(v_job.organization_id,v_job.site_id) then
  raise exception 'PPM job start denied' using errcode='42501'; end if;
 if v_job.assigned_to is not null and v_job.assigned_to<>auth.uid()
    and not public.fm_ppm_can_manage(v_job.organization_id) then
   raise exception 'PPM job is assigned to a different technician' using errcode='42501';end if;
 if v_job.status<>'scheduled' then raise exception 'only scheduled jobs can start'; end if;
 update public.fm_ppm_jobs
 set status='in_progress',started_at=now() where id=p_job;
 insert into public.fm_ppm_job_events(organization_id,job_id,action,actor_id)
 values(v_job.organization_id,p_job,'started',auth.uid());
end;
$$;

create or replace function public.fm_ppm_complete_job(
 p_job uuid,p_notes text,p_readings jsonb default '{}'::jsonb,
 p_inspection uuid default null
)
returns void language plpgsql security definer set search_path=public as $$
declare v_job public.fm_ppm_jobs%rowtype;
begin
 select * into v_job from public.fm_ppm_jobs where id=p_job for update;
 if not found or not public.fm_ppm_can_execute(v_job.organization_id,v_job.site_id) then
  raise exception 'PPM completion denied' using errcode='42501'; end if;
 if v_job.assigned_to is not null and v_job.assigned_to<>auth.uid()
    and not public.fm_ppm_can_manage(v_job.organization_id) then
   raise exception 'PPM job is assigned to a different technician' using errcode='42501';end if;
 -- A retried offline completion after a committed response loss is harmless.
 if v_job.status='completed' and v_job.completed_by=auth.uid()
   and v_job.execution_notes=btrim(p_notes)
   and v_job.readings is not distinct from p_readings
   and v_job.inspection_id is not distinct from p_inspection then
   return;
 end if;
 if v_job.status not in ('scheduled','in_progress') then
  raise exception 'PPM job already closed'; end if;
 if p_notes is null or length(btrim(p_notes))<5 then
  raise exception 'execution notes of at least five characters required'; end if;
 if p_readings is null or jsonb_typeof(p_readings)<>'object' then
  raise exception 'PPM readings must be a JSON object'; end if;
 update public.fm_ppm_jobs
 set status='completed',execution_notes=btrim(p_notes),readings=p_readings,
 inspection_id=p_inspection,completed_at=now(),completed_by=auth.uid(),
 started_at=coalesce(started_at,now()) where id=p_job;
 insert into public.fm_ppm_job_events
 (organization_id,job_id,action,actor_id,notes,inspection_id,readings)
 values(v_job.organization_id,p_job,'completed',auth.uid(),btrim(p_notes),p_inspection,p_readings);
end;
$$;

create or replace function public.fm_ppm_skip_job(p_job uuid,p_reason text)
returns void language plpgsql security definer set search_path=public as $$
declare v_job public.fm_ppm_jobs%rowtype;
begin
 select * into v_job from public.fm_ppm_jobs where id=p_job for update;
 if not found or not public.fm_ppm_can_manage(v_job.organization_id) then
  raise exception 'PPM skip requires organization admin' using errcode='42501'; end if;
 if v_job.status not in ('scheduled','in_progress') then raise exception 'PPM job already closed'; end if;
 if p_reason is null or length(btrim(p_reason))<5 then raise exception 'skip reason required'; end if;
 update public.fm_ppm_jobs set status='skipped',execution_notes=btrim(p_reason),
 completed_by=auth.uid(),completed_at=now() where id=p_job;
 insert into public.fm_ppm_job_events(organization_id,job_id,action,actor_id,notes)
 values(v_job.organization_id,p_job,'skipped',auth.uid(),btrim(p_reason));
end;
$$;


-- Owner/organization-admin only PPM plan pause/resume.
create or replace function public.fm_ppm_set_plan_active(p_plan uuid,p_active boolean)
returns void language plpgsql security definer set search_path=public as $$
declare v_plan public.fm_ppm_plans%rowtype;
begin
 select * into v_plan from public.fm_ppm_plans where id=p_plan for update;
 if not found or not public.fm_ppm_can_manage(v_plan.organization_id) then
   raise exception 'PPM plan status change denied' using errcode='42501';end if;
 update public.fm_ppm_plans set is_active=p_active where id=p_plan;
end;
$$;
revoke all on function public.fm_ppm_set_plan_active(uuid,boolean) from public,anon;
grant execute on function public.fm_ppm_set_plan_active(uuid,boolean) to authenticated;

-- Controlled assignment; assigned user must belong to same organization and
-- have write access to the specific site (or be an org administrator).
create or replace function public.fm_ppm_assign_job(p_job uuid,p_user uuid)
returns void language plpgsql security definer set search_path=public as $$
declare v_job public.fm_ppm_jobs%rowtype;
begin
 select * into v_job from public.fm_ppm_jobs where id=p_job for update;
 if not found or not public.fm_ppm_can_manage(v_job.organization_id) then
  raise exception 'PPM assignment denied' using errcode='42501';end if;
 if v_job.status in ('completed','skipped') then raise exception 'closed PPM job cannot be reassigned';end if;
 if p_user is not null and not exists(
  select 1 from public.profiles p
  where p.id=p_user and p.home_organization_id=v_job.organization_id
    and p.is_active and p.approval_status='approved'
    and (p.role='super_admin' or exists(
      select 1 from public.user_site_access a
      where a.user_id=p_user and a.site_id=v_job.site_id and a.can_write
        and (a.valid_from is null or a.valid_from<=now())
        and (a.valid_until is null or a.valid_until>now())
    ) or exists(
      select 1 from public.user_location_access a
      where a.user_id=p_user and a.organization_id=v_job.organization_id
        and a.can_write and (a.site_id=v_job.site_id or a.site_id is null)
        and a.building_id is null and a.floor_id is null and a.area_id is null
        and (a.valid_from is null or a.valid_from<=now())
        and (a.valid_until is null or a.valid_until>now())
    ))
 ) then raise exception 'assigned user must have current write access to work site';end if;
 update public.fm_ppm_jobs set assigned_to=p_user where id=p_job;
 insert into public.fm_ppm_job_events(organization_id,job_id,action,actor_id,notes)
 values(v_job.organization_id,p_job,'assigned',auth.uid(),
   case when p_user is null then 'Unassigned' else 'Assigned to '||p_user::text end);
end;
$$;
revoke all on function public.fm_ppm_assign_job(uuid,uuid) from public,anon;
grant execute on function public.fm_ppm_assign_job(uuid,uuid) to authenticated;

-- Do not grant functions to anonymous callers, including default PUBLIC execute.
revoke all on function
 public.fm_ppm_save_asset(uuid,text,text,text,uuid,uuid,text,text,text,text,text,text,uuid,uuid,uuid),
 public.fm_ppm_save_plan(uuid,uuid,text,text,date,int,uuid,text,text,uuid,text),
 public.fm_ppm_generate_due_jobs(uuid,integer,integer),
 public.fm_ppm_start_job(uuid),
 public.fm_ppm_complete_job(uuid,text,jsonb,uuid),
 public.fm_ppm_skip_job(uuid,text)
from public,anon;
grant execute on function
 public.fm_ppm_save_asset(uuid,text,text,text,uuid,uuid,text,text,text,text,text,text,uuid,uuid,uuid),
 public.fm_ppm_save_plan(uuid,uuid,text,text,date,int,uuid,text,text,uuid,text),
 public.fm_ppm_generate_due_jobs(uuid,integer,integer),
 public.fm_ppm_start_job(uuid),
 public.fm_ppm_complete_job(uuid,text,jsonb,uuid),
 public.fm_ppm_skip_job(uuid,text)
to authenticated;
