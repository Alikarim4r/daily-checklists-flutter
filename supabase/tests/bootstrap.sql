-- Minimal Supabase-owned schemas required to execute the application
-- migrations against a temporary stock PostgreSQL instance.
create schema auth;
create schema storage;
create schema extensions;

create role anon nologin;
create role authenticated nologin;
create role service_role nologin;

-- Match the hardened Data API behavior used by new Supabase projects: tables
-- and sequences created by migrations are inaccessible until explicitly
-- granted. The public schema itself remains discoverable by PostgREST.
grant usage on schema public to anon, authenticated, service_role;
alter default privileges in schema public
  revoke all privileges on tables from public, anon, authenticated;
alter default privileges in schema public
  revoke all privileges on sequences from public, anon, authenticated;

create extension pgcrypto with schema extensions;

create function auth.uid()
returns uuid
language sql
stable
as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;

grant usage on schema auth to anon, authenticated, service_role;
grant execute on function auth.uid() to anon, authenticated, service_role;

create table auth.users (
  id uuid primary key,
  instance_id uuid,
  aud text,
  role text,
  email text unique,
  encrypted_password text,
  email_confirmed_at timestamptz,
  raw_app_meta_data jsonb not null default '{}'::jsonb,
  raw_user_meta_data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  confirmation_token text,
  recovery_token text,
  email_change_token_new text,
  email_change text
);

create table auth.identities (
  id uuid primary key,
  user_id uuid references auth.users (id) on delete cascade,
  provider_id text,
  identity_data jsonb,
  provider text,
  last_sign_in_at timestamptz,
  created_at timestamptz,
  updated_at timestamptz
);

create table storage.buckets (
  id text primary key,
  name text not null,
  public boolean not null default false,
  file_size_limit bigint,
  allowed_mime_types text[]
);

create table storage.objects (
  id uuid primary key default extensions.gen_random_uuid(),
  bucket_id text references storage.buckets (id),
  name text not null,
  created_at timestamptz not null default now()
);

alter table storage.objects enable row level security;
