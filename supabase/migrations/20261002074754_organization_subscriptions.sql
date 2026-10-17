-- Organization-level SaaS entitlements for Daily Checklists.
-- Billing provider events must be verified server-side before updating these rows.

create type public.subscription_plan as enum ('trial', 'starter', 'professional', 'enterprise');
create type public.subscription_status as enum ('trialing', 'active', 'past_due', 'grace_period', 'canceled', 'expired');
create type public.billing_provider as enum ('manual', 'google_play', 'external_contract');

create table public.organization_subscriptions (
  organization_id uuid primary key references public.organizations(id) on delete cascade,
  plan public.subscription_plan not null default 'trial',
  status public.subscription_status not null default 'trialing',
  provider public.billing_provider not null default 'manual',
  provider_customer_ref text,
  provider_subscription_ref text,
  current_period_start timestamptz,
  current_period_end timestamptz,
  grace_period_end timestamptz,
  cancel_at_period_end boolean not null default false,
  max_users integer not null default 10 check (max_users > 0),
  max_sites integer not null default 1 check (max_sites > 0),
  features jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index organization_subscriptions_provider_ref_uidx
  on public.organization_subscriptions(provider, provider_subscription_ref)
  where provider_subscription_ref is not null;

create trigger organization_subscriptions_set_updated_at
  before update on public.organization_subscriptions
  for each row execute function public.set_updated_at();

alter table public.organization_subscriptions enable row level security;

create policy organization_subscriptions_select on public.organization_subscriptions
  for select to authenticated
  using (public.can_access_organization(organization_id));

-- Clients can never create/change billing state directly.
revoke all on table public.organization_subscriptions from anon;
revoke insert, update, delete on table public.organization_subscriptions from authenticated;
grant select on table public.organization_subscriptions to authenticated;

create or replace function public.subscription_access_state(p_organization_id uuid)
returns table (
  plan public.subscription_plan,
  status public.subscription_status,
  has_access boolean,
  max_users integer,
  max_sites integer,
  current_period_end timestamptz,
  grace_period_end timestamptz,
  features jsonb
)
language sql
stable
security invoker
set search_path = ''
as $$
  select s.plan, s.status,
    (s.status in ('trialing','active','grace_period') and
      (s.status <> 'grace_period' or s.grace_period_end is null or s.grace_period_end > now())) as has_access,
    s.max_users, s.max_sites, s.current_period_end, s.grace_period_end, s.features
  from public.organization_subscriptions s
  where s.organization_id = p_organization_id
    and public.can_access_organization(s.organization_id)
  limit 1;
$$;

revoke execute on function public.subscription_access_state(uuid) from public, anon;
grant execute on function public.subscription_access_state(uuid) to authenticated;

-- Existing organizations receive a launch-period Professional entitlement so this
-- migration never locks out the current production tenant.
insert into public.organization_subscriptions (
  organization_id, plan, status, provider, current_period_start, current_period_end,
  max_users, max_sites, features
)
select id, 'professional', 'active', 'manual', now(), now() + interval '365 days',
  50, 25,
  '{"offline_sync":true,"reports":true,"corrective_actions":true,"audit_log":true,"custom_branding":true}'::jsonb
from public.organizations
on conflict (organization_id) do nothing;
