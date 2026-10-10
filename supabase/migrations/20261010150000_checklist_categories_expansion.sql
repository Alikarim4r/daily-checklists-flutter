-- Expand classification choices without reassigning existing checklists.
-- Empty categories are hidden by applications; no seed/placeholder sites added.
alter table public.sites
  drop constraint if exists sites_checklist_category_allowed;
alter table public.sites
  add constraint sites_checklist_category_allowed
  check (checklist_category in (
    'general', 'facilities', 'hygiene', 'irrigation', 'pantry',
    'maintenance', 'safety', 'food', 'stores'
  ));

comment on column public.sites.checklist_category is
  'Site checklist grouping (facilities, hygiene, irrigation, pantry etc); nonempty categories appear in View, Entry, and Admin.';
