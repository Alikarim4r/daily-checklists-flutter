-- Fixtures inserted after 024 and before 025.
-- The untouched 19-item draft must refresh; the answered draft must remain.

insert into public.checklist_inspections (
  id, site_id, building_code, inspection_date, inspection_time, floor_label,
  location_label, inspector_name, status, review_status
)
select
  fixture.id,
  site.id,
  site.building_code,
  date '2026-01-03',
  '08:00',
  'ALL',
  site.location,
  fixture.inspector_name,
  'draft',
  'draft'
from (
  select id, building_code, location
  from public.sites
  where checklist_type = 'B7_MECH'
    and is_active = true
  order by id
  limit 1
) site
cross join (values
  ('25000000-0000-4000-8000-000000000001'::uuid, 'Untouched B7-M draft'),
  ('25000000-0000-4000-8000-000000000002'::uuid, 'Answered B7-M draft')
) fixture(id, inspector_name);

insert into public.checklist_inspection_items (
  inspection_id, item_index, description, description_ar,
  response, default_answer, is_custom
)
select
  '25000000-0000-4000-8000-000000000001'::uuid,
  index,
  'Legacy B7-M item ' || index,
  'بند قديم ' || index,
  null,
  'Y',
  false
from generate_series(1, 19) index;

insert into public.checklist_inspection_items (
  inspection_id, item_index, description, description_ar,
  response, default_answer, is_custom
)
values (
  '25000000-0000-4000-8000-000000000002',
  1,
  'Legacy answered B7-M item',
  'بند قديم مجاب عنه',
  'yes',
  'Y',
  false
);
