-- P2 production background processing: hourly PPM scheduler.
-- pg_cron is a Supabase-supported Postgres extension; do not disable it
-- during rollbacks because other projects may use existing cron jobs.
create extension if not exists pg_cron with schema pg_catalog;
grant usage on schema cron to postgres;
grant all privileges on all tables in schema cron to postgres;
-- Schedule only our named job; cron.schedule(name,...) updates by name.
select cron.schedule(
  'daily-checklists-ppm-hourly-v1',
  '15 * * * *',
  'select public.fm_ppm_scheduler_tick()'
);
