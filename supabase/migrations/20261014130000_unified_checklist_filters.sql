-- GLOB-001: unified, per-organization checklist taxonomy; additive to P1/P2/P3.
create table public.checklist_filter_terms (
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete restrict,
 dimension text not null check(dimension in ('sector','service_class','department','coverage','document_kind')),
 parent_id uuid references public.checklist_filter_terms(id) on delete restrict,
 code text not null check(code ~ '^[a-z][a-z0-9_]{0,47}$'),
 name_en text not null check(length(btrim(name_en)) between 1 and 100),
 name_ar text not null check(length(btrim(name_ar)) between 1 and 100),
 sort_order int not null default 0,
 is_active boolean not null default true,
 created_at timestamptz not null default now(),
 unique nulls not distinct (organization_id,dimension,parent_id,code)
);
create index checklist_filter_terms_org_idx on public.checklist_filter_terms(organization_id,dimension,parent_id,is_active);

create or replace function public.checklist_filter_validate_term()
returns trigger language plpgsql set search_path=public,pg_temp as $$
declare p public.checklist_filter_terms%rowtype;
begin
 if new.dimension in ('sector','document_kind') then
  if new.parent_id is not null then raise exception 'top-level term has no parent'; end if;
 else
  if new.parent_id is null then raise exception 'parent term required'; end if;
  select * into p from public.checklist_filter_terms where id=new.parent_id;
  if p.id is null or p.organization_id<>new.organization_id or not p.is_active
   or (new.dimension='service_class' and p.dimension<>'sector')
   or (new.dimension='department' and p.dimension<>'service_class')
   or (new.dimension='coverage' and p.dimension<>'department')
  then raise exception 'category parent is invalid or not in organization';end if;
 end if;
 if tg_op='UPDATE' and (new.dimension<>old.dimension or
  new.organization_id<>old.organization_id or new.parent_id is distinct from old.parent_id)
 then raise exception 'category cannot be moved; archive and create';end if;
 return new;
end;
$$;
create trigger checklist_filter_term_guard before insert or update
on public.checklist_filter_terms for each row execute function public.checklist_filter_validate_term();

create table public.checklist_assignment_facets (
 assignment_id uuid primary key references public.checklist_assignments(id) on delete cascade,
 organization_id uuid not null references public.organizations(id),
 sector_id uuid not null references public.checklist_filter_terms(id),
 service_class_id uuid not null references public.checklist_filter_terms(id),
 department_id uuid not null references public.checklist_filter_terms(id),
 coverage_id uuid not null references public.checklist_filter_terms(id),
 document_kind_id uuid not null references public.checklist_filter_terms(id),
 updated_by uuid references public.profiles(id),
 updated_at timestamptz not null default now()
);
create index checklist_assignment_facets_org_idx on public.checklist_assignment_facets(organization_id,sector_id,service_class_id,department_id,coverage_id,document_kind_id);
create or replace function public.checklist_filter_validate_assignment()
returns trigger language plpgsql set search_path=public,pg_temp as $$
declare a public.checklist_assignments%rowtype;
 s public.checklist_filter_terms%rowtype;
 c public.checklist_filter_terms%rowtype;
 d public.checklist_filter_terms%rowtype;
 z public.checklist_filter_terms%rowtype;
 k public.checklist_filter_terms%rowtype;
begin
 select * into a from public.checklist_assignments where id=new.assignment_id;
 if a.id is null or a.organization_id<>new.organization_id then
  raise exception 'assignment and classification organization mismatch';end if;
 select * into s from public.checklist_filter_terms where id=new.sector_id;
 select * into c from public.checklist_filter_terms where id=new.service_class_id;
 select * into d from public.checklist_filter_terms where id=new.department_id;
 select * into z from public.checklist_filter_terms where id=new.coverage_id;
 select * into k from public.checklist_filter_terms where id=new.document_kind_id;
 if s.id is null or c.id is null or d.id is null or z.id is null or k.id is null
   or s.organization_id<>new.organization_id or c.organization_id<>new.organization_id
   or d.organization_id<>new.organization_id or z.organization_id<>new.organization_id
   or k.organization_id<>new.organization_id
   or s.dimension<>'sector' or c.dimension<>'service_class'
   or d.dimension<>'department' or z.dimension<>'coverage'
   or k.dimension<>'document_kind'
   or c.parent_id<>s.id or d.parent_id<>c.id or z.parent_id<>d.id
 then raise exception 'classification hierarchy invalid';end if;
 if tg_op='INSERT' or (new.sector_id<>old.sector_id or
   new.service_class_id<>old.service_class_id or new.department_id<>old.department_id
   or new.coverage_id<>old.coverage_id or new.document_kind_id<>old.document_kind_id) then
  if not (s.is_active and c.is_active and d.is_active and z.is_active and k.is_active)
  then raise exception 'new classification must use active terms';end if;
 end if;
 new.updated_at=now();
 return new;
end;
$$;
create trigger checklist_filter_assignment_guard before insert or update
on public.checklist_assignment_facets for each row execute function public.checklist_filter_validate_assignment();

-- Fixed default seed: explicit structure; names are editable through new terms,
-- not by destructive remapping of historical records.
create or replace function public.checklist_filter_seed(p_org uuid)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare sector uuid; hard uuid; soft uuid; dep uuid; v_service uuid;
 v_code text;v_en text;v_ar text;v_dept record;v_cov record;
begin
 if not exists(select 1 from public.organizations where id=p_org) then
  raise exception 'organization not found';end if;
 insert into public.checklist_filter_terms(organization_id,dimension,code,name_en,name_ar,sort_order)
 values(p_org,'sector','facilities','Facilities Management','إدارة المرافق',10)
 on conflict do nothing;
 select id into sector from public.checklist_filter_terms
 where organization_id=p_org and dimension='sector' and code='facilities';
 insert into public.checklist_filter_terms(organization_id,dimension,parent_id,code,name_en,name_ar,sort_order)
 values(p_org,'service_class',sector,'hard','Hard Services','الخدمات الفنية',10),
       (p_org,'service_class',sector,'soft','Soft Services','الخدمات اللينة',20)
 on conflict do nothing;
 select id into hard from public.checklist_filter_terms
 where organization_id=p_org and dimension='service_class' and parent_id=sector and code='hard';
 select id into soft from public.checklist_filter_terms
 where organization_id=p_org and dimension='service_class' and parent_id=sector and code='soft';
 insert into public.checklist_filter_terms(organization_id,dimension,parent_id,code,name_en,name_ar,sort_order)
 values(p_org,'department',hard,'general','General','عام',10),
 (p_org,'department',soft,'cleaning','Cleaning','النظافة',10),
 (p_org,'department',soft,'hospitality','Hospitality','الضيافة',20)
 on conflict do nothing;
 for v_dept in select id,code from public.checklist_filter_terms
 where organization_id=p_org and dimension='department' and parent_id in (hard,soft)
 loop
  insert into public.checklist_filter_terms(organization_id,dimension,parent_id,code,name_en,name_ar,sort_order)
  values(p_org,'coverage',v_dept.id,'general','Whole building / General','عام / كامل المبنى',10),
  (p_org,'coverage',v_dept.id,'washrooms','Washrooms','الحمامات',20),
  (p_org,'coverage',v_dept.id,'kitchens','Kitchens','المطابخ',30),
  (p_org,'coverage',v_dept.id,'pantries','Pantries','البانتري',40),
  (p_org,'coverage',v_dept.id,'offices','Offices','المكاتب',50),
  (p_org,'coverage',v_dept.id,'corridors','Corridors','الممرات',60),
  (p_org,'coverage',v_dept.id,'prayer_halls','Prayer halls','قاعات الصلاة',70),
  (p_org,'coverage',v_dept.id,'plant_rooms','Plant rooms','غرف المعدات',80),
  (p_org,'coverage',v_dept.id,'lobbies','Lobbies','الردهات',90),
  (p_org,'coverage',v_dept.id,'parking','Parking','مواقف السيارات',100),
  (p_org,'coverage',v_dept.id,'roofs','Roofs','الأسطح',110),
  (p_org,'coverage',v_dept.id,'stores','Stores','المخازن',120)
  on conflict do nothing;
 end loop;
 insert into public.checklist_filter_terms(organization_id,dimension,code,name_en,name_ar,sort_order)
 values(p_org,'document_kind','checklist','Daily Checklist','قائمة فحص يومية',10),
 (p_org,'document_kind','ppm','Planned Preventive Maintenance','الصيانة الوقائية',20),
 (p_org,'document_kind','safety','Safety Inspection','فحص السلامة',30),
 (p_org,'document_kind','inspection','Inspection','تفتيش',40),
 (p_org,'document_kind','audit','Audit','تدقيق',50),
 (p_org,'document_kind','risk_assessment','Risk Assessment','تقييم المخاطر',60),
 (p_org,'document_kind','method_statement','Method Statement','طريقة تنفيذ العمل',70),
 (p_org,'document_kind','itp','Inspection & Test Plan','خطة الفحص والاختبار',80),
 (p_org,'document_kind','ncr','Nonconformity','عدم المطابقة',90)
 on conflict do nothing;
end;
$$;

do $$ declare org record;begin
 for org in select id from public.organizations loop
  perform public.checklist_filter_seed(org.id);
 end loop;
end $$;
-- Seed taxonomy for newly registered organizations, without impacting other systems.
create or replace function public.checklist_filter_seed_on_new_org()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
begin perform public.checklist_filter_seed(new.id);return new;end;
$$;
create trigger checklist_filter_seed_new_org after insert on public.organizations
for each row execute function public.checklist_filter_seed_on_new_org();

create or replace function public.checklist_filter_default_assignment()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare sec uuid;svc uuid;dept uuid;cov uuid;kind uuid;
 service_code text;
begin
 perform public.checklist_filter_seed(new.organization_id);
 select id into sec from public.checklist_filter_terms
 where organization_id=new.organization_id and dimension='sector' and code='facilities';
 service_code:=case when new.service_type_code in ('cleaning','hygiene','soft_services')
  then 'soft' else 'hard' end;
 select id into svc from public.checklist_filter_terms
 where organization_id=new.organization_id and dimension='service_class'
 and parent_id=sec and code=service_code;
 select id into dept from public.checklist_filter_terms
 where organization_id=new.organization_id and dimension='department'
 and parent_id=svc and code=case when service_code='soft' then 'cleaning' else 'general' end;
 select id into cov from public.checklist_filter_terms
 where organization_id=new.organization_id and dimension='coverage'
 and parent_id=dept and code='general';
 select id into kind from public.checklist_filter_terms
 where organization_id=new.organization_id and dimension='document_kind'
 and code=case when new.service_type_code='safety' then 'safety' else 'checklist' end;
 insert into public.checklist_assignment_facets
  (assignment_id,organization_id,sector_id,service_class_id,department_id,coverage_id,document_kind_id)
 values(new.id,new.organization_id,sec,svc,dept,cov,kind)
 on conflict (assignment_id) do nothing;
 return new;
end;$$;
create trigger checklist_filter_assignment_default after insert
on public.checklist_assignments for each row execute function public.checklist_filter_default_assignment();

-- Backfill the 29 existing hierarchy assignments without touching inspections.
insert into public.checklist_assignment_facets
 (assignment_id,organization_id,sector_id,service_class_id,department_id,coverage_id,document_kind_id)
select a.id,a.organization_id,sector.id,svc.id,dept.id,cov.id,k.id
from public.checklist_assignments a
join public.checklist_filter_terms sector on sector.organization_id=a.organization_id
 and sector.dimension='sector' and sector.code='facilities'
join public.checklist_filter_terms svc on svc.organization_id=a.organization_id
 and svc.dimension='service_class' and svc.parent_id=sector.id
 and svc.code=case when a.service_type_code in ('cleaning','hygiene','soft_services')
  then 'soft' else 'hard' end
join public.checklist_filter_terms dept on dept.organization_id=a.organization_id
 and dept.dimension='department' and dept.parent_id=svc.id
 and dept.code=case when svc.code='soft' then 'cleaning' else 'general' end
join public.checklist_filter_terms cov on cov.organization_id=a.organization_id
 and cov.dimension='coverage' and cov.parent_id=dept.id and cov.code='general'
join public.checklist_filter_terms k on k.organization_id=a.organization_id
 and k.dimension='document_kind'
 and k.code=case when a.service_type_code='safety' then 'safety' else 'checklist' end
on conflict (assignment_id) do nothing;

-- Backfill only unambiguous area classifications; unknown areas stay General.
update public.checklist_assignment_facets f
set coverage_id=term.id
from public.checklist_assignments a,
 public.facility_areas area,
 public.checklist_filter_terms term
where a.id=f.assignment_id and area.id=a.area_id
 and term.organization_id=f.organization_id
 and term.dimension='coverage' and term.parent_id=f.department_id
 and term.code=case area.area_type
   when 'washroom' then 'washrooms'
   when 'office' then 'offices'
   when 'prayer_hall' then 'prayer_halls'
   when 'plant_room' then 'plant_rooms'
   when 'kitchen' then 'kitchens'
   when 'pantry' then 'pantries'
   when 'corridor' then 'corridors'
   when 'parking' then 'parking'
   when 'roof' then 'roofs'
   when 'store' then 'stores'
   else 'general' end;

-- The only public reader sees labels strictly for the assignment IDs returned
-- by the existing location + service-access authorized scope RPC.
create or replace function public.list_my_checklist_filter_facets(
 p_requirement text default 'read'
) returns setof jsonb language sql stable security definer
set search_path=public,pg_temp set row_security=off as $$
 select jsonb_build_object(
  'assignment_id',a.assignment_id,
  'sector_id',s.id,'sector_name_en',s.name_en,'sector_name_ar',s.name_ar,
  'service_class_id',c.id,'service_class_name_en',c.name_en,'service_class_name_ar',c.name_ar,
  'department_id',d.id,'department_name_en',d.name_en,'department_name_ar',d.name_ar,
  'coverage_id',v.id,'coverage_name_en',v.name_en,'coverage_name_ar',v.name_ar,
  'document_kind_id',k.id,'document_kind_name_en',k.name_en,'document_kind_name_ar',k.name_ar
 )
 from public.list_my_checklist_location_scope(p_requirement) accessible
 join public.checklist_assignment_facets a on a.assignment_id=accessible.assignment_id
 join public.checklist_filter_terms s on s.id=a.sector_id
 join public.checklist_filter_terms c on c.id=a.service_class_id
 join public.checklist_filter_terms d on d.id=a.department_id
 join public.checklist_filter_terms v on v.id=a.coverage_id
 join public.checklist_filter_terms k on k.id=a.document_kind_id
 where auth.uid() is not null
$$;
create or replace function public.list_org_checklist_filter_terms(p_org uuid)
returns setof jsonb language sql stable security definer
set search_path=public,pg_temp set row_security=off as $$
 select jsonb_build_object('id',id,'organization_id',organization_id,
  'dimension',dimension,'parent_id',parent_id,
  'code',code,'name_en',name_en,'name_ar',name_ar,
  'is_active',is_active,'sort_order',sort_order)
 from public.checklist_filter_terms
 where organization_id=p_org and
 (public.is_platform_owner() or public.is_org_super_admin(p_org))
 order by dimension,sort_order,name_en
$$;

create or replace function public.manage_checklist_filter_term(
 p_org uuid,p_dimension text,p_parent uuid,p_code text,
 p_name_en text,p_name_ar text,p_archive_id uuid default null
) returns uuid language plpgsql security definer
set search_path=public,pg_temp as $$
declare v_id uuid;
begin
 if auth.uid() is null or not (public.is_platform_owner() or public.is_org_super_admin(p_org))
 then raise exception 'organization taxonomy management denied' using errcode='42501';end if;
 if p_archive_id is not null then
  select id into v_id from public.checklist_filter_terms
   where id=p_archive_id and organization_id=p_org for update;
  if v_id is null then raise exception 'term not found';end if;
  -- Default assignments must always have a valid General area and kind.
  if exists(select 1 from public.checklist_filter_terms where id=v_id and
    ((dimension='coverage' and code='general') or
     (dimension='document_kind' and code in ('checklist','safety')))) then
    raise exception 'system fallback category cannot be archived';end if;
  if exists(select 1 from public.checklist_filter_terms
   where parent_id=v_id and is_active) or
   exists(select 1 from public.checklist_assignment_facets
    where sector_id=v_id or service_class_id=v_id or department_id=v_id
     or coverage_id=v_id or document_kind_id=v_id)
  then raise exception 'cannot archive a term while used by checklists or child terms';end if;
  update public.checklist_filter_terms set is_active=false where id=v_id;
  return v_id;
 end if;
 if p_code is null or p_name_en is null or p_name_ar is null then
  raise exception 'code and bilingual names required';end if;
 insert into public.checklist_filter_terms
  (organization_id,dimension,parent_id,code,name_en,name_ar)
 values(p_org,p_dimension,p_parent,lower(btrim(p_code)),btrim(p_name_en),btrim(p_name_ar))
 returning id into v_id;
 return v_id;
end;
$$;

create or replace function public.set_checklist_assignment_facets(
 p_assignment uuid,p_sector uuid,p_service_class uuid,p_department uuid,
 p_coverage uuid,p_document_kind uuid
) returns void language plpgsql security definer
set search_path=public,pg_temp as $$
declare a public.checklist_assignments%rowtype;
 z uuid;
begin
 select * into a from public.checklist_assignments where id=p_assignment for update;
 if a.id is null then raise exception 'assignment not found';end if;
 select zone_id into z from public.sites where id=a.site_id;
 if auth.uid() is null or not coalesce(public.location_access_allows(
 a.organization_id,z,a.site_id,a.building_id,a.floor_id,a.area_id,'manage'),false)
 then raise exception 'no permission to manage this checklist' using errcode='42501';end if;
 insert into public.checklist_assignment_facets
 (assignment_id,organization_id,sector_id,service_class_id,department_id,coverage_id,
  document_kind_id,updated_by)
 values(a.id,a.organization_id,p_sector,p_service_class,p_department,p_coverage,
  p_document_kind,auth.uid())
 on conflict(assignment_id) do update set
  sector_id=excluded.sector_id,service_class_id=excluded.service_class_id,
  department_id=excluded.department_id,coverage_id=excluded.coverage_id,
  document_kind_id=excluded.document_kind_id,updated_by=auth.uid();
end;$$;

alter table public.checklist_filter_terms enable row level security;
alter table public.checklist_assignment_facets enable row level security;
revoke all on public.checklist_filter_terms,public.checklist_assignment_facets
 from public,anon,authenticated;
revoke all on function public.checklist_filter_seed(uuid),
 public.list_my_checklist_filter_facets(text),
 public.list_org_checklist_filter_terms(uuid),
 public.manage_checklist_filter_term(uuid,text,uuid,text,text,text,uuid),
 public.set_checklist_assignment_facets(uuid,uuid,uuid,uuid,uuid,uuid)
 from public,anon;
grant execute on function public.list_my_checklist_filter_facets(text),
 public.list_org_checklist_filter_terms(uuid),
 public.manage_checklist_filter_term(uuid,text,uuid,text,text,text,uuid),
 public.set_checklist_assignment_facets(uuid,uuid,uuid,uuid,uuid,uuid)
 to authenticated;
-- Invoked only by the trusted table triggers / migration owner.
