-- =============================================================================
-- Per-site form/table color themes
-- Migration: 018_form_themes.sql
-- =============================================================================
-- form_theme = 'inherit' → unit uses parent campus theme (client + resolve helper).

alter table public.sites
  add column if not exists form_theme text not null default 'classic_gold',
  add column if not exists form_theme_accent text;

comment on column public.sites.form_theme is
  'Paper form chrome: classic_gold|navy_sand|forest|slate|crimson|teal|custom|inherit';
comment on column public.sites.form_theme_accent is
  'Optional #RRGGBB accent when form_theme = custom';

-- Checklist units default to inherit campus chrome when parent exists.
update public.sites
set form_theme = 'inherit'
where parent_site_id is not null
  and form_theme = 'classic_gold';

alter table public.sites
  drop constraint if exists sites_form_theme_check;

alter table public.sites
  add constraint sites_form_theme_check
  check (
    form_theme in (
      'classic_gold',
      'navy_sand',
      'forest',
      'slate',
      'crimson',
      'teal',
      'custom',
      'inherit'
    )
  );
