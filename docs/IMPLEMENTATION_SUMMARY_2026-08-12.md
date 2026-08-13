# Implementation summary — release candidate 1.2.0+5

Date: 2026-08-12  
Target environment: staging  
Applications: Entry, Viewer, Admin, Web portal

## Release status

The critical and high-priority hardening phases are implemented and pass the
local quality, migration, security-smoke, Web, Android-debug, and macOS-release
build gates. The changes remain a **staging release candidate**. No production
database migration or production deployment was performed because the required
backup/restore evidence, staging role matrix, and distribution signing material
are external release gates.

The implementation is additive. It does not rewrite historical inspections,
delete legacy evidence, or retroactively replace checklist snapshots.

## Fixed issues and implemented capabilities

### Security, workflow, and audit

- Future inspection dates are rejected in Entry/Viewer and by PostgreSQL using
  the Qatar business date.
- Existing inspection dates can only be corrected by the platform owner through
  an optimistic-lock RPC with a mandatory reason and complete audit event.
- Technicians cannot delete stored evidence. Authorized pre-approval deletion is
  scope checked and audited; approved evidence remains immutable.
- Approved/terminal inspections and items are protected by universal database
  triggers, not only hidden UI actions.
- Returned, rejected, canceled, and approved workflow transitions use scoped
  RPCs with expected versions, mandatory reasons, and notifications.
- The append-only audit trail covers inspection, item, workflow, permission,
  hierarchy, checklist, evidence, and corrective-action changes.
- The Admin app exposes searchable audit history.

### Templates, references, and evidence

- Published checklists are immutable. A change is made by cloning a draft
  version and publishing it atomically; the prior published version is retired.
- Inspections store a stable template/version/name snapshot, so historical
  content is not changed by a later template release.
- Every inspection receives a stable searchable reference number.
- Media evidence has normalized metadata: inspection, item where applicable,
  site, uploader, timestamp, kind, storage path, and stable photo reference.
- Legacy `image_path` and signature records are backfilled without deleting the
  legacy fields.
- Duplicate same-site/day creation is blocked by default. A controlled
  reinspection requires an explicit reason and is audited.

### Corrective actions

- A corrective action can be created directly from a failed inspection item and
  remains linked to the inspection, item, and site.
- Priority, assignee, due date, status, comments, evidence requirement, closure
  details, optimistic version, audit, and assignment notifications are present.
- Critical/evidence-required actions cannot be closed without evidence.
- The Viewer provides scoped search, status/priority filters, transition actions,
  evidence upload, and manager verification/closure.

### Entry, offline, and session behavior

- Draft edits auto-save after a short debounce and on app lifecycle/navigation
  changes, including signature bytes in encrypted offline storage.
- The offline outbox uses stable client references and optimistic version
  checkpoints to prevent duplicate submission and silent overwrite.
- The Sync Status screen shows pending records, pending images, failed records,
  last successful sync, detail, and retry.
- Validation failures remain server drafts; transport failures are queued instead
  of being mislabeled as backend validation errors.
- Biometrics are a local unlock. Navigation and window resize no longer cause a
  prompt; relock occurs only after a meaningful background interval.

### Images, signature, stamp, logo, and reports

- The signature label/actions are outside the drawable canvas, including the
  upper edge. Historical and newly captured signatures resolve from bytes on
  mobile, desktop, Web, and PDF.
- The signature is normalized to readable blue ink and cached signed downloads
  are bounded.
- Web/desktop image selection uses byte-safe file selection and validates empty,
  corrupt, unsupported, and low-resolution images before upload.
- Captured evidence is resized/compressed for transport while the stored evidence
  relationship remains database based.
- Arabic photo stamps are rendered by Flutter text shaping rather than bitmap
  glyph drawing, preserving RTL names and line layout.
- Ministry/site logos are validated, aspect-ratio safe, larger, and centrally
  resolved for screens and reports.
- Inspection PDF export now offers:
  - embedded optimized photo evidence; or
  - stable photo references with time-limited secure links.
- Photo references are based on item/photo order (for example 5.1) and never on
  PDF pagination. Report filenames use the stable inspection reference.
- A4 reports include inspection reference and checklist version.

### Supervision, performance, and observability

- Supervision loading has stale-response protection, explicit loading/error/empty
  states, and structured failure reporting.
- Filters include Today, This Week, This Month, Last Month, Last 3 Months, Last 6
  Months, This Year, and unrestricted From/To selection using Qatar time.
- Large header reads are paged in 500-row batches and site filters are chunked to
  avoid PostgREST URL/row limits.
- Detailed latest/history data uses batched RPCs, replacing per-inspection N+1
  item reads. Signed media downloads use a short bounded cache.
- The dashboard provides scoped KPIs, follow-ups, open/overdue issues, a
  documented transparent site ranking, and scoped PDF export.
- Client crash/API/upload/sync/report failures are captured with app version,
  platform, module, type, and timestamp. Tokens, email, query values, and long
  opaque values are redacted. Repeated events are throttled.
- Only the platform owner may view client error logs, through the new Admin
  monitoring screen.
- Site grants now support start/expiry timestamps and stop authorizing read/write
  operations immediately after expiry.
- Version and build number are visible in Settings → About.

### UI and portal

- Shared cards use the required 50% surface opacity; the vector background is
  visible and subtle in both light and dark modes.
- Theme resolution follows organization → zone → campus/site → checklist type,
  with draft-template editing and published-version immutability.
- The portal and all three Web apps are built as staging version 1.2.0+5.
- The portal verifies native artifact version/build before copying it. Old 1.1.x
  Android/macOS files are no longer presented as current downloads.

## Database migrations

- `027_critical_guardrails_and_audit.sql`: Qatar date guard, owner correction,
  evidence deletion restrictions, terminal immutability, append-only audit.
- `028_workflow_notifications_and_admin_audit.sql`: workflow states/RPCs,
  notifications, auth session audit, and privileged-entity audit triggers.
- `029_references_versions_corrective_actions.sql`: template lineage/versioning,
  inspection references/snapshots, normalized evidence, corrective actions.
- `030_controlled_reinspections.sql`: duplicate-period guard and reasoned
  reinspection RPC.
- `031_temporary_access_and_error_monitoring.sql`: expiring grants and
  privacy-conscious client error monitoring.

## RLS and permission changes

- Audit is readable only by platform owner or the scoped manager allowed by its
  site context; normal users cannot edit audit rows.
- Error logs can be inserted only by the authenticated user for their own UUID
  and selected only by the platform owner.
- Evidence and corrective actions inherit site access; corrective mutations are
  RPC-only and role/state checked.
- Template version mutation/publish is owner-only and protected again by
  published-row triggers.
- Existing organization-super-admin and site/campus access boundaries remain the
  final database authorization boundary; UI filtering is not trusted.
- Expired site grants are enforced by `has_site_access`, `can_write_site`, and
  `can_manage_site` database helpers.

## Main modified modules

- `apps/checklist_entry/lib/main.dart`: auto-save, offline media, sync status,
  controlled reinspection, validation, monitoring.
- `apps/checklist_viewer/lib/main.dart`: workflow/date/report/evidence actions,
  notifications, corrective-action entry points.
- `apps/checklist_viewer/lib/screens/ops_dashboard_screen.dart`: robust flexible
  filtering, pagination-aware metrics, export, monitoring.
- `apps/checklist_viewer/lib/screens/corrective_actions_screen.dart`: scoped
  corrective-action workflow.
- `apps/checklist_admin/lib/screens/checklists_tab.dart`: draft/published version
  management and immutable published UI.
- `apps/checklist_admin/lib/screens/users_tab.dart`: temporary access windows.
- `apps/checklist_admin/lib/screens/audit_log_screen.dart` and
  `client_error_log_screen.dart`: operational audit/monitoring.
- `packages/checklist_shared`: models, repositories, reports, offline queue,
  signature/photo/stamp validation, session policy, error reporting, and common UI.
- `scripts/build_web_portal.sh`: version-safe release artifact packaging.

## Automated validation performed

- `./scripts/check_quality.sh`: passed completely.
- Dart formatter: 110 files checked, no changes required.
- Flutter analyzer: shared package plus Entry, Viewer, Admin — zero issues.
- Automated Flutter tests: 49 passed in total.
- SQL static parse/security invariants: 31 migrations passed.
- PostgreSQL integration: a clean database applied migrations 001–031 and passed
  workflow/RLS smoke tests.
- Security smoke includes future dates, terminal immutability, role boundaries,
  stable snapshots/references, controlled reinspection, evidence-required
  corrective closure, expired access, audit, notification, and error log storage.
- Web portal HTML/links/download guards and JavaScript syntax: passed.
- Release Web build: Entry, Viewer, Admin passed, including Wasm dry-run compile.
- Android staging debug build: Entry, Viewer, Admin passed.
- macOS staging release build: Entry, Viewer, Admin passed.
- `git diff --check`: passed.

## Required manual staging tests

1. Apply 027–031 to a restored staging snapshot only after capturing baseline row
   counts and storage samples.
2. Test accounts for technician, viewer, site manager, organization manager, and
   platform owner; verify negative direct REST/RPC/Storage requests.
3. Chrome, Safari, Android, and macOS: upload multiple JPG/JPEG/PNG images,
   simulate interruption/retry, then verify evidence metadata and signed retrieval.
4. Draw across all signature edges, submit/approve, reopen on Web/mobile, and
   inspect embedded/link PDF modes in Arabic and English.
5. Two-device offline conflict, process termination during sync, token refresh,
   five-minute background biometric relock, and revoked-session behavior.
6. Large date range and large embedded-photo report memory/time test using a
   staging dataset comparable to production.
7. Restore a provider backup into an isolated project and record RPO/RTO, counts,
   checksums, and sampled media retrieval.

## Known limitations and intentionally deferred enhancements

The following priority-3 items were intentionally not represented as complete;
they need a separate schema/product phase and staging acceptance rather than a
partial implementation hidden behind UI controls:

- server-synchronized saved filter views;
- native XLSX export (PDF is implemented; CSV/XLSX format needs an approved
  reporting schema);
- site/asset QR identity and deep-link routing;
- optional GPS/location evidence and its privacy policy;
- numeric/text/dropdown/multiple-choice/date item types and configurable
  conditional rules;
- per-item critical/major/minor weights integrated into a formally approved KPI;
- a fine-grained action permission matrix beyond the existing role plus scoped
  read/write/manage model;
- configurable custom-period comparison and deeper recurring-issue analytics;
- signed Android AAB/APK, notarized Developer-ID macOS packages, and iOS
  TestFlight artifacts.

Native distribution is blocked by missing Android release keystore variables and
missing Apple Developer ID/notary credentials. Debug artifacts are deliberately
not published to the portal. Production deployment is blocked until the backup
restore drill and staging acceptance matrix are complete.

