# Technical review and production hardening plan

> Implementation update: critical/high-priority phases now extend through
> migrations 027–031 and release candidate 1.2.0+5. See
> `IMPLEMENTATION_SUMMARY_2026-08-12.md` for verified changes, build results,
> manual staging gates, and intentionally deferred enhancements.

Date: 2026-08-12  
Scope: Entry, Viewer, Admin, shared Flutter package, Supabase/PostgreSQL, Storage,
offline sync, and report generation.

## Executive assessment

The project is an established three-application Flutter system and should be
improved incrementally. Its current foundation is stronger than a prototype:
organization/site scoping, RLS, private Storage, UUID-based platform ownership,
optimistic versions, idempotent offline client references, encrypted offline
outbox data, multilingual catalog items, and server-side submission validation
already exist. The safest route is additive migrations and small compatible UI
changes, not a rewrite.

The highest-risk gaps found in the review were: future dates were not rejected by
the database; draft Storage deletion included technicians; approved immutability
depended mostly on individual RPC checks rather than universal triggers; and
there was no central append-only audit log. Migration 027 addresses these four
gaps and is intentionally additive.

## Current architecture and modules

- `apps/checklist_entry`: field data entry, photos, signatures, local drafts,
  encrypted outbox, save/submit workflow.
- `apps/checklist_viewer`: scoped hierarchy browsing, review/approval, A4 form,
  PDF/print export, supervision dashboard, notifications.
- `apps/checklist_admin`: organizations, zones, sites, templates, themes, users,
  policies, report logos, and privileged deletion.
- `packages/checklist_shared`: models, repositories, Supabase bootstrap,
  authentication gate, session/biometric policy, themes, common widgets,
  offline queue, reports, and operational metrics.
- `supabase/migrations`: the authoritative schema and security evolution.
- `supabase/tests`: reproducible PostgreSQL migration and workflow smoke tests.
- `web_portal`: release/download portal for hosted builds.

All applications use the same Supabase project and shared repository layer.
Sensitive workflow writes are performed through `SECURITY DEFINER` RPCs with
explicit authorization and optimistic-version checks; direct workflow-table
mutations are revoked from clients.

## Authentication, session, and authorization

Supabase Auth is authoritative. `public.profiles` stores the application role,
activation and approval state, while platform ownership is protected by
`public.platform_owners` UUID membership rather than a mutable email. Site scope
is represented by `public.user_site_access`, including read/write/manage flags.
Organization super administrators are constrained by their home organization;
site administrators operate through their site/campus scope.

Biometrics are a local unlock layer, not a second identity provider. The shared
relock policy now avoids prompting for ordinary navigation or window resize and
only relocks after a meaningful background interval. Supabase session refresh
continues to control server access.

## Database and RLS assessment

Core hierarchy tables are organizations, zones, sites, profiles, and
user-site-access. Checklist tables include templates, template items, site items,
organization policy, inspections, inspection items, and corrections. Storage is
private and paths are scoped as:

`organization_id/site_id/inspection_id/file_name`

RLS and helper functions already enforce organization/site scope for reads and
writes. Migration 019 fixed the previously unsafe self-profile update and moved
platform-owner checks to immutable UUID membership. Migration 020 moved workflow
mutations into RPCs with version locking. Migration 021 added batched reads and
path-aware Storage policies.

Migration 027 adds defense in depth:

- Database rejection of inspection dates after the Qatar business date.
- Owner-only date correction RPC with expected version and mandatory reason.
- Technician denial for removal of already-stored signature/photo evidence.
- Storage deletion limited to a scoped manager before approval.
- Universal triggers that make approved inspections and their items immutable.
- Append-only audit events for inspection, item, approval and Storage deletion.
- RLS-protected audit visibility for the platform owner or scoped site manager.

## Storage, photos, signature, stamp, logo, and reports

Checklist media uses a private bucket and signed URLs. Serialized evidence
supports legacy strings, arrays, and v2 issue/fix pairs. Submission validation
checks that required signature and evidence objects exist under the inspection
prefix. The Entry app can queue local image/signature bytes for later upload;
Viewer/report code resolves signed content and generates the A4 report.

Previously observed signature clipping was addressed in the shared signature-pad
layout by placing labels outside the drawable canvas. Report branding is resolved
centrally through the report-logo path and organization/site hierarchy. Remaining
visual acceptance checks must cover real Arabic names, large logos, embedded
photos, photo links, Android, macOS, and web print output.

## Offline and synchronization behavior

The offline outbox is stored in encrypted Hive data. Entries carry the base
server version and a stable `client_reference`. Sync uses optimistic conflict
detection and can resume after a save checkpoint without silently overwriting a
newer server record. Pending, syncing, and failed states exist in the queue.

The end-user sync-status screen, explicit retry, encrypted auto-save, optimistic
conflict detection, stable client references, and resumable save checkpoints are
implemented. Remaining operational follow-up is retention cleanup for abandoned
failed entries, an optional storage quota indicator, and real two-device staging
fault-injection. Server-side uniqueness and idempotency remain authoritative.

## Supervision and performance assessment

The supervision dashboard uses operational metric models and batched latest/
history RPCs. The major prior causes of slowness were repeated per-inspection item
queries, repeated signed-URL generation, unnecessary full-screen rebuilds, and
large unpaginated result sets. The repository now supports batch item reads and
signed-URL caching, but large deployments still require cursor pagination,
server-aggregated KPI queries, bounded date ranges, and lazy report image fetches.

Scope filters must always send permitted site IDs and must never rely on hiding
unauthorized UI. RLS remains the final boundary. Future KPI/ranking formulas
should be calculated from a documented server function so mobile and web produce
the same result.

## Root causes of reported critical issues

1. Future date: both Entry and Viewer used “now + 1 day” as a date-picker limit,
   and the draft RPC accepted any date. Fixed in UI and database.
2. Date modification: creating/loading a different daily record was available,
   but there was no explicit audited date-correction operation. Added owner-only
   RPC and Viewer owner control.
3. Evidence deletion: `can_delete_checklist_media` allowed any draft writer and
   Entry detached then deleted stored objects. Fixed with manager-only Storage
   deletion and database detection of removed evidence references.
4. Approved lock: current RPCs checked approval, but a new future RPC could omit
   the check. Added parent/item mutation triggers.
5. Auditability: corrections had a narrow history table; workflow, evidence,
   and date events were not centralized. Added append-only audit log and Admin UI.
6. Web upload risks: image selection and preview depend on web-safe bytes rather
   than native file paths. All new upload changes must use byte APIs and test
   Chrome/Safari explicitly.

## Change classification

No schema change is required for: picker limits, loading skeletons, repaint
boundaries, dark-mode contrast, local image compression, report layout, app
version display, and biometric prompt timing.

Schema/RPC changes are required for: comprehensive audit, owner date correction,
approved immutability, returned/rejected/canceled workflow, notifications,
corrective actions, saved filters, reference numbers, QR identities, location
evidence, template versioning, answer types, conditional rules, item criticality,
fine-grained/temporary permissions, and durable monitoring events.

## Security, data-loss, compatibility, and performance risks

- Security: any `SECURITY DEFINER` function must fix `search_path`, validate
  `auth.uid()`, verify tenant/site scope, and have narrow grants.
- Data loss: deleting media before successfully saving a detached reference can
  orphan or erase evidence. The database now blocks technician removal; manager
  deletion still requires UI confirmation and operational backup retention.
- Compatibility: adding enum workflow states requires coordinated server and all
  three Flutter clients. It should ship in its own compatibility release.
- Performance: item-level audit is intentionally detailed and will grow quickly.
  Production needs retention/archival policy and indexed bounded queries.
- Privacy: audit and photo metadata can contain personal data. Access is scoped,
  and exports must avoid exposing signed URLs beyond their intended lifetime.

## Recommended implementation sequence

1. Apply and validate migration 027 in staging; run negative RLS/role tests.
2. Complete web signature/logo/upload/stamp regression tests.
3. Fix supervision filters/error handling and add server-side pagination.
4. Add returned/rejected/canceled workflow and relevant notifications as one
   compatibility migration and synchronized client release.
5. Add corrective actions and evidence-before-close rules.
6. Add template version snapshots, answer types, required/critical weights, and
   conditional logic without altering historical inspection items.
7. Add saved filters, richer reports, automatic references, and QR/location
   capabilities.
8. Establish monitoring, backup restore drills, staged rollout, and release
   observability before broad production deployment.

## Validation gates

Every phase must pass formatting, static analysis, unit/widget tests, the full
PostgreSQL migration chain, role-negative tests, web build, Android build, and
affected desktop build. Staging must include technician, viewer, site manager,
organization manager, and platform-owner accounts. Production migration requires
a verified backup and a documented rollback/forward-fix decision.
