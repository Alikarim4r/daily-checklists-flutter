-- Fixtures inserted after 025 and before 026.
-- Reproduce the production defect: B7-M was assigned the 19-item B4 template.
-- The untouched draft must be repaired; the answered draft must remain immutable.

update public.sites site
set checklist_type = 'B4'
where site.id = (
  select candidate.id
  from public.sites candidate
  where upper(trim(candidate.building_code)) = 'B7-M'
    and candidate.is_active = true
  order by candidate.id
  limit 1
);

insert into public.checklist_inspections (
  id, site_id, building_code, inspection_date, inspection_time, floor_label,
  location_label, inspector_name, status, review_status
)
select
  fixture.id,
  site.id,
  site.building_code,
  date '2026-01-04',
  '08:00',
  'ALL',
  site.location,
  fixture.inspector_name,
  'draft',
  'draft'
from (
  select id, building_code, location
  from public.sites
  where upper(trim(building_code)) = 'B7-M'
    and is_active = true
  order by id
  limit 1
) site
cross join (values
  ('26000000-0000-4000-8000-000000000001'::uuid, 'Wrong-bound untouched B7-M draft'),
  ('26000000-0000-4000-8000-000000000002'::uuid, 'Wrong-bound answered B7-M draft')
) fixture(id, inspector_name);

insert into public.checklist_inspection_items (
  inspection_id, item_index, description, description_ar,
  response, default_answer, is_custom
)
select
  fixture.inspection_id,
  item.item_index,
  item.description_en,
  item.description_ar,
  case
    when fixture.answered and item.item_index = 1
      then 'yes'::public.checklist_response
    else null
  end,
  item.default_answer,
  false
from public.checklist_templates template
join public.checklist_template_items item
  on item.template_id = template.id
cross join (values
  ('26000000-0000-4000-8000-000000000001'::uuid, false),
  ('26000000-0000-4000-8000-000000000002'::uuid, true)
) fixture(inspection_id, answered)
where template.code = 'B4'
  and item.is_active = true;
