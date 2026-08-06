-- =============================================================================
-- Hierarchy: campus site (موقع) → building checklists (قوائم فحص داخل الموقع)
-- Migration: 010_parent_site_hierarchy.sql
-- =============================================================================

alter table public.sites
  add column if not exists parent_site_id uuid
    references public.sites (id) on delete set null;

create index if not exists sites_parent_site_id_idx
  on public.sites (parent_site_id)
  where parent_site_id is not null;

-- Prevent cycles at insert/update (one level: child may not be its own ancestor)
create or replace function public.sites_prevent_parent_cycle()
returns trigger
language plpgsql
as $$
begin
  if new.parent_site_id is null then
    return new;
  end if;
  if new.parent_site_id = new.id then
    raise exception 'site cannot be its own parent';
  end if;
  if exists (
    select 1 from public.sites p
    where p.id = new.parent_site_id
      and p.parent_site_id is not null
  ) then
    raise exception 'only one nesting level is allowed (site → checklist)';
  end if;
  return new;
end;
$$;

drop trigger if exists sites_prevent_parent_cycle_trg on public.sites;
create trigger sites_prevent_parent_cycle_trg
  before insert or update of parent_site_id on public.sites
  for each row execute function public.sites_prevent_parent_cycle();

-- Campus / parent site: المقر الدائم (no building_code → not a daily checklist unit)
insert into public.sites (
  id, organization_id, zone_id, name_en, name_ar, site_type, location,
  is_active, building_code, pin, checklist_type, parent_site_id
) values (
  'a0000000-0000-4000-8000-000000000100',
  'a0000000-0000-4000-8000-000000000001',
  'a0000000-0000-4000-8000-000000000010',
  'MOEHE Permanent Headquarters',
  'المقر الدائم لوزارة التربية والتعليم والتعليم العالي',
  'headquarters',
  'MOEHE Permanent Headquarters',
  true,
  null,
  null,
  'DEFAULT',
  null
)
on conflict (id) do update set
  name_en = excluded.name_en,
  name_ar = excluded.name_ar,
  location = excluded.location,
  building_code = null,
  parent_site_id = null,
  is_active = true,
  updated_at = now();

-- Nest existing HQ buildings under the campus site
update public.sites
set parent_site_id = 'a0000000-0000-4000-8000-000000000100',
    updated_at = now()
where id in (
  'a0000000-0000-4000-8000-000000000101',
  'a0000000-0000-4000-8000-000000000102',
  'a0000000-0000-4000-8000-000000000103',
  'a0000000-0000-4000-8000-000000000104',
  'a0000000-0000-4000-8000-000000000105',
  'a0000000-0000-4000-8000-000000000106',
  'a0000000-0000-4000-8000-000000000107',
  'a0000000-0000-4000-8000-000000000108',
  'a0000000-0000-4000-8000-000000000109',
  'a0000000-0000-4000-8000-000000000110'
);

-- Anyone with access to a child checklist also gets read on campus (for UI grouping)
insert into public.user_site_access (user_id, site_id, role, can_read, can_write, can_manage)
select distinct a.user_id,
       'a0000000-0000-4000-8000-000000000100'::uuid,
       a.role,
       true,
       false,
       false
from public.user_site_access a
where a.site_id in (
  'a0000000-0000-4000-8000-000000000101',
  'a0000000-0000-4000-8000-000000000102',
  'a0000000-0000-4000-8000-000000000103',
  'a0000000-0000-4000-8000-000000000104',
  'a0000000-0000-4000-8000-000000000105',
  'a0000000-0000-4000-8000-000000000106',
  'a0000000-0000-4000-8000-000000000107',
  'a0000000-0000-4000-8000-000000000108',
  'a0000000-0000-4000-8000-000000000109',
  'a0000000-0000-4000-8000-000000000110'
)
on conflict (user_id, site_id) do nothing;
