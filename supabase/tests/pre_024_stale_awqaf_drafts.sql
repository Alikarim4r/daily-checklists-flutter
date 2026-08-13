-- Fixtures inserted after 023 and before 024 by test_migrations_postgres.sh.
-- One draft is untouched and must refresh; one is answered and must remain.

insert into public.checklist_inspections (
  id,
  site_id,
  building_code,
  inspection_date,
  inspection_time,
  floor_label,
  location_label,
  inspector_name,
  status,
  review_status
)
select
  fixture.id,
  site.id,
  site.building_code,
  date '2026-01-02',
  '08:00',
  'ALL',
  site.location,
  fixture.inspector_name,
  'draft',
  'draft'
from (
  select id, building_code, location
  from public.sites
  where checklist_type = 'AWQAF_MEN_PRAYER'
    and is_active = true
  order by id
  limit 1
) site
cross join (values
  ('24000000-0000-4000-8000-000000000001'::uuid, 'Untouched stale draft'),
  ('24000000-0000-4000-8000-000000000002'::uuid, 'Answered stale draft')
) fixture(id, inspector_name);

insert into public.checklist_inspection_items (
  inspection_id,
  item_index,
  description,
  description_ar,
  response,
  default_answer,
  is_custom
)
values
  (
    '24000000-0000-4000-8000-000000000001',
    1,
    'Legacy untouched item',
    'بند قديم غير مستخدم',
    null,
    'Y',
    false
  ),
  (
    '24000000-0000-4000-8000-000000000002',
    1,
    'Legacy answered item',
    'بند قديم مجاب عنه',
    'yes',
    'Y',
    false
  );

