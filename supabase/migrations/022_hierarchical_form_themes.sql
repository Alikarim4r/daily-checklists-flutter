-- =============================================================================
-- Hierarchical checklist themes
-- Migration: 022_hierarchical_form_themes.sql
-- =============================================================================
-- Resolution precedence:
-- checklist unit/site -> parent campus -> zone -> template/type -> organization
-- -> classic gold default.

alter table public.organizations
  add column if not exists form_theme text not null default 'classic_gold',
  add column if not exists form_theme_accent text;

alter table public.zones
  add column if not exists form_theme text not null default 'inherit',
  add column if not exists form_theme_accent text;

alter table public.checklist_templates
  add column if not exists form_theme text not null default 'inherit',
  add column if not exists form_theme_accent text;

-- New campuses and checklist units inherit unless an administrator chooses an
-- explicit theme. Existing classic-gold rows were the old default, so migrate
-- them to inheritance without changing their current effective appearance.
alter table public.sites alter column form_theme set default 'inherit';
update public.sites
set form_theme = 'inherit', form_theme_accent = null
where form_theme = 'classic_gold';

update public.organizations
set form_theme_accent = null
where form_theme <> 'custom';
update public.zones
set form_theme_accent = null
where form_theme <> 'custom';
update public.sites
set form_theme_accent = null
where form_theme <> 'custom';
update public.checklist_templates
set form_theme_accent = null
where form_theme <> 'custom';

alter table public.organizations
  drop constraint if exists organizations_form_theme_check,
  drop constraint if exists organizations_form_theme_accent_check;
alter table public.organizations
  add constraint organizations_form_theme_check check (
    form_theme in (
      'classic_gold', 'navy_sand', 'forest', 'slate',
      'crimson', 'teal', 'custom', 'inherit'
    )
  ),
  add constraint organizations_form_theme_accent_check check (
    (form_theme = 'custom' and form_theme_accent ~ '^#[0-9A-Fa-f]{6}$')
    or (form_theme <> 'custom' and form_theme_accent is null)
  );

alter table public.zones
  drop constraint if exists zones_form_theme_check,
  drop constraint if exists zones_form_theme_accent_check;
alter table public.zones
  add constraint zones_form_theme_check check (
    form_theme in (
      'classic_gold', 'navy_sand', 'forest', 'slate',
      'crimson', 'teal', 'custom', 'inherit'
    )
  ),
  add constraint zones_form_theme_accent_check check (
    (form_theme = 'custom' and form_theme_accent ~ '^#[0-9A-Fa-f]{6}$')
    or (form_theme <> 'custom' and form_theme_accent is null)
  );

alter table public.sites
  drop constraint if exists sites_form_theme_check,
  drop constraint if exists sites_form_theme_accent_check;
alter table public.sites
  add constraint sites_form_theme_check check (
    form_theme in (
      'classic_gold', 'navy_sand', 'forest', 'slate',
      'crimson', 'teal', 'custom', 'inherit'
    )
  ),
  add constraint sites_form_theme_accent_check check (
    (form_theme = 'custom' and form_theme_accent ~ '^#[0-9A-Fa-f]{6}$')
    or (form_theme <> 'custom' and form_theme_accent is null)
  );

alter table public.checklist_templates
  drop constraint if exists checklist_templates_form_theme_check,
  drop constraint if exists checklist_templates_form_theme_accent_check;
alter table public.checklist_templates
  add constraint checklist_templates_form_theme_check check (
    form_theme in (
      'classic_gold', 'navy_sand', 'forest', 'slate',
      'crimson', 'teal', 'custom', 'inherit'
    )
  ),
  add constraint checklist_templates_form_theme_accent_check check (
    (form_theme = 'custom' and form_theme_accent ~ '^#[0-9A-Fa-f]{6}$')
    or (form_theme <> 'custom' and form_theme_accent is null)
  );

comment on column public.organizations.form_theme is
  'Organization-level checklist theme; root fallback is classic_gold.';
comment on column public.zones.form_theme is
  'Zone checklist theme; inherit resolves from organization.';
comment on column public.checklist_templates.form_theme is
  'Checklist-type theme; inherit resolves to the hierarchy/default.';

create or replace function public.resolve_checklist_form_themes(
  p_site_ids uuid[]
)
returns table (
  site_id uuid,
  theme_key text,
  accent_hex text,
  source_scope text
)
language sql
stable
security definer
set search_path = public
set row_security = off
as $$
  with eligible_sites as materialized (
    select
      site.id,
      site.organization_id,
      coalesce(site.zone_id, parent.zone_id) as effective_zone_id,
      site.parent_site_id,
      site.checklist_type,
      site.form_theme,
      site.form_theme_accent
    from public.sites site
    left join public.sites parent on parent.id = site.parent_site_id
    where site.id = any(coalesce(p_site_ids, array[]::uuid[]))
      and (
        public.is_platform_owner()
        or public.is_org_super_admin(site.organization_id)
        or public.has_site_access(site.id)
      )
  ),
  candidates as (
    select
      site.id as target_site_id,
      site.form_theme as candidate_theme,
      site.form_theme_accent as candidate_accent,
      'site'::text as candidate_scope,
      1 as priority
    from eligible_sites site

    union all

    select
      site.id,
      parent.form_theme,
      parent.form_theme_accent,
      'campus'::text,
      2
    from eligible_sites site
    join public.sites parent on parent.id = site.parent_site_id

    union all

    select
      site.id,
      zone.form_theme,
      zone.form_theme_accent,
      'zone'::text,
      3
    from eligible_sites site
    join public.zones zone on zone.id = site.effective_zone_id

    union all

    select
      site.id,
      template.form_theme,
      template.form_theme_accent,
      'template'::text,
      4
    from eligible_sites site
    join public.checklist_templates template
      on template.code = site.checklist_type

    union all

    select
      site.id,
      organization.form_theme,
      organization.form_theme_accent,
      'organization'::text,
      5
    from eligible_sites site
    join public.organizations organization
      on organization.id = site.organization_id

    union all

    select
      site.id,
      'classic_gold'::text,
      null::text,
      'default'::text,
      6
    from eligible_sites site
  ),
  resolved as (
    select distinct on (candidate.target_site_id)
      candidate.target_site_id,
      candidate.candidate_theme,
      candidate.candidate_accent,
      candidate.candidate_scope
    from candidates candidate
    where candidate.candidate_theme <> 'inherit'
    order by candidate.target_site_id, candidate.priority
  )
  select
    resolved.target_site_id,
    resolved.candidate_theme,
    case
      when resolved.candidate_theme = 'custom'
        then resolved.candidate_accent
      else null
    end,
    resolved.candidate_scope
  from resolved;
$$;

revoke all on function public.resolve_checklist_form_themes(uuid[])
  from public;
grant execute on function public.resolve_checklist_form_themes(uuid[])
  to authenticated;
