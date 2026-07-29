-- =============================================================================
-- Daily Checklists — seed MOEHE HQ buildings
-- Migration: 005_seed_moehe.sql
-- =============================================================================

insert into public.organizations (id, name_en, name_ar, is_active)
values (
  'a0000000-0000-4000-8000-000000000001',
  'MOEHE Headquarters',
  'وزارة التربية والتعليم والتعليم العالي - المقر',
  true
)
on conflict (id) do update set
  name_en = excluded.name_en,
  name_ar = excluded.name_ar,
  is_active = true,
  updated_at = now();

insert into public.zones (id, organization_id, code, name_en, name_ar, is_active)
values (
  'a0000000-0000-4000-8000-000000000010',
  'a0000000-0000-4000-8000-000000000001',
  'headquarters',
  'Headquarters',
  'المقر الرئيسي',
  true
)
on conflict (id) do update set
  code = excluded.code,
  name_en = excluded.name_en,
  name_ar = excluded.name_ar,
  is_active = true,
  updated_at = now();

insert into public.sites (
  id, organization_id, zone_id, name_en, name_ar, site_type, location,
  is_active, building_code, pin, checklist_type
) values
  ('a0000000-0000-4000-8000-000000000101', 'a0000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000010',
   'Building 1 - Evaluation Institute', 'مبنى 1 - معهد التقييم', 'headquarters', 'MOEHE Permanent Headquarters',
   true, 'B1', '66170852/A', 'DEFAULT'),
  ('a0000000-0000-4000-8000-000000000102', 'a0000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000010',
   'Building 2 - Shared Services Division', 'مبنى 2 - قطاع الخدمات المشتركة', 'headquarters', 'MOEHE Permanent Headquarters',
   true, 'B2', '66170852/B', 'DEFAULT'),
  ('a0000000-0000-4000-8000-000000000103', 'a0000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000010',
   'Building 2 GF - Data Center Room', 'مبنى 2 - غرفة مركز البيانات', 'headquarters', 'MOEHE Permanent Headquarters',
   true, 'B2-DC', '66170852/B-DC', 'B2_DC'),
  ('a0000000-0000-4000-8000-000000000104', 'a0000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000010',
   'Building 3 - Higher Education Institute', 'مبنى 3 - معهد التعليم العالي', 'headquarters', 'MOEHE Permanent Headquarters',
   true, 'B3', '66170852/C', 'DEFAULT'),
  ('a0000000-0000-4000-8000-000000000105', 'a0000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000010',
   'Building 4 - Secretary General''s Office', 'مبنى 4 - مكتب الأمين العام', 'headquarters', 'MOEHE Permanent Headquarters',
   true, 'B4', '66170852/D', 'B4'),
  ('a0000000-0000-4000-8000-000000000106', 'a0000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000010',
   'Building 5 - Education Institute', 'مبنى 5 - معهد التعليم', 'headquarters', 'MOEHE Permanent Headquarters',
   true, 'B5', '66170852/E', 'DEFAULT'),
  ('a0000000-0000-4000-8000-000000000107', 'a0000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000010',
   'Building 6 - Wall Of Knowledge', 'مبنى 6 - جدار المعرفة', 'headquarters', 'MOEHE Permanent Headquarters',
   true, 'B6', '66170852/F', 'KNOWLEDGE_WALL'),
  ('a0000000-0000-4000-8000-000000000108', 'a0000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000010',
   'Building 7 - Car Parking', 'مبنى 7 - مواقف السيارات', 'headquarters', 'MOEHE Permanent Headquarters',
   true, 'B7', '66170852/G', 'B7_PARKING'),
  ('a0000000-0000-4000-8000-000000000109', 'a0000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000010',
   'Building 7 - Mechanical Plants', 'مبنى 7 - المحطات الميكانيكية', 'headquarters', 'MOEHE Permanent Headquarters',
   true, 'B7-M', '66170852/G-M', 'B7_MECH'),
  ('a0000000-0000-4000-8000-000000000110', 'a0000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000010',
   'Building 7 - BMS', 'مبنى 7 - نظام إدارة المباني', 'headquarters', 'MOEHE Permanent Headquarters',
   true, 'B7-BMS', '66170852/G-BMS', 'B7_BMS')
on conflict (id) do update set
  name_en = excluded.name_en,
  name_ar = excluded.name_ar,
  building_code = excluded.building_code,
  pin = excluded.pin,
  checklist_type = excluded.checklist_type,
  is_active = true,
  updated_at = now();
