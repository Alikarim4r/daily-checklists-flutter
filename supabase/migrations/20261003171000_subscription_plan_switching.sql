-- Persist the exact Google Play base plan/offer so monthly/annual variants are
-- represented correctly and subscription replacements can be shown accurately.
alter table public.organization_subscriptions
  add column if not exists base_plan_id text,
  add column if not exists offer_id text;

drop function if exists public.current_subscription_entitlement();
create function public.current_subscription_entitlement()
returns table (
  organization_id uuid,
  plan_tier text,
  product_id text,
  base_plan_id text,
  offer_id text,
  subscription_state text,
  expires_at timestamptz,
  auto_renewing boolean
)
language sql
stable
security invoker
set search_path = public
as $$
  select s.organization_id, s.plan_tier, s.product_id,
         s.base_plan_id, s.offer_id, s.subscription_state,
         s.expires_at, s.auto_renewing
  from public.organization_subscriptions s
  join public.profiles p on p.home_organization_id = s.organization_id
  where p.id = (select auth.uid()) and p.is_active = true
  limit 1;
$$;

revoke all on function public.current_subscription_entitlement() from public, anon;
grant execute on function public.current_subscription_entitlement() to authenticated;
