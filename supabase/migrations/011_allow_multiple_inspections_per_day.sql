-- Allow multiple checklists per site per calendar day (new list after submit/export).
alter table public.checklist_inspections
  drop constraint if exists checklist_inspections_unique_site_date;

create index if not exists checklist_inspections_site_date_idx
  on public.checklist_inspections (site_id, inspection_date desc);

create index if not exists checklist_inspections_site_date_created_idx
  on public.checklist_inspections (site_id, inspection_date, created_at desc);
