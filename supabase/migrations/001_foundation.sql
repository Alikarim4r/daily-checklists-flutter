-- =============================================================================
-- Daily Checklists — independent foundation schema
-- Project: daily-checklists-flutter (NOT smart-meters)
-- Migration: 001_foundation.sql
-- =============================================================================

create extension if not exists "pgcrypto";

create type public.user_role as enum (
  'super_admin',
  'site_admin',
  'technician',
  'technician_request',
  'viewer'
);

create type public.approval_status as enum (
  'pending',
  'approved',
  'rejected',
  'suspended'
);

create type public.site_type as enum (
  'headquarters',
  'school',
  'kindergarten',
  'office',
  'warehouse',
  'training_center',
  'other'
);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create or replace function public.current_business_date()
returns date
language sql
stable
as $$
  select (timezone('Asia/Qatar', now()))::date;
$$;

-- Organizations
create table public.organizations (
  id uuid primary key default gen_random_uuid(),
  name_en text not null,
  name_ar text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint organizations_name_en_not_empty check (char_length(trim(name_en)) > 0),
  constraint organizations_name_ar_not_empty check (char_length(trim(name_ar)) > 0)
);

create trigger organizations_set_updated_at
  before update on public.organizations
  for each row execute function public.set_updated_at();

-- Zones
create table public.zones (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  code text not null,
  name_en text not null,
  name_ar text,
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint zones_organization_code_unique unique (organization_id, code),
  constraint zones_code_format check (code ~ '^[a-z][a-z0-9_]*$')
);

create trigger zones_set_updated_at
  before update on public.zones
  for each row execute function public.set_updated_at();

-- Sites
create table public.sites (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete restrict,
  zone_id uuid references public.zones (id) on delete set null,
  name_en text not null,
  name_ar text not null,
  site_type public.site_type not null default 'other',
  location text,
  building_code text,
  pin text,
  checklist_type text not null default 'DEFAULT',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint sites_name_en_not_empty check (char_length(trim(name_en)) > 0),
  constraint sites_name_ar_not_empty check (char_length(trim(name_ar)) > 0)
);

create unique index sites_building_code_uidx
  on public.sites (building_code)
  where building_code is not null;

create trigger sites_set_updated_at
  before update on public.sites
  for each row execute function public.set_updated_at();

-- Profiles
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name text not null default '',
  email text not null,
  role public.user_role not null default 'viewer',
  is_active boolean not null default false,
  approval_status public.approval_status not null default 'pending',
  approval_note text,
  approved_at timestamptz,
  approved_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, email, role, is_active, approval_status)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', split_part(new.email, '@', 1)),
    new.email,
    'viewer',
    false,
    'pending'
  );
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Site access
create table public.user_site_access (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  site_id uuid not null references public.sites (id) on delete cascade,
  role public.user_role not null,
  can_read boolean not null default true,
  can_write boolean not null default false,
  can_manage boolean not null default false,
  created_at timestamptz not null default now(),
  constraint user_site_access_unique_user_site unique (user_id, site_id)
);
