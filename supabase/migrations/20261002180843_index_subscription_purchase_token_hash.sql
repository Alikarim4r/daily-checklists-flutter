create index if not exists organization_subscriptions_purchase_token_hash_idx on public.organization_subscriptions(purchase_token_hash) where purchase_token_hash is not null;;
