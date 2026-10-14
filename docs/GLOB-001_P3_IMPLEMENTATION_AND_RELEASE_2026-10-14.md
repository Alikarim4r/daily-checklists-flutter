# Daily Checklists — P3 A+B+C Production Delivery

**Product:** Daily Checklists · **Date:** 2026-10-14 · **Global HSE & Technical Documentation**

## P3-A — Versioned document governance
- Organization/site/asset/PPM work-order references, category/kind, document reference, jurisdiction and standard edition.
- Immutable document-version snapshots, status transitions (draft, in review, approved, rejected, superseded), change notes, independent author/reviewer check and immutable approval-decision log.
- Multi-tenant RLS with SELECT-only end-user grants; guarded write RPCs; cross-organization link checks. An approved version cannot be changed; supersession keeps old document and links the replacement.

## P3-B — Typed technical documentation
- Actual editor and schema validation for Method Statement, Risk Assessment (5x5 initial/residual scoring), JSA, SOP and COP/standard references, with typed fields rather than raw JSON.
- Initial/residual control scores validated on server; ordered work steps; source and edition required for regulatory reference.
- No automatic regulatory approval, certification, authority signature or professional validation is implied.

## P3-C — Safety and quality workflows
- PTW: draft/approve, link approved RA/JSA, controlled expiry max 30 days, issue, suspend, resume and close with append-only events.
- ITP: checkpoint types hold/witness/review/test; verified criteria; signed evidence; independent authorized sign-off for hold/witness.
- NCR: finding, root cause and corrective action; independent closure/disposition after approval; optional submitted same-organization inspection evidence.
- Link to existing PPM work orders, sites and assets. Existing CheckView/CheckIn and A4 layouts are unchanged.

## Confirmed quality gates
- Disposable isolated PostgreSQL integration: **PASS** for all 8 document kinds, tenant read separation, role-based self-approval denial, 5x5 risk validation, historical version protection, PTW issue/lifecycle, ITP hold sign, NCR independent closure, supersession.
- Flutter static analyzer: no issues across checklist_shared, CheckAdmin, CheckIn and CheckView at final source validation.
- Flutter tests: **100 shared + 17 CheckAdmin + 16 CheckIn + 31 CheckView = 164 passing**.
- Production: applied P3-A, P3-B and P3-C migrations in order after private preflight snapshot schema `p3_rollout_audit_20261014`.
- All nine baseline legacy table row counts remained unchanged; new technical-document/permit/ITP/NCR tables intentionally start with 0 customer records.
- Anonymous EXECUTE disallowed on all `technical_*` guarded APIs.
- Separate source commit and CheckAdmin-only GitHub Pages release recorded below after deployment.

## Operational acceptance and limits
- **Important blocker for independent live sign-off:** at time of verification, the single active approved `super_admin` was not assigned to an organization; there were no active `site_admin` accounts. A second organization-scoped authorized reviewer must be assigned before fully exercising reviewer/approver workflows under separate production identities. Do not allow self-approval as a workaround.
- A production rollback-only role-context test of authoring, submission and self-approval/PTW-before-approval denial was executed without retaining test records. It is not a complete live GUI/UAT with multiple human identities.
- PTW is a software authorization workflow, not an override of jurisdictional legal permit/signature requirements.
- No Google Play or App Store releases, cloud subscription pricing changes or schema changes to old inspection/PPM datasets were made.

## Release
- Source branch: `feature/global-hse-p3-20261014`; CheckAdmin release separately pushed to `gh-pages`.
- Confirm the exact published JS file hash with the compiled release after GitHub Pages build completes; record success before claiming CDN propagation.
