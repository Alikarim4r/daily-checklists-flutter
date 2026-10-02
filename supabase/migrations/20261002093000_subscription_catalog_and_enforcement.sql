-- Commercial catalog + server-side quota enforcement for Daily Checklists.
-- Approved pricing: QAR 199 / 499 / 999 monthly, with two months free annually.

create table public.subscription_plan_catalog (
  plan public.subscription_plan primary key,
  display_order integer not null,
  monthly_price_qar integer,
  annual_price_qar integer,
  trial_days integer not null default 0 check (trial_days >= 0),
  max_users integer not null check (max_users > 0),
  max_sites integer not null check (max_sites > 0),
  storage_gb integer not null check (storage_gb > 0),
  is_public boolean not null default true,
  is_recommended boolean not null default false,
  features jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

insert into public.subscription_plan_catalog
(plan, display_order, monthly_price_qar, annual_price_qar, trial_days, max_users, max_sites, storage_gb, is_public, is_recommended, features)
values
('trial', 0, 0, 0, 30, 10, 1, 5, false, false, '{"offline_sync":true,"reports":true,"corrective_actions":true}'),
('starter', 1, 199, 1990, 0, 10, 1, 5, true, false, '{"offline_sync":true,"reports":true,"corrective_actions":true}'),
('professional', 2, 499, 4990, 0, 50, 5, 25, true, true, '{"offline_sync":true,"reports":true,"corrective_actions":true,"audit_log":true,"custom_branding":true}'),
('business', 3, 999, 9990, 0, 200, 20, 100, true, false, '{"offline_sync":true,"reports":true,"corrective_actions":true,"audit_log":true,"custom_branding":true,"multi_site_management":true,"priority_support":true}'),
('enterprise', 4, null, 20000, 0, 1000000, 1000000, 1000, true, false, '{"offline_sync":true,"reports":true,"corrective_actions":true,"audit_log":true,"custom_branding":true,"multi_site_management":true,"priority_support":true,"custom_limits":true,"sla":true,"onboarding":true}')
on conflict (plan) do update set
  display_order=excluded.display_order, monthly_price_qar=excluded.monthly_price_qar,
  annual_price_qar=excluded.annual_price_qar, trial_days=excluded.trial_days,
  max_users=excluded.max_users, max_sites=excluded.max_sites, storage_gb=excluded.storage_gb,
  is_public=excluded.is_public, is_recommended=excluded.is_recommended,
  features=excluded.features, updated_at=now();

alter table public.subscription_plan_catalog enable row level security;
create policy subscription_plan_catalog_read on public.subscription_plan_catalog for select to authenticated using (true);
revoke all on table public.subscription_plan_catalog from anon;
revoke insert, update, delete on table public.subscription_plan_catalog from authenticated;
grant select on table public.subscription_plan_catalog to authenticated;

alter table public.organization_subscriptions add column if not exists storage_gb integer not null default 5 check (storage_gb > 0);

-- Keep the initial Professional entitlement aligned with the approved commercial tier.
update public.organization_subscriptions
set max_sites = 5, storage_gb = 25,
    features = features || '{"audit_log":true,"custom_branding":true}'::jsonb
where plan = 'professional' and provider = 'manual';

create or replace function public.subscription_usage(p_organization_id uuid)
returns table (active_users bigint, active_sites bigint, max_users integer, max_sites integer, storage_gb integer)
language sql stable security invoker set search_path = '' as $$
  select
    (select count(*) from public.profiles p where p.home_organization_id=p_organization_id and p.is_active=true),
    (select count(*) from public.sites si where si.organization_id=p_organization_id and si.is_active=true),
    s.max_users, s.max_sites, s.storage_gb
  from public.organization_subscriptions s
  where s.organization_id=p_organization_id and public.can_access_organization(p_organization_id)
  limit 1;
$$;
revoke execute on function public.subscription_usage(uuid) from public, anon;
grant execute on function public.subscription_usage(uuid) to authenticated;

create or replace function public.enforce_subscription_site_limit()
returns trigger language plpgsql security definer set search_path = public as $$
declare s public.organization_subscriptions%rowtype; n bigint;
begin
  if new.is_active is not true then return new; end if;
  select * into s from public.organization_subscriptions where organization_id=new.organization_id;
  if not found then raise exception 'SUBSCRIPTION_REQUIRED'; end if;
  if s.status not in ('trialing','active','grace_period') then raise exception 'SUBSCRIPTION_INACTIVE'; end if;
  if s.status='grace_period' and s.grace_period_end is not null and s.grace_period_end <= now() then raise exception 'SUBSCRIPTION_EXPIRED'; end if;
  select count(*) into n from public.sites where organization_id=new.organization_id and is_active=true and id<>new.id;
  if n >= s.max_sites then raise exception 'SUBSCRIPTION_SITE_LIMIT_REACHED:%', s.max_sites; end if;
  return new;
end; $$;

drop trigger if exists enforce_subscription_site_limit on public.sites;
create trigger enforce_subscription_site_limit before insert or update of is_active, organization_id on public.sites
for each row execute function public.enforce_subscription_site_limit();

create or replace function public.enforce_subscription_user_limit()
returns trigger language plpgsql security definer set search_path = public as $$
declare s public.organization_subscriptions%rowtype; n bigint;
begin
  if new.home_organization_id is null or new.is_active is not true then return new; end if;
  select * into s from public.organization_subscriptions where organization_id=new.home_organization_id;
  if not found then raise exception 'SUBSCRIPTION_REQUIRED'; end if;
  if s.status not in ('trialing','active','grace_period') then raise exception 'SUBSCRIPTION_INACTIVE'; end if;
  if s.status='grace_period' and s.grace_period_end is not null and s.grace_period_end <= now() then raise exception 'SUBSCRIPTION_EXPIRED'; end if;
  select count(*) into n from public.profiles where home_organization_id=new.home_organization_id and is_active=true and id<>new.id;
  if n >= s.max_users then raise exception 'SUBSCRIPTION_USER_LIMIT_REACHED:%', s.max_users; end if;
  return new;
end; $$;

drop trigger if exists enforce_subscription_user_limit on public.profiles;
create trigger enforce_subscription_user_limit before insert or update of is_active, home_organization_id on public.profiles
for each row execute function public.enforce_subscription_user_limit();
