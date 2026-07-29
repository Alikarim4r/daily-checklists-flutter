-- =============================================================================
-- Daily Checklists — inspection domain
-- Migration: 003_checklist_domain.sql
-- =============================================================================

create type public.checklist_response as enum ('yes', 'no', 'na');
create type public.checklist_inspection_status as enum ('draft', 'submitted');

create table public.checklist_inspections (
  id uuid primary key default gen_random_uuid(),
  site_id uuid not null references public.sites (id) on delete restrict,
  building_code text not null,
  inspection_date date not null,
  inspection_time text not null default '',
  floor_label text not null default 'ALL',
  location_label text not null default 'MOEHE Permanent Headquarters',
  inspector_name text not null default '',
  inspector_user_id uuid references public.profiles (id) on delete set null,
  signature_path text,
  status public.checklist_inspection_status not null default 'draft',
  submitted_at timestamptz,
  submitted_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint checklist_inspections_unique_site_date unique (site_id, inspection_date)
);

create index checklist_inspections_site_id_idx on public.checklist_inspections (site_id);
create index checklist_inspections_date_idx on public.checklist_inspections (inspection_date desc);

create table public.checklist_inspection_items (
  id uuid primary key default gen_random_uuid(),
  inspection_id uuid not null references public.checklist_inspections (id) on delete cascade,
  item_index int not null,
  description text not null,
  description_ar text,
  response public.checklist_response,
  actions_taken text not null default '',
  image_path text,
  is_custom boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint checklist_inspection_items_unique_index unique (inspection_id, item_index)
);

create table public.checklist_corrections (
  id uuid primary key default gen_random_uuid(),
  inspection_id uuid not null references public.checklist_inspections (id) on delete cascade,
  item_id uuid references public.checklist_inspection_items (id) on delete set null,
  field_name text not null,
  old_value text,
  new_value text,
  reason text not null default '',
  corrected_by uuid not null references public.profiles (id) on delete restrict,
  created_at timestamptz not null default now()
);

create or replace function public.set_checklist_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger checklist_inspections_set_updated_at
  before update on public.checklist_inspections
  for each row execute function public.set_checklist_updated_at();

create trigger checklist_items_set_updated_at
  before update on public.checklist_inspection_items
  for each row execute function public.set_checklist_updated_at();

-- RLS helpers
create or replace function public.can_edit_checklist_inspection(p_inspection_id uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.checklist_inspections i
    where i.id = p_inspection_id
      and (
        public.is_super_admin()
        or (public.can_write_site(i.site_id) and i.status = 'draft')
        or (public.can_manage_site(i.site_id) and i.status = 'draft')
      )
  );
$$;

create or replace function public.can_admin_correct_checklist(p_site_id uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_super_admin() or public.can_manage_site(p_site_id);
$$;

alter table public.checklist_inspections enable row level security;
alter table public.checklist_inspection_items enable row level security;
alter table public.checklist_corrections enable row level security;

create policy checklist_inspections_select on public.checklist_inspections
  for select to authenticated
  using (public.is_super_admin() or public.has_site_access(site_id));

create policy checklist_inspections_insert on public.checklist_inspections
  for insert to authenticated
  with check (
    public.is_approved_active_user()
    and (public.is_super_admin() or public.can_write_site(site_id))
  );

create policy checklist_inspections_update on public.checklist_inspections
  for update to authenticated
  using (
    public.is_super_admin()
    or public.can_admin_correct_checklist(site_id)
    or (public.can_write_site(site_id) and status = 'draft')
  )
  with check (
    public.is_super_admin()
    or public.can_admin_correct_checklist(site_id)
    or public.can_write_site(site_id)
  );

create policy checklist_inspections_delete on public.checklist_inspections
  for delete to authenticated
  using (public.is_super_admin());

create policy checklist_items_select on public.checklist_inspection_items
  for select to authenticated
  using (
    exists (
      select 1 from public.checklist_inspections i
      where i.id = inspection_id
        and (public.is_super_admin() or public.has_site_access(i.site_id))
    )
  );

create policy checklist_items_insert on public.checklist_inspection_items
  for insert to authenticated
  with check (public.can_edit_checklist_inspection(inspection_id));

create policy checklist_items_update on public.checklist_inspection_items
  for update to authenticated
  using (
    public.can_edit_checklist_inspection(inspection_id)
    or exists (
      select 1 from public.checklist_inspections i
      where i.id = inspection_id and public.can_admin_correct_checklist(i.site_id)
    )
  )
  with check (
    public.can_edit_checklist_inspection(inspection_id)
    or exists (
      select 1 from public.checklist_inspections i
      where i.id = inspection_id and public.can_admin_correct_checklist(i.site_id)
    )
  );

create policy checklist_items_delete on public.checklist_inspection_items
  for delete to authenticated
  using (
    public.can_edit_checklist_inspection(inspection_id) or public.is_super_admin()
  );

create policy checklist_corrections_select on public.checklist_corrections
  for select to authenticated
  using (
    exists (
      select 1 from public.checklist_inspections i
      where i.id = inspection_id
        and (public.is_super_admin() or public.can_admin_correct_checklist(i.site_id))
    )
  );

create policy checklist_corrections_insert on public.checklist_corrections
  for insert to authenticated
  with check (
    corrected_by = auth.uid()
    and exists (
      select 1 from public.checklist_inspections i
      where i.id = inspection_id and public.can_admin_correct_checklist(i.site_id)
    )
  );
