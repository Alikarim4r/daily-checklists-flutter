-- =============================================================================
-- Daily Checklists — catalog templates, review workflow, org policies
-- Migration: 008_admin_catalog_policies.sql
-- =============================================================================

-- Review workflow (viewer sees approved; site_admin edits submitted)
create type public.checklist_review_status as enum (
  'draft',
  'submitted',
  'approved'
);

alter table public.checklist_inspections
  add column if not exists review_status public.checklist_review_status
    not null default 'draft';

alter table public.checklist_inspections
  add column if not exists approved_at timestamptz;

alter table public.checklist_inspections
  add column if not exists approved_by uuid references public.profiles (id) on delete set null;

-- Backfill: submitted inspections become approved so existing viewer flow keeps working
update public.checklist_inspections
set review_status = case
  when status = 'submitted' then 'approved'::public.checklist_review_status
  else 'draft'::public.checklist_review_status
end
where true;

create index if not exists checklist_inspections_review_status_idx
  on public.checklist_inspections (review_status);

-- Catalog templates
create table if not exists public.checklist_templates (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name_en text not null,
  name_ar text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint checklist_templates_code_format check (code ~ '^[A-Z][A-Z0-9_]*$')
);

create trigger checklist_templates_set_updated_at
  before update on public.checklist_templates
  for each row execute function public.set_updated_at();

create table if not exists public.checklist_template_items (
  id uuid primary key default gen_random_uuid(),
  template_id uuid not null references public.checklist_templates (id) on delete cascade,
  item_index int not null,
  default_answer text not null default 'Y',
  description_en text not null,
  description_ar text,
  description_bn text,
  description_hi text,
  description_ml text,
  sort_order int not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint checklist_template_items_unique unique (template_id, item_index),
  constraint checklist_template_items_default_chk
    check (default_answer in ('Y', 'N', 'NA'))
);

create trigger checklist_template_items_set_updated_at
  before update on public.checklist_template_items
  for each row execute function public.set_updated_at();

create index if not exists checklist_template_items_template_idx
  on public.checklist_template_items (template_id, sort_order);

-- Per-site extra items on top of template
create table if not exists public.site_checklist_items (
  id uuid primary key default gen_random_uuid(),
  site_id uuid not null references public.sites (id) on delete cascade,
  item_index int not null,
  default_answer text not null default 'Y',
  description_en text not null,
  description_ar text,
  sort_order int not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint site_checklist_items_unique unique (site_id, item_index),
  constraint site_checklist_items_default_chk
    check (default_answer in ('Y', 'N', 'NA'))
);

create trigger site_checklist_items_set_updated_at
  before update on public.site_checklist_items
  for each row execute function public.set_updated_at();

-- Org policies (photos + overdue)
create type public.policy_severity as enum ('info', 'warning', 'critical');

create table if not exists public.checklist_org_policies (
  organization_id uuid primary key references public.organizations (id) on delete cascade,
  photo_required_on_problem boolean not null default true,
  missing_photo_severity public.policy_severity not null default 'warning',
  require_fix_photo boolean not null default false,
  ongoing_problem_overdue_days int not null default 3,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint checklist_org_policies_overdue_positive
    check (ongoing_problem_overdue_days >= 0)
);

create trigger checklist_org_policies_set_updated_at
  before update on public.checklist_org_policies
  for each row execute function public.set_updated_at();

insert into public.checklist_org_policies (organization_id)
select id from public.organizations
on conflict (organization_id) do nothing;

-- RLS
alter table public.checklist_templates enable row level security;
alter table public.checklist_template_items enable row level security;
alter table public.site_checklist_items enable row level security;
alter table public.checklist_org_policies enable row level security;

drop policy if exists checklist_templates_select on public.checklist_templates;
create policy checklist_templates_select on public.checklist_templates
  for select to authenticated
  using (public.is_approved_active_user() or public.is_platform_owner());

drop policy if exists checklist_templates_write on public.checklist_templates;
create policy checklist_templates_write on public.checklist_templates
  for all to authenticated
  using (public.is_super_admin() or public.is_platform_owner())
  with check (public.is_super_admin() or public.is_platform_owner());

drop policy if exists checklist_template_items_select on public.checklist_template_items;
create policy checklist_template_items_select on public.checklist_template_items
  for select to authenticated
  using (public.is_approved_active_user() or public.is_platform_owner());

drop policy if exists checklist_template_items_write on public.checklist_template_items;
create policy checklist_template_items_write on public.checklist_template_items
  for all to authenticated
  using (public.is_super_admin() or public.is_platform_owner())
  with check (public.is_super_admin() or public.is_platform_owner());

drop policy if exists site_checklist_items_select on public.site_checklist_items;
create policy site_checklist_items_select on public.site_checklist_items
  for select to authenticated
  using (
    public.is_platform_owner()
    or public.is_super_admin()
    or public.has_site_access(site_id)
  );

drop policy if exists site_checklist_items_write on public.site_checklist_items;
create policy site_checklist_items_write on public.site_checklist_items
  for all to authenticated
  using (
    public.is_platform_owner()
    or public.is_super_admin()
    or public.can_manage_site(site_id)
  )
  with check (
    public.is_platform_owner()
    or public.is_super_admin()
    or public.can_manage_site(site_id)
  );

drop policy if exists checklist_org_policies_select on public.checklist_org_policies;
create policy checklist_org_policies_select on public.checklist_org_policies
  for select to authenticated
  using (public.is_approved_active_user() or public.is_platform_owner());

drop policy if exists checklist_org_policies_write on public.checklist_org_policies;
create policy checklist_org_policies_write on public.checklist_org_policies
  for all to authenticated
  using (public.is_super_admin() or public.is_platform_owner())
  with check (public.is_super_admin() or public.is_platform_owner());

-- Approve inspection RPC
create or replace function public.admin_approve_inspection(p_inspection_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_site_id uuid;
begin
  if not (public.is_platform_owner() or public.is_approved_active_user()) then
    raise exception 'not allowed';
  end if;

  select site_id into v_site_id
  from public.checklist_inspections
  where id = p_inspection_id;

  if v_site_id is null then
    raise exception 'inspection not found';
  end if;

  if not (
    public.is_platform_owner()
    or public.is_super_admin()
    or public.can_manage_site(v_site_id)
  ) then
    raise exception 'not allowed to approve this inspection';
  end if;

  update public.checklist_inspections
  set
    review_status = 'approved',
    status = 'submitted',
    approved_at = now(),
    approved_by = auth.uid(),
    submitted_at = coalesce(submitted_at, now()),
    submitted_by = coalesce(submitted_by, auth.uid())
  where id = p_inspection_id;
end;
$$;

grant execute on function public.admin_approve_inspection(uuid) to authenticated;

-- When technician submits, mark review_status submitted
create or replace function public.mark_inspection_submitted()
returns trigger
language plpgsql
as $$
begin
  if new.status = 'submitted' and old.status is distinct from 'submitted' then
    if new.review_status = 'draft' then
      new.review_status = 'submitted';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists checklist_inspections_mark_submitted on public.checklist_inspections;
create trigger checklist_inspections_mark_submitted
  before update on public.checklist_inspections
  for each row execute function public.mark_inspection_submitted();

-- Auto-generated seed from kChecklistLists

insert into public.checklist_templates (code, name_en, name_ar, is_active)
values ('B2_DC', 'Building 2 Data Center', 'مركز بيانات المبنى 2', true)
on conflict (code) do update set name_en = excluded.name_en, name_ar = excluded.name_ar;


insert into public.checklist_template_items
  (template_id, item_index, default_answer, description_en, description_ar, sort_order, is_active)
select t.id, v.item_index, v.default_answer, v.description_en, v.description_ar, v.sort_order, true
from public.checklist_templates t
cross join (values
  (1, 'Y', 'Are the temperature parameters of the Data Center and UPS room within the set values?', 'هل معايير درجة الحرارة في مركز البيانات وغرفة UPS ضمن القيم المحددة؟', 1),
  (2, 'Y', 'Are all IT racks closed and secure?', 'هل جميع خزائن تقنية المعلومات مغلقة ومؤمنة؟', 2),
  (3, 'N', 'Is there any alarm or fault in the water leak detection system?', 'هل يوجد أي إنذار أو عطل في نظام الكشف عن تسرب المياه؟', 3),
  (4, 'N', 'Is there any alarm or fault in the VESDA VFT panels?', 'هل يوجد أي إنذار أو عطل في لوحات VESDA VFT؟', 4),
  (5, 'N', 'Is there any alarm or fault in the VESDA VLP panels?', 'هل يوجد أي إنذار أو عطل في لوحات VESDA VLP؟', 5),
  (6, 'N', 'Is there any alarm or fault in the FM200 panel of the Data Center and UPS room?', 'هل يوجد أي إنذار في لوحة FM200 لمركز البيانات وغرفة UPS؟', 6),
  (7, 'Y', 'Is the Data Center and UPS room space clean, with no unsecured items lying around?', 'هل غرف مركز البيانات وUPS نظيفة ولا توجد بها مواد غير مؤمنة؟', 7),
  (8, 'Y', 'Are all lights functioning normally with no flickering or busted lamps?', 'هل جميع الأضواء تعمل بشكل طبيعي دون وميض أو تلف؟', 8),
  (9, 'Y', 'Are the corridors inside the Data Center locked and secure?', 'هل الممرات داخل مركز البيانات مغلقة ومؤمنة؟', 9),
  (10, 'Y', 'Are the main doors of the Data Center and UPS room closing properly?', 'هل الأبواب الرئيسية لمركز البيانات وغرفة UPS تُغلق بشكل صحيح؟', 10),
  (11, 'Y', 'Is the autonomy of both 400 kVA UPS systems above 1000 minutes with no alarms?', 'هل استقلالية أنظمة UPS (400 كيلو فولت أمبير) تزيد عن 1000 دقيقة؟', 11),
  (12, 'N', 'Is there any abnormal sound or noise in the room from any equipment?', 'هل يوجد أي صوت أو ضجيج غير طبيعي صادر عن المعدات في الغرفة؟', 12)
) as v(item_index, default_answer, description_en, description_ar, sort_order)
where t.code = 'B2_DC'
on conflict (template_id, item_index) do update set
  default_answer = excluded.default_answer,
  description_en = excluded.description_en,
  description_ar = excluded.description_ar,
  sort_order = excluded.sort_order;


insert into public.checklist_templates (code, name_en, name_ar, is_active)
values ('B4', 'Building 4', 'المبنى 4', true)
on conflict (code) do update set name_en = excluded.name_en, name_ar = excluded.name_ar;


insert into public.checklist_template_items
  (template_id, item_index, default_answer, description_en, description_ar, sort_order, is_active)
select t.id, v.item_index, v.default_answer, v.description_en, v.description_ar, v.sort_order, true
from public.checklist_templates t
cross join (values
  (1, 'Y', 'Are all lights functioning normally with no flickering or busted lamps?', 'هل جميع الأضواء تعمل بشكل طبيعي؟', 1),
  (2, 'Y', 'Are the Lighting Control Systems (LCS) working as per schedule?', 'هل أنظمة التحكم في الإضاءة تعمل حسب الجدول الزمني؟', 2),
  (3, 'Y', 'Are all CBS systems indicating normal or healthy mode?', 'هل جميع أنظمة CBS تشير إلى الحالة الطبيعية؟', 3),
  (4, 'Y', 'Is there no abnormal sound or noise in the electrical room, AHU room, or UPS room?', 'هل تخلو الغرف الكهربائية وغرف AHU/UPS من الضجيج غير الطبيعي؟', 4),
  (5, 'Y', 'Are the SMDB / ESMDB / USMDB circuit breakers in the correct operational position?', 'هل قواطع الدوائر (SMDB/ESMDB/USMDB) في وضع التشغيل الصحيح؟', 5),
  (6, 'Y', 'Are all Distribution Board (DB) circuit breakers in the correct operational position?', 'هل جميع قواطع لوحات التوزيع (DB) في وضع التشغيل الصحيح؟', 6),
  (7, 'Y', 'Are the starter panels operating in Auto mode?', 'هل لوحات التشغيل (Starter Panels) تعمل في وضع Auto؟', 7),
  (8, 'Y', 'Is the UPS functioning normally and battery ventilation operating?', 'هل يعمل الـ UPS وتهوية غرفة البطاريات بشكل طبيعي؟', 8),
  (9, 'Y', 'Are all Access Control System (ACS) doors functioning normally?', 'هل جميع أبواب نظام التحكم في الدخول (ACS) تعمل بشكل سليم؟', 9),
  (10, 'Y', 'Are the digital signage systems operating normally?', 'هل أنظمة اللوحات الرقمية تعمل بشكل طبيعي؟', 10),
  (11, 'Y', 'Are the Audio-Visual (AV) systems in meeting rooms functioning normally?', 'هل أنظمة الصوت والصورة (AV) في غرف الاجتماعات تعمل بشكل سليم؟', 11),
  (12, 'Y', 'Is the Public Address (PA) rack/system functioning normally?', 'هل نظام الإذاعة الداخلية (PA) يعمل في الوضع الطبيعي؟', 12),
  (13, 'Y', 'Are AHUs, Exhaust Fans, and Fresh Air Fans functioning normally?', 'هل وحدات AHUs ومراوح السحب والضخ تعمل بشكل طبيعي؟', 13),
  (14, 'N', 'Is there any water leakage in the mechanical room?', 'هل يوجد أي تسرب للمياه في الغرفة الميكانيكية؟', 14),
  (15, 'N', 'Is there any abnormal sound or noise in the electrical/AHU/UPS rooms?', 'هل يوجد ضجيج غير طبيعي في غرف الكهرباء/AHU/UPS؟', 15),
  (16, 'Y', 'Are all VRV units working normally without any fault?', 'هل جميع وحدات VRV تعمل بشكل طبيعي دون أعطال؟', 16),
  (17, 'Y', 'Are all booster pumps working normally?', 'هل جميع مضخات التعزيز تعمل بشكل طبيعي؟', 17),
  (18, 'N', 'Is there any leakage or overflow from the domestic water tank (Roof)?', 'هل يوجد تسرب أو فيضان من خزان المياه العلوي؟', 18),
  (19, 'Y', 'Is the car park drainage near VIP lobby free from blockages?', 'هل تصريف مواقف السيارات بالقرب من ردهة VIP خالٍ من الانسدادات؟', 19)
) as v(item_index, default_answer, description_en, description_ar, sort_order)
where t.code = 'B4'
on conflict (template_id, item_index) do update set
  default_answer = excluded.default_answer,
  description_en = excluded.description_en,
  description_ar = excluded.description_ar,
  sort_order = excluded.sort_order;


insert into public.checklist_templates (code, name_en, name_ar, is_active)
values ('KNOWLEDGE_WALL', 'Knowledge Wall', 'جدار المعرفة', true)
on conflict (code) do update set name_en = excluded.name_en, name_ar = excluded.name_ar;


insert into public.checklist_template_items
  (template_id, item_index, default_answer, description_en, description_ar, sort_order, is_active)
select t.id, v.item_index, v.default_answer, v.description_en, v.description_ar, v.sort_order, true
from public.checklist_templates t
cross join (values
  (1, 'Y', 'Are all lights functioning normally?', 'هل جميع الأضواء تعمل بشكل طبيعي؟', 1),
  (2, 'Y', 'Are the Lighting Control Systems (LCS) working as per schedule?', 'هل أنظمة التحكم في الإضاءة تعمل حسب الجدول؟', 2),
  (3, 'Y', 'Are the CBS systems indicating normal mode?', 'هل أنظمة CBS تشير إلى الوضع الطبيعي؟', 3),
  (4, 'Y', 'Are all Access Control System (ACS) doors functioning normally?', 'هل جميع أبواب ACS تعمل بشكل سليم؟', 4),
  (5, 'Y', 'Are the digital signages functioning normally?', 'هل اللوحات الرقمية تعمل بشكل طبيعي؟', 5),
  (6, 'Y', 'Are the Air Handling Units (AHUs) functioning normally?', 'هل وحدات مناولة الهواء (AHUs) تعمل بشكل طبيعي؟', 6)
) as v(item_index, default_answer, description_en, description_ar, sort_order)
where t.code = 'KNOWLEDGE_WALL'
on conflict (template_id, item_index) do update set
  default_answer = excluded.default_answer,
  description_en = excluded.description_en,
  description_ar = excluded.description_ar,
  sort_order = excluded.sort_order;


insert into public.checklist_templates (code, name_en, name_ar, is_active)
values ('B7_PARKING', 'Building 7 Parking', 'مواقف المبنى 7', true)
on conflict (code) do update set name_en = excluded.name_en, name_ar = excluded.name_ar;


insert into public.checklist_template_items
  (template_id, item_index, default_answer, description_en, description_ar, sort_order, is_active)
select t.id, v.item_index, v.default_answer, v.description_en, v.description_ar, v.sort_order, true
from public.checklist_templates t
cross join (values
  (1, 'Y', 'Are all lights functioning normally?', 'هل جميع الأضواء تعمل بشكل طبيعي؟', 1),
  (2, 'Y', 'Are the Lighting Control Systems (LCS) working as per schedule?', 'هل أنظمة التحكم في الإضاءة تعمل حسب الجدول؟', 2),
  (3, 'Y', 'Are the Feeder Pillars functioning as per schedule?', 'هل تعمل صناديق التغذية (Feeder Pillars) حسب الجدول؟', 3),
  (4, 'Y', 'Are all CBS indicating normal mode?', 'هل جميع أنظمة CBS تشير للوضع الطبيعي؟', 4),
  (5, 'Y', 'Are the LV Panels circuit breakers at the correct position?', 'هل قواطع الدوائر في لوحات LV في الوضع الصحيح؟', 5),
  (6, 'Y', 'Are the capacitor bank / panel and battery charger operational?', 'هل لوحة مكثف التيار وشاحن البطارية يعملان؟', 6),
  (7, 'Y', 'Are SMDB’s / ESMDB’s / USMDB circuit breakers at correct position?', 'هل قواطع SMDB/ESMDB/USMDB في الوضع الصحيح؟', 7),
  (8, 'Y', 'Are all DB’s circuit breakers at the correct operational position?', 'هل جميع قواطع لوحات التوزيع (DB) في وضع التشغيل؟', 8),
  (9, 'Y', 'Are the starter panels operating in Auto mode?', 'هل لوحات التشغيل في وضع Auto؟', 9),
  (10, 'Y', 'Is the UPS functioning normally?', 'هل يعمل نظام الـ UPS بشكل طبيعي؟', 10),
  (11, 'Y', 'Are all ACS doors functioning normally?', 'هل جميع أبواب ACS تعمل بشكل سليم؟', 11),
  (12, 'Y', 'Are VRV units, split units, and extract fans functioning normally?', 'هل تعمل وحدات VRV والمكيفات ومراوح الشفط بشكل طبيعي؟', 12),
  (13, 'Y', 'Is the Fire Alarm System functioning normally?', 'هل يعمل نظام إنذار الحريق بشكل طبيعي؟', 13),
  (14, 'Y', 'Is the Fire Alarm System status recorded in the daily report?', 'هل تم تسجيل حالة نظام إنذار الحريق في التقرير اليومي؟', 14)
) as v(item_index, default_answer, description_en, description_ar, sort_order)
where t.code = 'B7_PARKING'
on conflict (template_id, item_index) do update set
  default_answer = excluded.default_answer,
  description_en = excluded.description_en,
  description_ar = excluded.description_ar,
  sort_order = excluded.sort_order;


insert into public.checklist_templates (code, name_en, name_ar, is_active)
values ('B7_MECH', 'Building 7 Mechanical', 'ميكانيكا المبنى 7', true)
on conflict (code) do update set name_en = excluded.name_en, name_ar = excluded.name_ar;


insert into public.checklist_template_items
  (template_id, item_index, default_answer, description_en, description_ar, sort_order, is_active)
select t.id, v.item_index, v.default_answer, v.description_en, v.description_ar, v.sort_order, true
from public.checklist_templates t
cross join (values
  (1, 'Y', 'Chillers: Are the chillers functioning normally?', 'المبردات: هل تعمل المبردات بشكل طبيعي؟', 1),
  (2, 'Y', 'Chillers: Are the measured data recorded?', 'المبردات: هل تم تسجيل البيانات المقاسة؟', 2),
  (3, 'Y', 'Chiller Room: Is the chemical dosing pump functioning normally?', 'غرفة المبردات: هل تعمل مضخة الجرعات الكيميائية بشكل طبيعي؟', 3),
  (4, 'Y', 'SCWP & PCWP: Are the pumps functioning normally?', 'المضخات: هل تعمل المضخات بشكل طبيعي؟', 4),
  (5, 'Y', 'SCWP & PCWP: Are the measured data recorded?', 'المضخات: هل تم تسجيل البيانات المقاسة؟', 5),
  (6, 'Y', 'Cooling Towers: Are the cooling towers functioning normally?', 'أبراج التبريد: هل تعمل أبراج التبريد بشكل طبيعي؟', 6),
  (7, 'Y', 'Cooling Towers: Are the measured data recorded?', 'أبراج التبريد: هل تم تسجيل البيانات المقاسة؟', 7),
  (8, 'Y', 'Cooling Towers: Is the chemical dosing system functioning normally?', 'أبراج التبريد: هل يعمل نظام الحقن الكيميائي بشكل سليم؟', 8),
  (9, 'Y', 'Condenser Pumps: Are the measured data recorded?', 'مضخات المكثف: هل تم تسجيل البيانات المقاسة؟', 9),
  (10, 'Y', 'Irrigation Room: Are the irrigation pumps functioning normally?', 'غرفة الري: هل تعمل مضخات الري بشكل طبيعي؟', 10),
  (11, 'Y', 'Irrigation Tank: Is the tank level normal?', 'خزان الري: هل مستوى الخزان طبيعي؟', 11),
  (12, 'Y', 'Potable Water: Is the system/pumps functioning normally?', 'المياه الصالحة للشرب: هل المضخات تعمل بشكل طبيعي؟', 12),
  (13, 'Y', 'Potable Water Tank: Is the tank level normal?', 'خزان مياه الشرب: هل مستوى الخزان طبيعي؟', 13),
  (14, 'Y', 'Make-up Water Tank: Is the system functioning normally?', 'خزان المياه التعويضي: هل النظام يعمل بشكل طبيعي؟', 14),
  (15, 'Y', 'Make-up Water Tank: Is the tank level normal?', 'خزان المياه التعويضي: هل مستوى الخزان طبيعي؟', 15),
  (16, 'Y', 'Storm Water Tank: Are the pumps functioning normally?', 'خزان مياه الأمطار: هل المضخات تعمل بشكل طبيعي؟', 16),
  (17, 'Y', 'Storm Water Tank: Is the tank level normal?', 'خزان مياه الأمطار: هل مستوى الخزان طبيعي؟', 17),
  (18, 'Y', 'RO Plant: Is the plant/pumps functioning normally?', 'محطة التحلية RO: هل المحطة تعمل بشكل طبيعي؟', 18),
  (19, 'Y', 'Fire Fighting: Are the electric pumps and jockey pump in Auto mode?', 'مكافحة الحريق: هل المضخة الكهربائية والجوكي في وضع Auto؟', 19),
  (20, 'Y', 'Fire Fighting Tank: Is the tank level normal?', 'خزان الحريق: هل مستوى الخزان طبيعي؟', 20),
  (21, 'Y', 'TSE Pump Room: Are the TSE pumps functioning normally?', 'غرفة مضخات TSE: هل تعمل المضخات بشكل طبيعي؟', 21),
  (22, 'Y', 'TSE / RO Plant: Is the water discharged accordingly?', 'محطة TSE/RO: هل يتم تصريف المياه وفقاً لذلك؟', 22)
) as v(item_index, default_answer, description_en, description_ar, sort_order)
where t.code = 'B7_MECH'
on conflict (template_id, item_index) do update set
  default_answer = excluded.default_answer,
  description_en = excluded.description_en,
  description_ar = excluded.description_ar,
  sort_order = excluded.sort_order;


insert into public.checklist_templates (code, name_en, name_ar, is_active)
values ('B7_BMS', 'Building 7 BMS', 'نظام BMS المبنى 7', true)
on conflict (code) do update set name_en = excluded.name_en, name_ar = excluded.name_ar;


insert into public.checklist_template_items
  (template_id, item_index, default_answer, description_en, description_ar, sort_order, is_active)
select t.id, v.item_index, v.default_answer, v.description_en, v.description_ar, v.sort_order, true
from public.checklist_templates t
cross join (values
  (1, 'Y', 'Is the BMS system functioning normal?', 'هل نظام BMS يعمل بشكل طبيعي؟', 1),
  (2, 'Y', 'Is the BMS network functioning normal?', 'هل شبكة الـ BMS تعمل بشكل طبيعي؟', 2),
  (3, 'Y', 'Are the chiller systems operating normal and maintaining set point?', 'هل تعمل أنظمة المبردات بشكل طبيعي وتحافظ على درجة الحرارة؟', 3),
  (4, 'Y', 'Are the AHUs operating normal and maintaining set point?', 'هل تعمل وحدات AHUs بشكل طبيعي وتحافظ على القيم؟', 4),
  (5, 'Y', 'Are the Fan Coil Units operating normal?', 'هل تعمل وحدات Fan Coil بشكل طبيعي؟', 5),
  (6, 'Y', 'Are the VAVs operating normal?', 'هل تعمل وحدات VAV بشكل طبيعي؟', 6),
  (7, 'Y', 'Are the Exhaust Fans operating normal (Auto)?', 'هل تعمل مراوح الشفط بشكل طبيعي (Auto)؟', 7),
  (8, 'Y', 'Are the Fresh Air Fans operating normal (Auto)?', 'هل تعمل مراوح الهواء النقي بشكل طبيعي (Auto)؟', 8),
  (9, 'Y', 'Are the Staircase Pressurization Fans operating normal?', 'هل تعمل مراوح ضغط الدرج بشكل طبيعي؟', 9),
  (10, 'Y', 'Is the Variable Refrigerant Flow (VRF) system operating normal?', 'هل يعمل نظام VRF بشكل طبيعي؟', 10),
  (11, 'Y', 'Are the CRAC units operating normal and maintaining set point?', 'هل تعمل وحدات CRAC بشكل طبيعي؟', 11),
  (12, 'Y', 'Is the Air-Cooled Chiller operating normal?', 'هل يعمل المبرد المبرد بالهواء بشكل طبيعي؟', 12),
  (13, 'Y', 'Is the Car Park CO monitoring system operating normal?', 'هل يعمل نظام مراقبة غاز CO في المواقف بشكل طبيعي؟', 13),
  (14, 'Y', 'Are the MDFs & MFSDs functioning normal?', 'هل تعمل وحدات MDFs و MFSDs بشكل طبيعي؟', 14),
  (15, 'Y', 'Are the LV panels operating normal?', 'هل لوحات LV تعمل بشكل طبيعي؟', 15),
  (16, 'Y', 'Are the generators operating within normal parameters (Auto)?', 'هل المولدات تعمل ضمن المعايير الطبيعية (Auto)؟', 16),
  (17, 'Y', 'Are the UPS systems operating within normal parameters?', 'هل أنظمة UPS تعمل ضمن المعايير الطبيعية؟', 17),
  (18, 'Y', 'Are the MVP meters functioning normal?', 'هل عدادات MVP تعمل بشكل طبيعي؟', 18),
  (19, 'Y', 'Are the transformers functioning normal?', 'هل المحولات تعمل بشكل طبيعي؟', 19),
  (20, 'Y', 'Are the feeder pillars operating normal?', 'هل تعمل صناديق التغذية بشكل طبيعي؟', 20),
  (21, 'Y', 'Are the roof booster pumps operating normal?', 'هل مضخات تعزيز السطح تعمل بشكل طبيعي؟', 21),
  (22, 'Y', 'Is the domestic water system operating normal?', 'هل نظام المياه المنزلي يعمل بشكل طبيعي؟', 22),
  (23, 'Y', 'Is the irrigation water system operating normal?', 'هل نظام مياه الري يعمل بشكل طبيعي؟', 23),
  (24, 'Y', 'Is the RO room operating normal?', 'هل غرفة الـ RO تعمل بشكل طبيعي؟', 24),
  (25, 'Y', 'Is the firefighting system operating normal?', 'هل نظام مكافحة الحريق يعمل بشكل طبيعي؟', 25),
  (26, 'Y', 'Are the storm water pumps operating normal?', 'هل تعمل مضخات مياه الأمطار بشكل طبيعي؟', 26),
  (27, 'Y', 'Is the fuel system operating normal?', 'هل يعمل نظام الوقود بشكل طبيعي؟', 27),
  (28, 'Y', 'Are the sump pumps operating normal?', 'هل تعمل مضخات الغطاس (Sump Pumps) بشكل طبيعي؟', 28),
  (29, 'Y', 'Is the fire alarm system operating normal?', 'هل يعمل نظام إنذار الحريق بشكل طبيعي؟', 29),
  (30, 'Y', 'Is the light control system operating normal?', 'هل يعمل نظام التحكم في الإضاءة بشكل طبيعي؟', 30),
  (31, 'Y', 'Is the public address system operating normal?', 'هل يعمل نظام الإذاعة العامة بشكل طبيعي؟', 31),
  (32, 'Y', 'Are the central battery systems operating normal?', 'هل تعمل أنظمة البطارية المركزية بشكل طبيعي؟', 32),
  (33, 'Y', 'Are the access control systems operating normal?', 'هل تعمل أنظمة التحكم في الدخول بشكل طبيعي؟', 33),
  (34, 'Y', 'Are the lifts/elevators operating normal?', 'هل تعمل المصاعد بشكل طبيعي؟', 34),
  (35, 'Y', 'Are the escalators operating normal?', 'هل تعمل السلالم المتحركة بشكل طبيعي؟', 35),
  (36, 'Y', 'Are the disabled toilet alarm systems operating normal?', 'هل أنظمة إنذار دورات المياه لذوي الإعاقة تعمل بشكل طبيعي؟', 36)
) as v(item_index, default_answer, description_en, description_ar, sort_order)
where t.code = 'B7_BMS'
on conflict (template_id, item_index) do update set
  default_answer = excluded.default_answer,
  description_en = excluded.description_en,
  description_ar = excluded.description_ar,
  sort_order = excluded.sort_order;


insert into public.checklist_templates (code, name_en, name_ar, is_active)
values ('DEFAULT', 'Default Checklist', 'القائمة الافتراضية', true)
on conflict (code) do update set name_en = excluded.name_en, name_ar = excluded.name_ar;


insert into public.checklist_template_items
  (template_id, item_index, default_answer, description_en, description_ar, sort_order, is_active)
select t.id, v.item_index, v.default_answer, v.description_en, v.description_ar, v.sort_order, true
from public.checklist_templates t
cross join (values
  (1, 'Y', 'Are all lights functioning normally?', 'هل جميع الأضواء تعمل بشكل طبيعي؟', 1),
  (2, 'Y', 'Are the Lighting Control Systems (LCS) working as per schedule?', 'هل أنظمة التحكم في الإضاءة تعمل حسب الجدول؟', 2),
  (3, 'Y', 'Are all CBS systems indicating normal or healthy status?', 'هل جميع أنظمة CBS تشير إلى الوضع الطبيعي؟', 3),
  (4, 'Y', 'Are the LV panel circuit breakers in the correct position?', 'هل قواطع الدوائر في لوحة LV في الوضع الصحيح؟', 4),
  (5, 'Y', 'Are the SMDB / ESMDB / USMDB circuit breakers in correct position?', 'هل قواطع SMDB/ESMDB/USMDB في الوضع الصحيح؟', 5),
  (6, 'Y', 'Are all Distribution Boards (DBs) circuit breakers in correct position?', 'هل جميع قواطع لوحات التوزيع في الوضع الصحيح؟', 6),
  (7, 'Y', 'Are the starter panels operating in Auto mode?', 'هل تعمل لوحات التشغيل في وضع Auto؟', 7),
  (8, 'Y', 'Is the UPS functioning normally and ventilation operating?', 'هل يعمل UPS وتهوية غرفة البطاريات بشكل سليم؟', 8),
  (9, 'Y', 'Are all Access Control System (ACS) doors functioning normally?', 'هل جميع أبواب ACS تعمل بشكل طبيعي؟', 9),
  (10, 'Y', 'Are the digital signage systems operating normally?', 'هل اللوحات الرقمية تعمل بشكل طبيعي؟', 10),
  (11, 'Y', 'Are the AV systems in meeting rooms functioning normally?', 'هل أنظمة AV في غرف الاجتماعات تعمل بشكل طبيعي؟', 11),
  (12, 'Y', 'Is the Public Address (PA) rack/system healthy?', 'هل نظام الإذاعة العامة يعمل بشكل سليم؟', 12),
  (13, 'Y', 'Are AHUs, Exhaust Fans, and Fresh Air Fans functioning normally?', 'هل تعمل وحدات AHUs ومراوح الشفط والضخ بشكل طبيعي؟', 13),
  (14, 'N', 'Is there any water leakage in the mechanical room?', 'هل يوجد أي تسرب مياه في الغرفة الميكانيكية؟', 14),
  (15, 'N', 'Is there any abnormal sound or noise in electrical/AHU/UPS rooms?', 'هل يوجد ضجيج غير طبيعي في غرف الكهرباء/AHU/UPS؟', 15),
  (16, 'Y', 'Are all VRV units working normally without fault?', 'هل تعمل وحدات VRV بشكل طبيعي دون أعطال؟', 16),
  (17, 'Y', 'Are all booster pumps working normally?', 'هل تعمل مضخات التعزيز بشكل طبيعي؟', 17),
  (18, 'N', 'Is there any leakage or overflow from the domestic tank?', 'هل يوجد تسرب أو فيضان من خزان المياه؟', 18)
) as v(item_index, default_answer, description_en, description_ar, sort_order)
where t.code = 'DEFAULT'
on conflict (template_id, item_index) do update set
  default_answer = excluded.default_answer,
  description_en = excluded.description_en,
  description_ar = excluded.description_ar,
  sort_order = excluded.sort_order;
-- done
