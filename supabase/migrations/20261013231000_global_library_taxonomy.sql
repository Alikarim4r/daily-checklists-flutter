-- GLOB-001 P1-01/02: Global Library 2.0, additive schema and deterministic backfill.
-- Keeps legacy category_id, checklist_categories, RLS, billing, old RPCs,
-- organization copies, revision history and signed/printed A4 records intact.
create table if not exists public.library_taxonomy_terms (
  id uuid primary key default gen_random_uuid(),
  dimension text not null check (dimension in ('industry','domain','subdomain')),
  slug text not null check (slug ~ '^[a-z][a-z0-9_]*$'),
  name_en text not null check (length(trim(name_en)) > 0),
  name_ar text not null check (length(trim(name_ar)) > 0),
  translations jsonb not null default '{}'::jsonb check (jsonb_typeof(translations) = 'object'),
  parent_id uuid references public.library_taxonomy_terms(id) on delete restrict,
  sort_order int not null default 0,
  is_active boolean not null default true,
  unique (dimension, slug),
  check (parent_id is null or parent_id <> id)
);
create index if not exists library_taxonomy_parent_idx
  on public.library_taxonomy_terms(parent_id);

-- A parent must be a domain for a subdomain, or another subdomain;
-- and no update may introduce an ancestry cycle.
create or replace function public.validate_global_library_taxonomy_parent()
returns trigger language plpgsql set search_path = public as $$
declare v_parent_dimension text; v_cycle boolean;
begin
  if new.parent_id is null then return new; end if;
  select dimension into v_parent_dimension
    from public.library_taxonomy_terms where id = new.parent_id;
  if v_parent_dimension is null
     or new.dimension <> 'subdomain'
     or v_parent_dimension not in ('domain','subdomain') then
    raise exception 'taxonomy parent must be a domain/subdomain of a subdomain';
  end if;
  with recursive ancestors as (
    select id, parent_id, array[id] as visited
      from public.library_taxonomy_terms where id = new.parent_id
    union all
    select p.id, p.parent_id, a.visited || p.id
      from ancestors a
      join public.library_taxonomy_terms p on p.id = a.parent_id
      where not p.id = any(a.visited)
  )
  select exists(select 1 from ancestors where id = new.id)
  into v_cycle;
  if v_cycle then raise exception 'taxonomy ancestry cycle'; end if;
  return new;
end;
$$;
drop trigger if exists library_taxonomy_parent_guard on public.library_taxonomy_terms;
create trigger library_taxonomy_parent_guard
  before insert or update of parent_id, dimension
  on public.library_taxonomy_terms
  for each row execute function public.validate_global_library_taxonomy_parent();

create table if not exists public.library_document_kinds (
  kind_code text primary key check (kind_code ~ '^[a-z][a-z0-9_]*$'),
  name_en text not null,
  name_ar text not null,
  execution_engine_code text,
  is_executable boolean not null default false,
  sort_order int not null default 0
);
create table if not exists public.library_template_classification (
  template_id uuid primary key references public.checklist_library_templates(id) on delete cascade,
  document_kind text not null default 'checklist' references public.library_document_kinds(kind_code),
  validation_status text not null default 'unreviewed'
    check (validation_status in ('unreviewed','internal_review','expert_reviewed')),
  frequency_hint text check (frequency_hint is null or frequency_hint in
    ('one_time','daily','weekly','monthly','quarterly','biannual','annual','custom')),
  updated_at timestamptz not null default now()
);
create index if not exists library_template_classification_kind_idx
  on public.library_template_classification(document_kind, template_id);

create table if not exists public.library_template_taxonomy (
  template_id uuid not null references public.checklist_library_templates(id) on delete cascade,
  term_id uuid not null references public.library_taxonomy_terms(id) on delete restrict,
  primary key (template_id, term_id)
);
create index if not exists library_template_taxonomy_term_idx
  on public.library_template_taxonomy(term_id, template_id);

create table if not exists public.library_template_jurisdiction (
  id uuid primary key default gen_random_uuid(),
  template_id uuid not null references public.checklist_library_templates(id) on delete cascade,
  country_code text check (country_code is null or country_code ~ '^[A-Z]{2}$'),
  standard_code text,
  standard_edition text,
  review_status text not null default 'not_reviewed'
    check (review_status in ('not_reviewed','under_review','reviewed')),
  reviewer_note text,
  reviewed_at timestamptz,
  unique nulls not distinct (template_id, country_code, standard_code, standard_edition)
);
create index if not exists library_template_jurisdiction_lookup_idx
  on public.library_template_jurisdiction(template_id, country_code);

create table if not exists public.library_template_locales (
  template_id uuid not null references public.checklist_library_templates(id) on delete cascade,
  locale text not null check (locale ~ '^[a-z]{2,3}(-[A-Za-z0-9]{2,8})*$'),
  name text not null check (length(trim(name)) > 0),
  description text,
  primary key (template_id, locale)
);

-- No public/anonymous writes to taxonomy or review claims.
alter table public.library_taxonomy_terms enable row level security;
alter table public.library_document_kinds enable row level security;
alter table public.library_template_classification enable row level security;
alter table public.library_template_taxonomy enable row level security;
alter table public.library_template_jurisdiction enable row level security;
alter table public.library_template_locales enable row level security;

create policy global_terms_read on public.library_taxonomy_terms
 for select to authenticated using (
   public.is_platform_owner() or public.is_approved_active_user()
 );
create policy global_terms_owner_write on public.library_taxonomy_terms
 for all to authenticated using (public.is_platform_owner())
 with check (public.is_platform_owner());
create policy global_kinds_read on public.library_document_kinds
 for select to authenticated using (
   public.is_platform_owner() or public.is_approved_active_user()
 );
create policy global_kinds_owner_write on public.library_document_kinds
 for all to authenticated using (public.is_platform_owner())
 with check (public.is_platform_owner());

-- Draft/global unpublished content is owner-only. Published metadata may be
-- browsed, but item bodies remain behind the existing entitlement checks.
create policy global_classification_read on public.library_template_classification
 for select to authenticated using (
   public.is_platform_owner() or (
     public.is_approved_active_user() and exists (
       select 1 from public.checklist_library_templates t
         where t.id = template_id and t.is_published
     )
   )
 );
create policy global_classification_owner_write on public.library_template_classification
 for all to authenticated using (public.is_platform_owner())
 with check (public.is_platform_owner());
create policy global_taxonomy_map_read on public.library_template_taxonomy
 for select to authenticated using (
   public.is_platform_owner() or (
     public.is_approved_active_user() and exists (
       select 1 from public.checklist_library_templates t
         where t.id = template_id and t.is_published
     )
   )
 );
create policy global_taxonomy_map_owner_write on public.library_template_taxonomy
 for all to authenticated using (public.is_platform_owner())
 with check (public.is_platform_owner());
create policy global_jurisdiction_read on public.library_template_jurisdiction
 for select to authenticated using (
   public.is_platform_owner() or (
     public.is_approved_active_user() and exists (
       select 1 from public.checklist_library_templates t
         where t.id = template_id and t.is_published
     )
   )
 );
create policy global_jurisdiction_owner_write on public.library_template_jurisdiction
 for all to authenticated using (public.is_platform_owner())
 with check (public.is_platform_owner());
create policy global_locale_read on public.library_template_locales
 for select to authenticated using (
   public.is_platform_owner() or (
     public.is_approved_active_user() and exists (
       select 1 from public.checklist_library_templates t
         where t.id = template_id and t.is_published
     )
   )
 );
create policy global_locale_owner_write on public.library_template_locales
 for all to authenticated using (public.is_platform_owner())
 with check (public.is_platform_owner());

-- Curated initial terms are seed metadata, not statements of local compliance.
insert into public.library_taxonomy_terms
(dimension, slug, name_en, name_ar, sort_order) values
('industry','facilities','Facilities Management','إدارة المرافق',10),
('industry','hospitality','Hospitality','الضيافة والفنادق',20),
('industry','food_beverage','Food & Beverage','الأغذية والمشروبات',30),
('industry','healthcare','Healthcare Operations','تشغيل المرافق الصحية',40),
('industry','education','Education','التعليم',50),
('industry','manufacturing','Manufacturing','التصنيع',60),
('industry','construction','Construction','الإنشاءات',70),
('industry','agriculture','Agriculture & Landscaping','الزراعة والتشجير',80),
('industry','logistics','Logistics & Warehousing','الخدمات اللوجستية والمخازن',90),
('industry','retail','Retail','التجزئة',100),
('industry','energy','Energy & Utilities','الطاقة والمرافق',110),
('industry','government','Government & Public Services','الجهات والخدمات الحكومية',120),
('industry','residential','Residential & Property','السكن والعقارات',130),
('industry','transport','Transportation','النقل',140),
('industry','environmental','Environmental Services','الخدمات البيئية',150),
('industry','laboratory','Laboratories','المختبرات',160),
('industry','worship','Worship Facilities','دور العبادة',170),
('industry','leisure','Sports & Leisure','الرياضة والترفيه',180),
('industry','security','Security Services','الخدمات الأمنية',190),
('domain','cleaning','Cleaning & Hygiene','النظافة والتعقيم',10),
('domain','hvac','HVAC & Refrigeration','التكييف والتبريد',20),
('domain','electrical','Electrical Systems','الأنظمة الكهربائية',30),
('domain','mechanical','Mechanical Systems','الأنظمة الميكانيكية',40),
('domain','irrigation','Irrigation & Landscaping','الري والتشجير',50),
('domain','hse','Health & Safety','الصحة والسلامة',60),
('domain','fire_safety','Fire & Life Safety','الحريق وسلامة الأرواح',70),
('domain','food_safety','Food Hygiene & Safety','سلامة الأغذية',80),
('domain','quality','Quality & Audits','الجودة والتدقيق',90),
('domain','logistics','Storage & Logistics','التخزين واللوجستيات',100),
('domain','security','Security Operations','العمليات الأمنية',110),
('domain','environmental','Environment & Waste','البيئة والنفايات',120),
('domain','workplace','Workplace Operations','العمليات المكتبية',130),
('domain','healthcare','Healthcare Operations','تشغيل المرافق الصحية',140),
('domain','laboratory','Laboratory Operations','تشغيل المختبرات',150),
('domain','education','Educational Facilities','المرافق التعليمية',160),
('domain','mobility','Transport & Mobility','النقل والتنقل',170),
('domain','residential','Property Operations','تشغيل العقارات',180)
on conflict (dimension,slug) do update
set name_en=excluded.name_en,name_ar=excluded.name_ar,sort_order=excluded.sort_order;

insert into public.library_document_kinds
(kind_code,name_en,name_ar,execution_engine_code,is_executable,sort_order) values
('checklist','Checklist','قائمة فحص','checklist',true,10),
('inspection','Inspection','تفتيش',null,false,20),
('audit','Audit','تدقيق',null,false,30),
('ppm','Preventive Maintenance','الصيانة الوقائية المجدولة',null,false,40),
('method_statement','Method Statement','طريقة تنفيذ الأعمال',null,false,50),
('risk_assessment','Risk Assessment','تقييم المخاطر',null,false,60),
('jsa','Job Safety Analysis','تحليل مخاطر العمل',null,false,70),
('sop','Standard Operating Procedure','إجراء تشغيلي قياسي',null,false,80),
('cop','Code of Practice','مدونة الممارسات',null,false,90),
('ptw','Permit to Work','تصريح عمل',null,false,100),
('itp','Inspection & Test Plan','خطة الفحص والاختبار',null,false,110),
('ncr','Nonconformity Report','تقرير عدم المطابقة',null,false,120),
('asset_register','Asset Register','سجل الأصول',null,false,130)
on conflict(kind_code) do update
set name_en=excluded.name_en,name_ar=excluded.name_ar,
    execution_engine_code=excluded.execution_engine_code,
    is_executable=excluded.is_executable,
    sort_order=excluded.sort_order;

-- Repeatable + non-destructive backfill; new templates default to checklist.
insert into public.library_template_classification(template_id,document_kind)
select id,'checklist' from public.checklist_library_templates
on conflict(template_id) do nothing;

-- Deterministic bridge from legacy catalog categories; preserve legacy FK.
-- Categories may carry multiple industries and more than one domain.
with category_mapping(category_slug, industry_slugs, domain_slugs) as (
 values
 ('education',array['education','facilities'],array['education','hse']),
 ('hygiene',array['facilities','hospitality'],array['cleaning']),
 ('workplace',array['facilities','government'],array['workplace']),
 ('worship',array['worship','facilities'],array['workplace','cleaning']),
 ('hospitality',array['hospitality','facilities'],array['cleaning','workplace']),
 ('food_beverage',array['food_beverage','hospitality'],array['food_safety','cleaning']),
 ('healthcare',array['healthcare','facilities'],array['healthcare','hse']),
 ('laboratory',array['laboratory','healthcare'],array['laboratory','hse']),
 ('leisure',array['leisure','facilities'],array['hse','workplace']),
 ('technical',array['facilities','energy'],array['mechanical','hvac','electrical']),
 ('storage',array['logistics','facilities'],array['logistics','hse']),
 ('outdoor',array['agriculture','facilities'],array['irrigation','hse']),
 ('security',array['security','government'],array['security']),
 ('retail_public',array['retail','government'],array['workplace','security']),
 ('environmental',array['environmental','facilities'],array['environmental']),
 ('fire_life_safety',array['facilities','construction'],array['fire_safety','hse']),
 ('transport',array['transport','facilities'],array['mobility','electrical']),
 ('residential',array['residential','facilities'],array['residential','cleaning'])
)
insert into public.library_template_taxonomy(template_id,term_id)
select t.id, x.id
from public.checklist_library_templates t
join public.checklist_library_categories c on c.id=t.category_id
join category_mapping m on m.category_slug=c.slug
join public.library_taxonomy_terms x on
  (x.dimension='industry' and x.slug=any(m.industry_slugs))
  or (x.dimension='domain' and x.slug=any(m.domain_slugs))
on conflict do nothing;

-- Supplement based on exact known checklist slugs, not fuzzy guessing.
with slug_terms(template_slug,dimension,term_slug) as (
 values
 ('landscape_irrigation','domain','irrigation'),
 ('chiller_plant','domain','hvac'),
 ('ahu_fan_room','domain','hvac'),
 ('electrical_room','domain','electrical'),
 ('fire_alarm_control_panel','domain','fire_safety'),
 ('fire_door_inspection','domain','fire_safety'),
 ('chemical_store','domain','hse'),
 ('pest_control_monitoring','domain','cleaning'),
 ('commercial_kitchen','domain','food_safety'),
 ('clinic_first_aid','domain','healthcare')
)
insert into public.library_template_taxonomy(template_id,term_id)
select t.id,term.id
from slug_terms m
join public.checklist_library_templates t on t.slug=m.template_slug
join public.library_taxonomy_terms term
  on term.dimension=m.dimension and term.slug=m.term_slug
on conflict do nothing;
