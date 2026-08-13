-- =============================================================================
-- Seed: Ministry of Awqaf and Islamic Affairs
-- Migration: 012_seed_awqaf_ministry.sql
-- Org + 3 zones + 6 mosques (campus) × 3 checklist units each
-- Templates: AWQAF_MEN_PRAYER, AWQAF_WUDU, AWQAF_IMAM_HOUSE
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Organization
-- ---------------------------------------------------------------------------
insert into public.organizations (id, name_en, name_ar, is_active)
values (
  'b0000000-0000-4000-8000-000000000001',
  'Ministry of Awqaf and Islamic Affairs',
  'وزارة الأوقاف والشؤون الإسلامية',
  true
)
on conflict (id) do update set
  name_en = excluded.name_en,
  name_ar = excluded.name_ar,
  is_active = true,
  updated_at = now();

insert into public.checklist_org_policies (organization_id)
values ('b0000000-0000-4000-8000-000000000001')
on conflict (organization_id) do nothing;

-- ---------------------------------------------------------------------------
-- Zones (3)
-- ---------------------------------------------------------------------------
insert into public.zones (id, organization_id, code, name_en, name_ar, is_active, sort_order)
values
  ('b0000000-0000-4000-8000-000000000010',
   'b0000000-0000-4000-8000-000000000001',
   'doha_center', 'Doha Center', 'وسط الدوحة', true, 1),
  ('b0000000-0000-4000-8000-000000000011',
   'b0000000-0000-4000-8000-000000000001',
   'al_rayyan', 'Al Rayyan', 'الريان', true, 2),
  ('b0000000-0000-4000-8000-000000000012',
   'b0000000-0000-4000-8000-000000000001',
   'al_wakrah', 'Al Wakrah', 'الوكرة', true, 3)
on conflict (id) do update set
  code = excluded.code,
  name_en = excluded.name_en,
  name_ar = excluded.name_ar,
  is_active = true,
  sort_order = excluded.sort_order,
  updated_at = now();

-- ---------------------------------------------------------------------------
-- Default checklist templates (3)
-- ---------------------------------------------------------------------------
insert into public.checklist_templates (code, name_en, name_ar, is_active)
values
  ('AWQAF_MEN_PRAYER', 'Men Prayer Hall', 'مصلى الرجال', true),
  ('AWQAF_WUDU', 'Washrooms & Ablution', 'الحمامات والمواضيء', true),
  ('AWQAF_IMAM_HOUSE', 'Imam House', 'بيت الإمام', true)
on conflict (code) do update set
  name_en = excluded.name_en,
  name_ar = excluded.name_ar,
  is_active = true,
  updated_at = now();

-- NOTE: Item bodies for AWQAF_* are owned by 013_awqaf_maintenance_only_items.sql
-- (maintenance / faults only — no cleaning). Kept as noop here for 012 apply order.

-- ---------------------------------------------------------------------------
-- Mosques (campus) + 3 checklist units each
-- ---------------------------------------------------------------------------
-- Campus sites (no building_code)
insert into public.sites (
  id, organization_id, zone_id, parent_site_id,
  name_en, name_ar, site_type, location, is_active,
  building_code, pin, checklist_type
) values
  -- Doha Center
  ('b0000000-0000-4000-8000-000000000100', 'b0000000-0000-4000-8000-000000000001',
   'b0000000-0000-4000-8000-000000000010', null,
   'Mosque of Imam Muhammad ibn Abdul Wahhab Area — Sample A',
   'مسجد منطقة الإمام محمد بن عبد الوهاب — نموذج أ',
   'other', 'Doha, Qatar', true, null, null, 'DEFAULT'),
  ('b0000000-0000-4000-8000-000000000101', 'b0000000-0000-4000-8000-000000000001',
   'b0000000-0000-4000-8000-000000000010', null,
   'Fereej Al Nasr Mosque — Sample B',
   'مسجد فريج النصر — نموذج ب',
   'other', 'Doha, Qatar', true, null, null, 'DEFAULT'),
  -- Al Rayyan
  ('b0000000-0000-4000-8000-000000000102', 'b0000000-0000-4000-8000-000000000001',
   'b0000000-0000-4000-8000-000000000011', null,
   'Al Gharrafa Mosque — Sample C',
   'مسجد الغرافة — نموذج ج',
   'other', 'Al Rayyan, Qatar', true, null, null, 'DEFAULT'),
  ('b0000000-0000-4000-8000-000000000103', 'b0000000-0000-4000-8000-000000000001',
   'b0000000-0000-4000-8000-000000000011', null,
   'Old Airport / Rayyan Sample Mosque D',
   'مسجد الريان — نموذج د',
   'other', 'Al Rayyan, Qatar', true, null, null, 'DEFAULT'),
  -- Al Wakrah
  ('b0000000-0000-4000-8000-000000000104', 'b0000000-0000-4000-8000-000000000001',
   'b0000000-0000-4000-8000-000000000012', null,
   'Al Wakrah Grand Sample Mosque E',
   'مسجد الوكرة الكبير — نموذج هـ',
   'other', 'Al Wakrah, Qatar', true, null, null, 'DEFAULT'),
  ('b0000000-0000-4000-8000-000000000105', 'b0000000-0000-4000-8000-000000000001',
   'b0000000-0000-4000-8000-000000000012', null,
   'Al Wukair Sample Mosque F',
   'مسجد الوكير — نموذج و',
   'other', 'Al Wakrah, Qatar', true, null, null, 'DEFAULT')
on conflict (id) do update set
  name_en = excluded.name_en,
  name_ar = excluded.name_ar,
  zone_id = excluded.zone_id,
  parent_site_id = null,
  building_code = null,
  pin = null,
  checklist_type = 'DEFAULT',
  is_active = true,
  updated_at = now();

-- Checklist units under each mosque
insert into public.sites (
  id, organization_id, zone_id, parent_site_id,
  name_en, name_ar, site_type, location, is_active,
  building_code, pin, checklist_type
) values
  -- Mosque A
  ('b0000000-0000-4000-8000-000000000201', 'b0000000-0000-4000-8000-000000000001',
   'b0000000-0000-4000-8000-000000000010', 'b0000000-0000-4000-8000-000000000100',
   'Men Prayer Hall', 'مصلى الرجال', 'other', 'Doha, Qatar', true,
   'MSQ-A-MEN', 'AWQAF/A/MEN', 'AWQAF_MEN_PRAYER'),
  ('b0000000-0000-4000-8000-000000000202', 'b0000000-0000-4000-8000-000000000001',
   'b0000000-0000-4000-8000-000000000010', 'b0000000-0000-4000-8000-000000000100',
   'Washrooms & Ablution', 'الحمامات والمواضيء', 'other', 'Doha, Qatar', true,
   'MSQ-A-WUDU', 'AWQAF/A/WUDU', 'AWQAF_WUDU'),
  ('b0000000-0000-4000-8000-000000000203', 'b0000000-0000-4000-8000-000000000001',
   'b0000000-0000-4000-8000-000000000010', 'b0000000-0000-4000-8000-000000000100',
   'Imam House', 'بيت الإمام', 'other', 'Doha, Qatar', true,
   'MSQ-A-IMAM', 'AWQAF/A/IMAM', 'AWQAF_IMAM_HOUSE'),
  -- Mosque B
  ('b0000000-0000-4000-8000-000000000211', 'b0000000-0000-4000-8000-000000000001',
   'b0000000-0000-4000-8000-000000000010', 'b0000000-0000-4000-8000-000000000101',
   'Men Prayer Hall', 'مصلى الرجال', 'other', 'Doha, Qatar', true,
   'MSQ-B-MEN', 'AWQAF/B/MEN', 'AWQAF_MEN_PRAYER'),
  ('b0000000-0000-4000-8000-000000000212', 'b0000000-0000-4000-8000-000000000001',
   'b0000000-0000-4000-8000-000000000010', 'b0000000-0000-4000-8000-000000000101',
   'Washrooms & Ablution', 'الحمامات والمواضيء', 'other', 'Doha, Qatar', true,
   'MSQ-B-WUDU', 'AWQAF/B/WUDU', 'AWQAF_WUDU'),
  ('b0000000-0000-4000-8000-000000000213', 'b0000000-0000-4000-8000-000000000001',
   'b0000000-0000-4000-8000-000000000010', 'b0000000-0000-4000-8000-000000000101',
   'Imam House', 'بيت الإمام', 'other', 'Doha, Qatar', true,
   'MSQ-B-IMAM', 'AWQAF/B/IMAM', 'AWQAF_IMAM_HOUSE'),
  -- Mosque C
  ('b0000000-0000-4000-8000-000000000221', 'b0000000-0000-4000-8000-000000000001',
   'b0000000-0000-4000-8000-000000000011', 'b0000000-0000-4000-8000-000000000102',
   'Men Prayer Hall', 'مصلى الرجال', 'other', 'Al Rayyan, Qatar', true,
   'MSQ-C-MEN', 'AWQAF/C/MEN', 'AWQAF_MEN_PRAYER'),
  ('b0000000-0000-4000-8000-000000000222', 'b0000000-0000-4000-8000-000000000001',
   'b0000000-0000-4000-8000-000000000011', 'b0000000-0000-4000-8000-000000000102',
   'Washrooms & Ablution', 'الحمامات والمواضيء', 'other', 'Al Rayyan, Qatar', true,
   'MSQ-C-WUDU', 'AWQAF/C/WUDU', 'AWQAF_WUDU'),
  ('b0000000-0000-4000-8000-000000000223', 'b0000000-0000-4000-8000-000000000001',
   'b0000000-0000-4000-8000-000000000011', 'b0000000-0000-4000-8000-000000000102',
   'Imam House', 'بيت الإمام', 'other', 'Al Rayyan, Qatar', true,
   'MSQ-C-IMAM', 'AWQAF/C/IMAM', 'AWQAF_IMAM_HOUSE'),
  -- Mosque D
  ('b0000000-0000-4000-8000-000000000231', 'b0000000-0000-4000-8000-000000000001',
   'b0000000-0000-4000-8000-000000000011', 'b0000000-0000-4000-8000-000000000103',
   'Men Prayer Hall', 'مصلى الرجال', 'other', 'Al Rayyan, Qatar', true,
   'MSQ-D-MEN', 'AWQAF/D/MEN', 'AWQAF_MEN_PRAYER'),
  ('b0000000-0000-4000-8000-000000000232', 'b0000000-0000-4000-8000-000000000001',
   'b0000000-0000-4000-8000-000000000011', 'b0000000-0000-4000-8000-000000000103',
   'Washrooms & Ablution', 'الحمامات والمواضيء', 'other', 'Al Rayyan, Qatar', true,
   'MSQ-D-WUDU', 'AWQAF/D/WUDU', 'AWQAF_WUDU'),
  ('b0000000-0000-4000-8000-000000000233', 'b0000000-0000-4000-8000-000000000001',
   'b0000000-0000-4000-8000-000000000011', 'b0000000-0000-4000-8000-000000000103',
   'Imam House', 'بيت الإمام', 'other', 'Al Rayyan, Qatar', true,
   'MSQ-D-IMAM', 'AWQAF/D/IMAM', 'AWQAF_IMAM_HOUSE'),
  -- Mosque E
  ('b0000000-0000-4000-8000-000000000241', 'b0000000-0000-4000-8000-000000000001',
   'b0000000-0000-4000-8000-000000000012', 'b0000000-0000-4000-8000-000000000104',
   'Men Prayer Hall', 'مصلى الرجال', 'other', 'Al Wakrah, Qatar', true,
   'MSQ-E-MEN', 'AWQAF/E/MEN', 'AWQAF_MEN_PRAYER'),
  ('b0000000-0000-4000-8000-000000000242', 'b0000000-0000-4000-8000-000000000001',
   'b0000000-0000-4000-8000-000000000012', 'b0000000-0000-4000-8000-000000000104',
   'Washrooms & Ablution', 'الحمامات والمواضيء', 'other', 'Al Wakrah, Qatar', true,
   'MSQ-E-WUDU', 'AWQAF/E/WUDU', 'AWQAF_WUDU'),
  ('b0000000-0000-4000-8000-000000000243', 'b0000000-0000-4000-8000-000000000001',
   'b0000000-0000-4000-8000-000000000012', 'b0000000-0000-4000-8000-000000000104',
   'Imam House', 'بيت الإمام', 'other', 'Al Wakrah, Qatar', true,
   'MSQ-E-IMAM', 'AWQAF/E/IMAM', 'AWQAF_IMAM_HOUSE'),
  -- Mosque F
  ('b0000000-0000-4000-8000-000000000251', 'b0000000-0000-4000-8000-000000000001',
   'b0000000-0000-4000-8000-000000000012', 'b0000000-0000-4000-8000-000000000105',
   'Men Prayer Hall', 'مصلى الرجال', 'other', 'Al Wakrah, Qatar', true,
   'MSQ-F-MEN', 'AWQAF/F/MEN', 'AWQAF_MEN_PRAYER'),
  ('b0000000-0000-4000-8000-000000000252', 'b0000000-0000-4000-8000-000000000001',
   'b0000000-0000-4000-8000-000000000012', 'b0000000-0000-4000-8000-000000000105',
   'Washrooms & Ablution', 'الحمامات والمواضيء', 'other', 'Al Wakrah, Qatar', true,
   'MSQ-F-WUDU', 'AWQAF/F/WUDU', 'AWQAF_WUDU'),
  ('b0000000-0000-4000-8000-000000000253', 'b0000000-0000-4000-8000-000000000001',
   'b0000000-0000-4000-8000-000000000012', 'b0000000-0000-4000-8000-000000000105',
   'Imam House', 'بيت الإمام', 'other', 'Al Wakrah, Qatar', true,
   'MSQ-F-IMAM', 'AWQAF/F/IMAM', 'AWQAF_IMAM_HOUSE')
on conflict (id) do update set
  name_en = excluded.name_en,
  name_ar = excluded.name_ar,
  zone_id = excluded.zone_id,
  parent_site_id = excluded.parent_site_id,
  building_code = excluded.building_code,
  pin = excluded.pin,
  checklist_type = excluded.checklist_type,
  is_active = true,
  updated_at = now();

-- Grant access to platform owner + trial demo on all Awqaf checklist units + campuses
insert into public.user_site_access (user_id, site_id, role, can_read, can_write, can_manage)
select p.id, s.id, 'super_admin', true, true, true
from public.profiles p
cross join public.sites s
where lower(p.email) in ('alikarim4r@gmail.com', 'test@alimind.com')
  and s.organization_id = 'b0000000-0000-4000-8000-000000000001'
on conflict (user_id, site_id) do update set
  role = excluded.role,
  can_read = true,
  can_write = true,
  can_manage = true;
