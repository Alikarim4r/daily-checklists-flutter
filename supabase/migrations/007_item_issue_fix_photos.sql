-- =============================================================================
-- Daily Checklists — issue/fix photo paths on inspection items
-- Migration: 007_item_issue_fix_photos.sql
-- =============================================================================

alter table public.checklist_inspection_items
  add column if not exists issue_image_path text,
  add column if not exists fix_image_path text,
  add column if not exists default_answer text not null default 'Y';

comment on column public.checklist_inspection_items.issue_image_path is
  'Problem evidence photo (HTML: issue)';
comment on column public.checklist_inspection_items.fix_image_path is
  'Repair evidence photo (HTML: fix)';
comment on column public.checklist_inspection_items.default_answer is
  'Expected answer Y/N from checklist catalog (problem = opposite)';
