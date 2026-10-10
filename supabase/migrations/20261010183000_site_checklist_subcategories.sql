-- Category subfolders for per-bathroom technical checklists.
-- Hygiene lists are shown directly under Cleaning, without a nested folder.
alter table public.sites
  add column if not exists checklist_subcategory text not null default '';
alter table public.sites
  drop constraint if exists sites_checklist_subcategory_allowed;
alter table public.sites
  add constraint sites_checklist_subcategory_allowed check (
    checklist_subcategory = '' or
    (checklist_category = 'facilities' and checklist_subcategory = 'washrooms')
  );
create index if not exists sites_checklist_subcategory_idx
  on public.sites (checklist_category, checklist_subcategory)
  where checklist_subcategory <> '';
