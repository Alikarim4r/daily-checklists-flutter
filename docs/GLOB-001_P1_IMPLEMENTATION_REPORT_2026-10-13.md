# GLOB-001 / P1 Implementation & Pre-Release Handoff
**Project:** Daily Checklists · **Phase:** Universal Library 2.0 · **Date:** 2026-10-13
**Status:** PRODUCTION DEPLOYED and production schema/data-parity verified; authenticated live end-to-end UI QA pending.

## Approved scope and delivered implementation
1. GLOB-001 P1-00: `20261013230000_global_library_revision_entitlement.sql` fixes archive RLS via `can_read_global_library_revision(uuid)` SECURITY DEFINER authorization check. Only platform owner or approved user with **currently entitled home organization** can read archived item bodies. Purchase revocation tested.
2. P1-01: `20261013231000_global_library_taxonomy.sql`: additive taxonomy terms (industry/domain/subdomain), multi-sector/template link table, document kinds + execution flags, validation/frequency classification, jurisdiction, optional locales, owner-write RLS and active-user read controls. 19 initial industry terms, 18 domain terms and 13 document kinds; only checklist is executable in P1.
3. P1-02: deterministic backfill maps all 18 pre-existing library category slugs to independent sectors/domains; supplements specific known template slugs. Preserves template UUID, legacy category_id and facility_tags, seven item languages, installs, purchases, 93 archived snapshots and original A4.
4. P1-03: `20261013232000_global_library_v2_read_api.sql` adds paginated, organization-scoped, text/sector/domain/type-filtered catalog metadata RPC `list_global_library_v2` and term/count RPC `list_global_library_facets_v2`. Does not return paid item bodies. Old `list_checklist_library(uuid)` remains unchanged.
5. P1-04: `20261013233000_global_library_owner_curation.sql` adds atomically validated owner-only taxonomy curation RPC `assign_global_library_taxonomy_v2` and immutable `library_taxonomy_audit_log`. Ordinary users cannot edit classifications; unknown/empty slugs are rejected.
6. CheckAdmin Web/UI: category, global sector, domain, document-kind, access, installed-only and search filters; responsive wrapping, localized Arabic/English labels, 100-row server pages with load-more, owner-only edit-classification dialog; read-only catalog availability with paid entitlement flags.
7. Shared Flutter library: extended library template model with optional global taxonomy metadata, localized facet model, V2 repository methods and error-scoped fallback to old RPC **only for missing endpoint** (NOT permission denials). No CheckIn or CheckView business logic changed.

## Source inventory verified in LIVE production (read-only Supabase connector)
- Project: `daily-checklists`.
- 79 library template rows, **79 published**, 18 categories, 93 revision snapshots, 8 organization installs, 61 purchase records at time of audit.
- PRE-MIGRATION observation: revision RLS was `is_platform_owner() OR is_approved_active_user()`. It lacked per-template purchase entitlement. This is now repaired in production using `can_read_global_library_revision(library_template_id)`.
- PRE-MIGRATION observation: taxonomy table / V2 RPC did not exist. Both now exist in production and permission checks confirm anonymous EXECUTE is disabled.
- Production migrations and CheckAdmin Web deployment performed with owner authorization; CheckView, CheckIn, billing plans, and mobile store releases were not changed.

## Test evidence and gates
| Test | Observed result |
|---|---|
| Flutter analyzer: shared / CheckAdmin / CheckIn / CheckView | 4/4 clean |
| Flutter test: shared / CheckAdmin / CheckIn / CheckView | 94 + 11 + 16 + 31 = **152 passing** |
| Existing P0 legacy compatibility fixtures | Included in shared suite; unchanged A4 / hierarchy / offline semantics |
| New V2 model/API fallback tests | 4 passed: 2 sectors + domains, old JSON response, no RLS-denial fallback, localization |
| PostgreSQL schema migration, **clean disposable PG16 cluster** | All 4 migrations pass |
| SQL entitlement / organizational authorization | PASS (Org A/B, owner, suspended account, purchase cancelled, archived free vs premium, non-entitled locked UI) |
| SQL owner edit + audit | PASS (non-owner rejection, unknown taxon rejected, atomic mappings, audit record, old revision unaltered) |
| Synthetic 10k-template pagination | PASS: page of 100 near offset 9900 in **~1.94s** locally |
| `flutter build web --release` for CheckAdmin /admin/ | PASS, output `/private/tmp/checkadmin-p1-global-library-preview-web` |
| Live production SQL policy/role grants post-migration | PASS (policy, anon denied, authenticated can execute); full actual-user JWT scenarios not run |
| Authenticated live CheckAdmin visual/interaction QA | **NOT RUN**; now awaits session-based owner acceptance |
| Multi-country/legal/clinical certification | Out of P1 scope; **no such claims** |

## Controlled production rollout plan (approval required)
1. Freeze CheckAdmin catalog writes briefly and take verified export/backup (templates, items, revision snapshots, installs and purchases). Check for exact source vs live schema parity.
2. Apply `20261013230000` **SECURITY ONLY** first; test with actual identity classes (owner, Org A paid, Org B unpaid, suspended, revoked) and verify SQL policy. If any access regression, stop and resolve; never open revisions to all authenticated users.
3. Apply `20261013231000` taxonomy, `20261013232000` versioned catalog API, `20261013233000` owner curation, in order; verify all 79 library IDs and 93 revision identities preserved, plus installs/purchases unchanged.
4. Run read-only live migration checks, sample 79 template taxonomies and null/orphan checks. Confirm old catalog RPC response and client imports remain unchanged; validate page/filter RPC with controlled user JWTs.
5. Publish **CheckAdmin web only** from the built tested source, without touching CheckView or CheckIn; use separate worktree and asset-only deployment. Wait for Pages successful build and verify live JS checksum.
6. User acceptance: owner edits sector classifications and sees audit; entitled clients install; unauthorized clients cannot read bodies; 320dp and desktop Arabic/English layouts; test refresh/caching and rollback path.
7. Regressions: revert CheckAdmin UI and V2 API usage behind old RPC, but retain the fixed security policy. Avoid deleting taxonomy tables or revision history; no destructive rollback of customer data.

## Important limits and follow-up
- Existing library expansion's seven language strings pass machine completeness but **not necessarily professional translation/sector validation**. Future professionally reviewed packs P2/P4.
- P1 doesn't turn PPM, Method Statements, RA, COP or PTW into executable workflows; document kinds are metadata-only until P2/P3.
- 10k deep offset paging took ~2 seconds in local DB; keyset pagination/search indexes should be prioritized before mass-catalog launch.
- Global taxonomies are independent of physical locations; existing Organization → Site → Building → Floor → Area → Checklist remains untouched.
- The project working tree already had numerous unrelated uncommitted files; P1 edits were applied to the current local working tree, with no reset/checkout of unrelated files. **Avoid blindly staging all changes or deploying from a stale branch**.
- One end-to-end package of source patches with original file bases must be prepared before deployment if repository synchronization is required; do not assume untracked Flutter files are already in Git history.

## Repeatable tests
- `bash scripts/audits/run_p1_isolated_postgres.sh` (disposable PostgreSQL, no prod credentials).
- `cd packages/checklist_shared && flutter test --no-pub`
- `cd apps/checklist_admin && flutter test --no-pub && flutter analyze --no-pub`
- `cd apps/checklist_entry && flutter test --no-pub && flutter analyze --no-pub`
- `cd apps/checklist_viewer && flutter test --no-pub && flutter analyze --no-pub`

**Decision:** P1 production schema is deployed and CheckAdmin Web is published; production data diff against private backup is zero. Authenticated end-to-end UX acceptance still requires a real user session, and regulatory/translation expertise remain outside P1 scope.

## Production rollout record — 2026-10-13 (supersedes the pre-release plan above)
- Supabase project: `daily-checklists`; private backup schema: `p1_rollout_backup_20261013`. Owner-access only; created before SQL migrations.
- Applied sequentially and successfully: `p1_private_catalog_preflight_snapshot_20261013`, `p1_00_secure_library_revision_entitlement`, `p1_01_global_library_taxonomy_backfill`, `p1_02_global_library_v2_catalog_rpc`, `p1_03_global_library_owner_curation`.
- Production counts after migration: **79 templates (all published); 18 original categories; 948 original item records; 93 original snapshots; 8 original installs; 61 purchase records**. Added **19 industry terms; 18 domain terms; 13 document kinds; classification of all 79 templates; 310 taxonomy mappings**.
- Exhaustive `EXCEPT ALL` comparison against the private point-in-time backup returned **zero differences** for original templates, items, revisions, installs and purchases. Original API retained unchanged.
- Production revision policy now `can_read_global_library_revision(library_template_id)`. Four new RPC/security-helper functions have **no EXECUTE grant for anon**; authenticated grants exist but function-level checks apply.
- CheckAdmin static deployment: `gh-pages` commit **`6327970415867536df2f8206e14ba99492dafed6`**. Only four files under `admin/` changed. GitHub Pages status **built**. Production `https://inspection.alielhassan.com/admin/main.dart.js` byte-identical to `/private/tmp/checkadmin-p1-global-library-qa-final/main.dart.js` at verification. Web version still `1.5.3 (27)`.
- Local tests: 94 shared + 11 Admin + 16 Entry + 31 Viewer = 152 successful; Flutter analyzer zero issues across all 4 packages; isolated PG test suite passed and 10k-item page test ~1.4–2.0s. Final release web build passed.
- **Open acceptance**: no end-to-end interaction with a logged-in authorized production account was performed; request owner confirmation of Admin filters, owner edit action and installed-template permissions. A new security advisor scan found warnings already present in other legacy database functions; no claim of full system security audit is made.
- Deployment rollback if needed: revert ONLY the `admin/` GitHub Pages bundle to the preceding commit, preserving the tightened production archive policy and original records; leave additive taxonomy tables until migration rollback has been separately reviewed.
