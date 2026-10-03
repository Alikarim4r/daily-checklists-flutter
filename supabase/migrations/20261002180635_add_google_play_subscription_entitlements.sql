create table if not exists public.organization_subscriptions (
  organization_id uuid primary key references public.organizations(id) on delete cascade,
  provider text not null default 'google_play' check (provider = 'google_play'),
  product_id text check (product_id in ('daily_checklists_starter','daily_checklists_professional','daily_checklists_business')),
  plan_tier text not null default 'starter' check (plan_tier in ('starter','professional','business')),
  purchase_token_hash text unique,
  subscription_state text not null default 'inactive',
  expires_at timestamptz,
  auto_renewing boolean not null default false,
  verified_at timestamptz,
  updated_at timestamptz not null default now()
);

alter table public.organization_subscriptions enable row level security;

revoke all on public.organization_subscriptions from anon;
grant select on public.organization_subscriptions to authenticated;

create policy "organization members can read subscription"
on public.organization_subscriptions
for select
to authenticated
using (
  exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid())
      and p.home_organization_id = organization_subscriptions.organization_id
      and p.is_active = true
  )
);

create or replace function public.current_subscription_entitlement()
returns table (
  organization_id uuid,
  plan_tier text,
  product_id text,
  subscription_state text,
  expires_at timestamptz,
  auto_renewing boolean
)
language sql
stable
security invoker
set search_path = public
as $$
  select s.organization_id, s.plan_tier, s.product_id, s.subscription_state,
         s.expires_at, s.auto_renewing
  from public.organization_subscriptions s
  join public.profiles p on p.home_organization_id = s.organization_id
  where p.id = (select auth.uid()) and p.is_active = true
  limit 1;
$$;

grant execute on function public.current_subscription_entitlement() to authenticated;;
