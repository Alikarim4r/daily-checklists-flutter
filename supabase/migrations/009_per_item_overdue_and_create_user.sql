-- =============================================================================
-- Daily Checklists — per-item overdue + admin create user
-- Migration: 009_per_item_overdue_and_create_user.sql
-- =============================================================================

-- Per-item overdue (days of consecutive problem before Overdue badge)
alter table public.checklist_template_items
  add column if not exists overdue_after_days int not null default 3
  constraint checklist_template_items_overdue_nonneg check (overdue_after_days >= 0);

alter table public.site_checklist_items
  add column if not exists overdue_after_days int not null default 3
  constraint site_checklist_items_overdue_nonneg check (overdue_after_days >= 0);

alter table public.checklist_inspection_items
  add column if not exists overdue_after_days int not null default 3
  constraint checklist_inspection_items_overdue_nonneg check (overdue_after_days >= 0);

-- Super admin / platform owner can create ready-to-login users (pending until approve).
create or replace function public.admin_create_user(
  p_email text,
  p_password text,
  p_full_name text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_user_id uuid := gen_random_uuid();
  v_email text := lower(trim(p_email));
begin
  if not (public.is_platform_owner() or public.is_super_admin()) then
    raise exception 'Only platform owner / super_admin can create users';
  end if;

  if v_email is null or position('@' in v_email) < 2 then
    raise exception 'Invalid email address';
  end if;

  if coalesce(length(p_password), 0) < 8 then
    raise exception 'Password must be at least 8 characters';
  end if;

  if exists (select 1 from auth.users where lower(email) = v_email) then
    raise exception 'A user with this email already exists';
  end if;

  insert into auth.users (
    id,
    instance_id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at,
    confirmation_token,
    recovery_token,
    email_change_token_new,
    email_change
  )
  values (
    v_user_id,
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    v_email,
    extensions.crypt(p_password, extensions.gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object('full_name', coalesce(p_full_name, '')),
    now(),
    now(),
    '',
    '',
    '',
    ''
  );

  insert into auth.identities (
    id,
    user_id,
    provider_id,
    identity_data,
    provider,
    last_sign_in_at,
    created_at,
    updated_at
  )
  values (
    gen_random_uuid(),
    v_user_id,
    v_user_id::text,
    jsonb_build_object(
      'sub', v_user_id::text,
      'email', v_email,
      'email_verified', true
    ),
    'email',
    now(),
    now(),
    now()
  );

  -- Trigger may have inserted profile; upsert to pending viewer.
  insert into public.profiles (
    id,
    full_name,
    email,
    role,
    is_active,
    approval_status
  )
  values (
    v_user_id,
    coalesce(nullif(trim(p_full_name), ''), split_part(v_email, '@', 1)),
    v_email,
    'viewer',
    false,
    'pending'
  )
  on conflict (id) do update set
    full_name = excluded.full_name,
    email = excluded.email,
    role = 'viewer',
    is_active = false,
    approval_status = 'pending',
    updated_at = now();

  return v_user_id;
end;
$$;

revoke all on function public.admin_create_user(text, text, text) from public;
grant execute on function public.admin_create_user(text, text, text) to authenticated;
