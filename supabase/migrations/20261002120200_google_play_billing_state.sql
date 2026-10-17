-- Google Play billing state. Purchase tokens are server-only and never exposed through the Data API.

create table public.google_play_subscription_purchases (
  purchase_token_hash text primary key,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  purchased_by uuid references auth.users(id) on delete set null,
  package_name text not null,
  product_id text not null,
  base_plan_id text,
  offer_id text,
  order_id text,
  linked_purchase_token_hash text,
  subscription_state text not null,
  acknowledgement_state text,
  region_code text,
  is_test_purchase boolean not null default false,
  start_time timestamptz,
  expiry_time timestamptz,
  auto_renewing boolean,
  cancel_at_period_end boolean not null default false,
  raw_response jsonb not null default '{}'::jsonb,
  last_verified_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index google_play_subscription_purchases_org_idx
  on public.google_play_subscription_purchases(organization_id, last_verified_at desc);
create index google_play_subscription_purchases_product_idx
  on public.google_play_subscription_purchases(product_id, subscription_state);

create trigger google_play_subscription_purchases_set_updated_at
  before update on public.google_play_subscription_purchases
  for each row execute function public.set_updated_at();

alter table public.google_play_subscription_purchases enable row level security;
revoke all on table public.google_play_subscription_purchases from anon, authenticated;

-- Public catalog metadata used to map verified Google Play products to SaaS entitlements.
alter table public.subscription_plan_catalog
  add column if not exists google_play_product_id text,
  add column if not exists google_play_monthly_base_plan_id text,
  add column if not exists google_play_annual_base_plan_id text,
  add column if not exists google_play_trial_offer_id text;

update public.subscription_plan_catalog set
  google_play_product_id = case plan
    when 'starter' then 'daily_checklists_starter'
    when 'professional' then 'daily_checklists_professional'
    when 'business' then 'daily_checklists_business'
    else null end,
  google_play_monthly_base_plan_id = case when plan in ('starter','professional','business') then 'monthly' else null end,
  google_play_annual_base_plan_id = case when plan in ('starter','professional','business') then 'annual' else null end,
  google_play_trial_offer_id = case when plan in ('starter','professional','business') then 'trial-30d' else null end;

create unique index subscription_plan_catalog_google_product_uidx
  on public.subscription_plan_catalog(google_play_product_id)
  where google_play_product_id is not null;

-- Re-publish catalog metadata after adding the billing columns so it is reachable
-- even when Supabase automatic Data API exposure is disabled.
grant select on table public.subscription_plan_catalog to authenticated;

-- RTDN deduplication/audit. No client access.
create table public.google_play_rtdn_events (
  message_id text primary key,
  publish_time timestamptz,
  package_name text,
  notification_type integer,
  purchase_token_hash text,
  event_time_millis bigint,
  status text not null default 'received' check (status in ('received','processed','ignored','failed')),
  error_code text,
  created_at timestamptz not null default now(),
  processed_at timestamptz
);
alter table public.google_play_rtdn_events enable row level security;
revoke all on table public.google_play_rtdn_events from anon, authenticated;
