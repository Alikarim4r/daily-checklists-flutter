# GLOB-001 / P2 — Global Asset & Planned Preventive Maintenance Implementation

**Date:** 2026-10-14 · **Status:** Supabase P2 schema and CheckAdmin Web successfully deployed; final Pages live build verification pending. CheckIn PPM source tested but CheckIn website/app stores deliberately not redeployed.
**Product:** Daily Checklists (CheckAdmin + CheckIn; CheckView unchanged by design)

## Implemented
- **Global asset register:** multi-organization, tenant-scoped asset codes, multilingual names, site/building/floor/area, type, importance and lifecycle state, optional manufacturer/model/serial. Database rejects cross-org or noncontiguous location mapping. Existing FM hierarchy and A4 checklists are not rewritten.
- **PPM schedules:** independent plan with asset, optional canonical checklist assignment, daily/weekly/monthly/quarterly/biannual/annual frequency, interval 1–24, IANA timezone, fixed anchor date and date-based occurrence counter. Month-end recurrence does not drift; completed jobs do not change later due dates.
- **Bounded materialization:** `fm_ppm_generate_due_jobs` generates due and upcoming jobs with (plan_id,due_on) unique constraint, locked scheduling, max 90-day horizon and max 1,000 per call; CheckAdmin auto-generates a bounded 45-day window when the organization manager opens/refreshes PPM. **No independent cron/automations scheduler configured**.
- **Execution:** individual work orders (scheduled/in_progress/completed/skipped), optional assigned technician, completion notes, JSON readings, optional submitted inspection evidence. Status changes and histories are server-verified; closed jobs/events are immutable. Authorized owner/super-admin can skip with a reason, pause/resume plan and assign staff.
- **Offline CheckIn:** new PPM work-order screen and normal app navigation icon; encrypted local job cache and completion outbox **separate** from existing A4 inspection queue; retry after online connectivity is restored. Identical completion attempts from the same executor are idempotent on the server and do not create duplicate completion events. Existing A4/offline logic is preserved.
- **Visibility:** PPM view uses **security_invoker=true** with the existing role/site RLS and computes overdue using the plan's IANA timezone. All write actions use guarded SECURITY DEFINER functions with no anonymous EXECUTE.
- **Global FM starter recipes:** 7 optional *draft* PPM instruction examples for chillers, cooling towers, pumps, electrical visual checks, irrigation, washroom conditions and fire exit observations. **Not OEM-reviewed or compliance-certified**, do not pretend they are safety work procedures.
- **CheckAdmin:** new Assets & PPM tab, asset hierarchy selector, starter recipes, A4 checklist assignment, timezone and frequency picker, owner organization choice, due/overdue counters, work-order completion and log, assignee selector, pause/resume, responsive Arabic/English interface. See `apps/checklist_admin/lib/screens/ppm_tab.dart`.
- **CheckView:** existing code/display preserved; no regression in viewer.
- **Actual A4 work forms:** completion may attach a submitted existing inspection from the **same org and optional checklist assignment**; entering inspection evidence ID is currently manual, not an automatic deep-link and no A4 document geometry was changed.

## Files
- `supabase/migrations/20261014001000_ppm_assets_and_schedules.sql`
- `supabase/migrations/20261014002000_ppm_execution_rpc.sql`
- `supabase/tests/p2_ppm_fixture.sql`
- `supabase/tests/p2_ppm_integration.sql`
- `scripts/audits/run_p2_isolated_postgres.sh`
- `packages/checklist_shared/lib/src/models/fm_ppm.dart`
- `packages/checklist_shared/lib/src/models/fm_ppm_starter_recipes.dart`
- `packages/checklist_shared/lib/src/repositories/fm_ppm_repository.dart`
- `packages/checklist_shared/lib/src/providers/providers.dart`
- `packages/checklist_shared/lib/checklist_shared.dart`
- `packages/checklist_shared/lib/src/offline/offline_inspection_queue.dart`
- `apps/checklist_admin/lib/main.dart`, `screens/ppm_tab.dart`
- `apps/checklist_entry/lib/main.dart`, `screens/entry_home.dart`, `screens/ppm_jobs_screen.dart`
- New unit/widget/offline tests `ppm_domain_test.dart`, `ppm_offline_outbox_test.dart`, `ppm_workbench_layout_test.dart`.

## Local QA and security
- Clean isolated PG16 integration suite: **PASS**, covers site/tenant isolation, invalid hierarchy, month-end/weekly/yearly date recurrence, IANA zone validation, twice-run idempotent schedule, worker vs admin grant, cross-tenant inspection rejection, legitimate completion evidence, idempotent offline completion replay, plan pause/resume, technician assignment, skip reason and terminal record/audit immutability.
- Encrypted Hive outbox test: **PASS**, PPM entries inaccessible to legacy inspection synchronization, clear on account purge, tenant/user scoped.
- Flutter shared unit/model tests: **100 passed**.
- CheckAdmin UI tests: **12 passed**, including RTL Arabic 320dp.
- CheckIn tests: **16 passed**.
- CheckView tests: **31 passed**.
- Flutter analyzer zero errors and warnings for four Flutter packages after fixes. Total **159 tests passed**.
- Build release and production verification, if performed, should be recorded separately below.

## Phased product limitations and release conditions
1. Scheduled jobs are generated **on PPM manager activity**, not an autonomous recurring cloud scheduler. A daily background job requires a separate approved scheduler and monitored rate limits; do not claim unattended generation.
2. CheckIn source implementation is prepared but **do not overwrite previously restored web /entry/ UI** without a version-preserving forward port or explicit owner acceptance. Production mobile app store releases require separately built and signed versions. The current CheckIn published web is older than the full local source.
3. No changes to CheckView code/assets; published Viewer remains unchanged.
4. No independently reviewed professional safety or manufacturer content. Starter recipes are drafts only.
5. Verify production schema and role policies; take preflight row-count and migration snapshot; apply both migrations sequentially, compare old data and new table counts, test with user JWTs after rollout. Failure rollback: revert only affected frontend assets and preserve existing historical data; avoid destructive DB drops.
6. The project root working tree contains many unrelated pre-existing dirty changes. Stage/commit **only** explicit P2 file list. Use an isolated `gh-pages` worktree and replace `admin/` artifacts only if deploying CheckAdmin; never rebuild the old Viewer or Entry from an unrelated/older local state.
7. Any change to iOS/Android releases, subscription pricing, cloud cron, or professional content review is separate from this P2 implementation.

## Production rollout record — 2026-10-14
- Live Supabase project `daily-checklists` (ref `xhdpyiklhouqwrtdwztn`). Preflight audit schema `p2_rollout_audit_20261014` stores the nine original table counts.
- Applied migrations `p2_private_schema_preflight_counts`, `p2_01_global_asset_register_and_planned_maintenance`, and `p2_02_ppm_execution_and_work_orders` successfully.
- Read-only live parity confirmed **all nine original table row counts unchanged** (5 orgs, 246 sites, 208 inspections, 79 library templates, 93 library revisions; remaining counts likewise matched).
- New production tables `fm_assets`, `fm_ppm_plans`, `fm_ppm_jobs` and `fm_ppm_job_events` have **0 rows**, intentionally: no synthetic/test records were created for real customers. New `fm_ppm_jobs_view` is present.
- GitHub Pages updated by pushing **CheckAdmin-only** static asset changes to `gh-pages` commit **`2bca278b9db19d6c9384da36fe4a851f3b1736f4`**, following successful CheckAdmin Release Web build. CheckView and CheckIn static bundles were unchanged.
- QA: 100 shared Flutter tests + 12 CheckAdmin + 16 CheckIn + 31 CheckView = **159 passing**, Flutter analyzers no outstanding issues across four packages. Separate isolated PG16 integration suite PASS (including timezones, 0 cross-tenant reads, historical immutable audit, expected assignment and revocation), real encrypted Hive outbox tests PASS, 320dp Arabic CheckAdmin widget PASS.
- **Pending real-user acceptance:** actual authenticated role workflows on production, creation of first real asset/plan/work order, and iOS/Android store release. Do not claim this was browser-tested under a real user JWT.
- **Important:** CheckIn is **not yet released to web or stores** because `/entry/` currently uses a deliberately retained older UI, and replacing it with the unmerged newer local source would be a regression. The PPM CheckIn implementation is complete and available in source for a controlled forward-port / release; existing CheckIn remains unchanged.
- No autonomous cron scheduler; generation on organization manager opening or refreshing PPM, plus explicit button. Draft professional template content is not certified.
- Website rollout status and exact live hash must be verified before making any completed CDN-delivery claim.
