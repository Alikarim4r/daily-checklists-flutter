# GLOB-001 / P0 — Independent Baseline Audit
**Date:** 2026-10-13 · **Product:** Daily Checklists (CheckAdmin, CheckIn, CheckView) · **Status:** P0 SOURCE AUDIT COMPLETE; P1 PRODUCTION GATE BLOCKED (SEC-P0-001)
**Scope:** Static inspection and non-destructive regression tests of the local Flutter/Supabase source. No production database queries, schema changes, deployments, billing actions, subscriptions or external AI agents.

## الملخص التنفيذي
تم تنفيذ فحص المرحلة P0 فعلياً لهيكل المكتبة والمشتريات والصلاحيات والإصدارات والتصنيفات. الأساس الحالي قابل للتوسعة عالمياً دون إعادة إنشاء التطبيقات الثلاثة. لكن نتيجة فحص الكود وحده لا تثبت أن جميع migrations مطبقة على قاعدة الإنتاج. اكتشفنا سياسة في أرشيف الإصدارات تحتاج إلى تصحيح أمني قبل إطلاق P1.

## 1. Verified source inventory (not live database counts)
| Component | Source and observed contract | Finding |
|---|---|---|
| Apps | `apps/checklist_admin`, `apps/checklist_entry`, `apps/checklist_viewer` | Three independent Flutter front ends on shared package |
| Shared business layer | `packages/checklist_shared/lib/src` | Shared models, Supabase repositories, localization, offline/sync, permissions, checklists and paper UI |
| Library category registry | `checklist_library_categories` from `20261003223000_checklist_library_marketplace.sql` | One active `category_id` per library template; cannot express true multi-sector classification directly |
| Library template + items | `checklist_library_templates`, `checklist_library_template_items` | Version, translations, tags, plan, purchase product, optional form theme; content item fields for seven languages |
| Marketplace installs | `organization_library_installs`, `organization_library_purchases` | Separates library original from organization-owned install; purchase verification server-side via Edge Function |
| Organization editable templates | `checklist_templates`, `checklist_template_items` | Installed library content is copied into an editable org draft; source IDs and versions retained |
| Revision history | `checklist_library_revisions` from `20261004102000_checklist_library_revision_history.sql` | Versioned JSON snapshots of template and complete item text |
| Global seed migrations | `20261003224000_seed_checklist_library.sql`, `20261004110000_expand_checklist_library_v2.sql` | Expansion SQL contains 18 category slugs, 79 unique template slugs, 7 declared item languages; these are **source counts only** |
| Publication gate | `20261004101500_checklist_library_quality_gate.sql` | Requires >=12 distinct active items and nonempty seven-language strings; does **not** establish translation accuracy, safety, legal validity, or professional review |
| Current API | `ChecklistLibraryRepository`: `list_checklist_library` RPC, `install_checklist_library_template` RPC, Google Play purchase Edge Function | Maintain response contracts for deployed clients |
| Admin catalogue | `apps/checklist_admin/lib/screens/checklist_library_pane.dart` | Search by name, description, tags and category; filter by single category, entitlement type, installed; owner organization switching |
| Entry / Viewer | `checklist_scope_filters.dart`, `checklist_categories.dart`, A4 and offline shared modules | Different location/assignment category taxonomy: nine hard-coded checklist categories, seven authorized organizational facets; do not silently relabel or merge |
| Billing | `LibraryPurchaseService`, `verify-google-play-library-purchase` | Library purchase flow references Google Play/Android; any web/iOS global purchase rollout requires separate commercial/platform review |

## 2. Critical findings and disposition
### SEC-P0-001 — HIGH — Revision history entitlement gap (BLOCKER)
**Evidence:** `supabase/migrations/20261004102000_checklist_library_revision_history.sql` (around lines 14–21). Authenticated users have SELECT grant and RLS permits `is_platform_owner() OR is_approved_active_user()`, independent of purchased-template entitlement, whereas current library item RLS checks `can_access_library_template`. Snapshots include `items_snapshot` JSON containing all historical item bodies.

**Impact if deployed as written:** A logged-in approved user may be able to read archived premium item content they are not entitled to. Do not broaden archive access when introducing a global library.

**P1 prerequisite:** First verify actual deployed policy read-only; then prepare/review a separate least-privilege SQL migration ensuring revision SELECT is restricted to owner or only entitled organization context, and test with at least two orgs (entitled / non-entitled) plus revoked purchase and expired user cases. Choose a per-organization RPC for revision history if generic RLS lacks correct organization context. Never rely only on UI hiding. Requires explicit approval before production migration.

### TAX-P0-002 — MEDIUM — Two incompatible category dimensions
The library `category_id` represents a facility/sector category (18 expansion slugs), while assigned checklist categories use a fixed nine-value `ChecklistCategories.ids` with `normalize(unknown) => general`. These represent different concepts and must coexist. Treating `category_id` or the nine slugs as globally canonical would lose industry/discipline/document-kind separation.

**Resolution:** Add new multi-dimensional mappings, preserve existing category IDs, checklistCategory slugs and legacy rendering. Never migrate them by string substitution.

### COM-P0-003 — MEDIUM — Monetization is platform-specific
Current library purchase flow is Google Play oriented; `google_play_product_id` is part of premium template schema. Country payment support, Apple IAP rules and web checkout are not proven by this source audit. **Resolution:** retain existing purchase checks while P1 focuses on taxonomy; do a separate platform billing compliance review before global premium sales.

### CNT-P0-004 — MEDIUM — Professional content validation is not the publication SQL gate
A generated 79-template/seven-language SQL seed is **not equivalent** to expert verification of risk, translation, legal requirements or applicability in all countries. Require edition/country/reviewer evidence and publication status before labeling a template certified/compliant. Existing published seed state in production not checked.

### LOC-P0-005 — MEDIUM — Physical hierarchy remains fixed
The existing `Organization → Site → Building → Floor → Area → Checklist` is appropriate for FM and should stay. Other sectors may need equipment, fleet, production line, vehicle, department or non-building work scopes. **Resolution:** P1 adds taxonomy to templates without altering location hierarchies; design optional location/entity extensions later, with mapped backward-compatible view and no fake physical building requirements.

### OPS-P0-006 — Operational provenance
The Mac working tree had ~169 pre-existing changes upon audit start on branch `feat/play-billing-storage`. None were reset, overwritten or committed. All P0 outputs are new files. Production Supabase policies, seed row counts, payment provider configuration and real authenticated user journeys **remain unverified** and are mandatory before release.

## 3. Non-destructive tests actually executed
- `flutter test --no-pub test/p0_global_library_legacy_contract_test.dart test/checklist_categories_test.dart test/checklist_scope_filters_test.dart test/location_filter_scope_test.dart` under `packages/checklist_shared`: **16 passed**. Includes **five new fixtures** for legacy categories, catalog JSON/7 languages/pricing/update state, distinct maintenance/cleaning rooms, and cross-organization selection scope.
- `flutter test --no-pub test/phase2_filter_and_a4_test.dart test/checklist_washroom_hierarchy_test.dart test/offline_sync_checkpoint_test.dart test/photo_pair_test.dart test/policy_enforcement_test.dart`: **19 passed**. Existing paper, hierarchy, offline and evidence regression.
- `python3 scripts/audits/p0_global_library_audit.py --json`: scanned checked-in SQL and repository, reported 18 categories / 79 unique templates / seven declared languages; flagged **SEC-P0-001**. Source audit only.
- `python3 -m py_compile scripts/audits/p0_global_library_audit.py`: pass.
- P0 does not change existing models, migrations, application business logic, clients, schema, network or deployment. No unverified security claims should be made.

## 4. What P0 did NOT validate
- Live Supabase migration parity or RLS runtime with real user tokens.
- Live seed publication/counts across environments.
- Google Play/App Store/website payment entitlement parity.
- Full device matrix, international time-zone formats, RTL content quality, certification/regulatory status.
- No security migration was applied; SEC-P0-001 is an identified potential vulnerability requiring confirmation and correction before P1 release.

## 5. P0 decision
**P0 documentation, inventory, read-only security examination and local regression baselines: COMPLETE.**

**P1 work may be developed in isolation but must not be marked RELEASE READY until:** SEC-P0-001 resolved and live policies verified; existing API/RLS contracts preserved; migration plan/test fixtures reviewed; owner explicitly approves production rollout. Refer to `docs/GLOBAL_LIBRARY_P1_ARCHITECTURE_AND_GATES.md` for the backwards-compatible design and acceptance criteria.
