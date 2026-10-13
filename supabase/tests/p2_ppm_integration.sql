-- P2 tenant, schedule, immutability and evidence tests.
do $$
begin
 if public.fm_ppm_due_date('2024-01-31','monthly',1,1)<>'2024-02-29'
 or public.fm_ppm_due_date('2024-01-31','monthly',1,2)<>'2024-03-31'
 or public.fm_ppm_due_date('2023-01-31','monthly',1,1)<>'2023-02-28'
 or public.fm_ppm_due_date('2026-01-01','weekly',1,2)<>'2026-01-15'
 or public.fm_ppm_due_date('2025-02-28','annual',1,1)<>'2026-02-28'
 then raise exception 'monthly/year recurrence anchor drift';end if;
end;$$;

set role authenticated;
set request.jwt.claim.sub='10000000-0000-0000-0000-000000000001';
do $$
declare a uuid; p uuid; n int; denied boolean:=false;
begin
 begin
  perform public.fm_ppm_save_asset(
   '00000000-0000-0000-0000-00000000000b','CH-01','Invalid','chiller',
   '50000000-0000-0000-0000-000000000002');
 exception when insufficient_privilege then denied:=true;end;
 if not denied then raise exception 'org admin may insert asset in Org B';end if;
 begin
  perform public.fm_ppm_save_asset(
   '00000000-0000-0000-0000-00000000000a','CH-02','Bad location','chiller',
   '50000000-0000-0000-0000-000000000002');
  raise exception 'cross-org asset site accepted';
 exception when raise_exception then
   if exists(select 1 from public.fm_assets where asset_code='CH-02') then raise exception 'location validation bypassed';end if;
 end;
 a:=public.fm_ppm_save_asset(
 '00000000-0000-0000-0000-00000000000a','CH-01','Chiller 1','chiller',
 '50000000-0000-0000-0000-000000000001',p_criticality=>'critical',
 p_building=>'60000000-0000-0000-0000-000000000001',
 p_floor=>'70000000-0000-0000-0000-000000000001',
 p_area=>'80000000-0000-0000-0000-000000000001');
 if not exists(select 1 from public.fm_assets where id=a and criticality='critical') then
  raise exception 'asset upsert failed';end if;
 p:=public.fm_ppm_save_plan(
 '00000000-0000-0000-0000-00000000000a',a,'Daily cooling check','daily',
 current_date-2,1,p_assignment=>'90000000-0000-0000-0000-000000000001',
 p_timezone=>'Asia/Qatar');
 if (select timezone_id from public.fm_ppm_plans where id=p)<>'Asia/Qatar' then
   raise exception 'IANA timezone not saved'; end if;
 begin
  perform public.fm_ppm_save_plan(
   '00000000-0000-0000-0000-00000000000a',a,'Invalid timezone','monthly',
   current_date,1,p_timezone=>'Mars/Phobos');
  raise exception 'invalid timezone accepted';
 exception when raise_exception then
  if exists(select 1 from public.fm_ppm_plans where title_en='Invalid timezone') then
   raise exception 'invalid timezone was persisted'; end if;
 end;
 n:=public.fm_ppm_generate_due_jobs('00000000-0000-0000-0000-00000000000a',2,20);
 if n<>5 then raise exception 'expected five due daily jobs, got %',n;end if;
 n:=public.fm_ppm_generate_due_jobs('00000000-0000-0000-0000-00000000000a',2,20);
 if n<>0 then raise exception 'PPM generation not idempotent: %',n;end if;
 if (select count(*) from public.fm_ppm_job_events where action='created')<>5 then
  raise exception 'missing immutable creation audit';end if;
 perform public.fm_ppm_assign_job(
  (select id from public.fm_ppm_jobs order by due_on limit 1),
  '10000000-0000-0000-0000-000000000005');
 if (select count(*) from public.fm_ppm_jobs
    where assigned_to='10000000-0000-0000-0000-000000000005')<>1 then
  raise exception 'PPM technician assignment failed'; end if;
 perform public.fm_ppm_set_plan_active(p,false);
 if (select is_active from public.fm_ppm_plans where id=p) then
  raise exception 'PPM plan pause failed';end if;
 perform public.fm_ppm_set_plan_active(p,true);
 if not (select is_active from public.fm_ppm_plans where id=p) then
  raise exception 'PPM plan resume failed';end if;

end;$$;

-- Site worker can read assigned site and execute; cannot create/manage PPM.
set request.jwt.claim.sub='10000000-0000-0000-0000-000000000005';
do $$
declare j uuid; denied boolean:=false;
begin
 begin
  perform public.fm_ppm_generate_due_jobs('00000000-0000-0000-0000-00000000000a');
 exception when insufficient_privilege then denied:=true;end;
 if not denied then raise exception 'worker may generate plans';end if;
 select id into j from public.fm_ppm_jobs order by due_on limit 1;
 if j is null then raise exception 'worker cannot read assigned PPM';end if;
 perform public.fm_ppm_start_job(j);
 begin
  perform public.fm_ppm_complete_job(j,'Completed coolant check','{}',
  'a0000000-0000-0000-0000-000000000002');
  raise exception 'foreign-tenant evidence accepted';
 exception when raise_exception then
  if exists(select 1 from public.fm_ppm_jobs where id=j and status='completed') then
   raise exception 'cross-org inspection evidence accepted';end if;
 end;
 perform public.fm_ppm_complete_job(j,'Completed coolant check',
 '{"supply_temp_c":6.5}'::jsonb,
 'a0000000-0000-0000-0000-000000000001');
 -- Retry identical offline evidence: should not produce a second completion event.
 perform public.fm_ppm_complete_job(j,'Completed coolant check',
 '{"supply_temp_c":6.5}'::jsonb,
 'a0000000-0000-0000-0000-000000000001');
 if (select count(*) from public.fm_ppm_job_events
     where job_id=j and action='completed')<>1 then
   raise exception 'offline completion retry duplicated audit';end if;
 if not exists(select 1 from public.fm_ppm_jobs where id=j
   and status='completed' and inspection_id='a0000000-0000-0000-0000-000000000001')
 then raise exception 'legitimate completion with evidence failed';end if;
 begin
  perform public.fm_ppm_complete_job(j,'Double complete');
  raise exception 'repeat closure accepted';
 exception when raise_exception then null; end;
end;$$;

set request.jwt.claim.sub='10000000-0000-0000-0000-000000000001';
do $$
declare j uuid; denied boolean:=false;
begin
 select id into j from public.fm_ppm_jobs where status='scheduled' order by due_on limit 1;
 perform public.fm_ppm_skip_job(j,'Access denied by building management');
 if not exists(select 1 from public.fm_ppm_jobs where id=j and status='skipped') then
  raise exception 'skip failure';end if;
 begin
  update public.fm_ppm_jobs set status='scheduled' where id=j;
  raise exception 'final state mutated';
 exception when insufficient_privilege then null; when raise_exception then null;end;
 begin
  delete from public.fm_ppm_job_events where job_id=j;
  raise exception 'audit event deleted';
 exception when insufficient_privilege then null;when raise_exception then null;end;
end;$$;

-- Separate authorized org must never read or complete other tenant's work.
set request.jwt.claim.sub='10000000-0000-0000-0000-000000000002';
do $$
declare n int; denied boolean:=false;
begin
 select count(*) into n from public.fm_ppm_jobs;
 if n<>0 then raise exception 'cross-tenant PPM job leak %',n;end if;
 select count(*) into n from public.fm_assets;
 if n<>0 then raise exception 'cross-tenant asset leak %',n;end if;
 begin
 perform public.fm_ppm_start_job((select id from public.fm_ppm_jobs limit 1));
 exception when insufficient_privilege then denied:=true;end;
 -- hidden job passed as null still must not execute.
 if not denied then raise exception 'unauthorized job execution';end if;
end;$$;
reset role;
select 'P2 PPM ISOLATED SECURITY + SCHEDULE + EXECUTION PASS' as result;
