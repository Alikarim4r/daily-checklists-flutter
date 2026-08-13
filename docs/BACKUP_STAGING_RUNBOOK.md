# Backup, staging, and release runbook

## Environments

Maintain separate Supabase projects for local/test, staging, and production.
Never point staging mobile/web builds at the production URL. Keep environment
URLs and public anonymous keys outside source control and use distinct Storage
buckets and Auth users in every environment.

## Before a database release

1. Record the deployed application and migration versions.
2. Create a provider-managed database backup and verify its completion.
3. Export schema-only and critical business tables to encrypted operational
   storage with documented retention.
4. Confirm Storage backup/retention for checklist evidence and report logos.
5. Apply migrations to a restored staging snapshot.
6. Run `scripts/check_quality.sh` and the role/security acceptance matrix.
7. Exercise Entry offline submit, Viewer approval/export, Admin user/scope edits,
   audit visibility, and evidence deletion denial.
8. Obtain an explicit go/no-go decision and schedule a monitored deployment.

## Restore drill

At least quarterly, restore the most recent backup into an isolated project,
verify row counts and checksums for hierarchy/inspection tables, sample private
media retrieval, run the migration smoke suite, and document recovery time and
recovery point. A backup that has not been restored successfully is not treated
as verified.

## Migration rules

- Migrations are additive and immutable after production deployment.
- Never drop historical inspection/evidence/audit data in the same release that
  introduces a replacement structure.
- New RPCs use explicit grants, `SECURITY DEFINER`, fixed `search_path`, RLS-aware
  authorization helpers, and negative tests.
- Enum additions ship only when all supported clients can parse the new values.
- For non-reversible data transformations, provide a forward-fix script and a
  verified backup restore procedure instead of promising an unsafe rollback.

## Rollout and monitoring

Deploy database changes first only when old clients remain compatible. Then
release web to staging, Android internal testing, and macOS staging. Monitor Auth,
PostgREST, database, Storage, sync failures, approval latency, and export errors.
Promote gradually and keep the prior signed binaries and portal assets available
until the observation window closes.

## Role acceptance matrix

- Technician: create/save/submit in assigned scope; cannot future-date, change
  saved date, delete stored evidence, approve, or cross scope.
- Viewer: read only approved records in assigned scope.
- Site manager: review and manage pre-approval evidence only for managed sites.
- Organization manager: manage only sites and users in the bound organization.
- Platform owner: global administration and audited date correction; cannot
  mutate or delete approved inspection history.

