-- PostgreSQL requires a newly added enum value to commit before it is used.
alter type public.subscription_plan add value if not exists 'business' after 'professional';
