# GLOB-001 / P0 — Global Library 2.0 Architecture, Migration Plan and Phase-1 Backlog
**Status:** Proposed engineering contract from completed P0 source audit · **Target:** maximum global applicability by phased implementation · **No production change in this document**

## 1. Canonical classification contract
A global library template must be filterable on **independent, many-to-many dimensions**:
- **Industry / Sector:** e.g. Facilities, Hospitality, Food and Beverage, Manufacturing, Education, Healthcare Operations, Retail, Logistics, Construction, Energy, Agriculture, Transportation, Government.
- **Work Domain / Discipline:** e.g. Cleaning, Irrigation, HVAC, Electrical, Fire/Life Safety, Waste, Food Hygiene, Quality, Audit, Inventory, Equipment Maintenance. Reuse a domain across multiple sectors.
- **Document / Workflow Kind:** Checklist, Inspection, Audit as initial executable types; PPM, SOP, RA, MS, PTW, JSA, ITP, COP, NCR/CAR, Asset Register, Completion Report as future distinct engines, **not** cast into a binary yes/no checklist.
- **Asset / Location:** existing organization/location hierarchy, plus future optional asset/entity graph. Do not change facility binding during P1.
- **Schedule/Frequency:** one-time/daily/weekly/monthly/etc metadata; a true recurrence execution engine begins P2, not P1.
- **Jurisdiction / Standard:** ISO country/region, standard identifier + edition and reviewer notes; applicability must be explicit; unknown means **not reviewed**, never globally certified.
- **Language/Locale:** BCP 47 locale identifiers; preserve existing seven content languages en/ar/bn/hi/ml/tl/ta. Add editorial fallbacks and translated catalog metadata incrementally.
- **Tenant / Access:** global published catalog separate from organization-owned copies and actual executed records, protected by role, subscription and entitlements.

## 2. Proposed minimum additive schema for P1 (not yet executed)
**New read-model additions, names provisional:**
1. `library_taxonomy_terms` — id UUID, immutable slug, dimension enum (industry/domain/subdomain), optional parent_id, translations JSONB, status/sort_order. Add constraints for parent dimension and cycles; no external translation API dependency.
2. `library_template_taxonomy` — template_id FK, term_id FK, unique composite, global owner-curated tags; supports many-to-many across sectors and disciplines.
3. `library_document_kinds` — stable `kind_code` (default `checklist`), localization, execution_engine_code; **P1** only existing executable checklist, others may be catalog-only/unpublished until dedicated engine.
4. `library_template_classification` — unique template_id FK, document_kind FK, optional sector-neutral service tags and maturity/validation state; can later hold recurrence-frequency hint without scheduling work.
5. `library_template_jurisdiction` — optional template/jurisdiction/standard/edition/reviewer/status mapping. Separate country-specific overlays are P4, not P1; no unsupported claims.
6. Optional `library_template_locales` — catalog-name/description translations by locale. Existing item columns and `languages[]` remain authoritative for current clients until versioned migration.

**Existing entities MUST remain unchanged and functional:** `checklist_library_categories`, `checklist_library_templates.category_id`, `facility_tags`, `checklist_templates`, `checklist_template_items`, `organization_library_installs`, `organization_library_purchases`, `checklist_library_revisions`, `list_checklist_library(uuid)`, `install_checklist_library_template(uuid,uuid)`, org/location permissions, legacy `checklistCategory` and A4 forms.

**Read API contract:** Keep current `list_checklist_library(uuid)` shape for deployed mobile/web builds. Introduce versioned additive `list_global_library_v2(...)` (or equivalent view/RPC) returning industries/domains/kind/locales/jurisdiction; use server-side permission filters and pagination. Do not break existing response deserialization.

**Write contract:** Global taxonomy changes are owner/admin controlled. Organization-owned templates retain copies and their version lineage. Never attach paid historical content to a query that unauthorised clients can select; isolate revisions through entitled scoped RPC/RLS.

## 3. Non-destructive staged migration approach
A. **Preflight**: inventory current deployed migrations and RLS policies read-only, backup and check active templates/org installs/revisions/entitlements; repair SEC-P0-001 separately before expanding catalog access.
B. **Expand**: add independent taxonomy tables and policies; no deletes, renames, type changes, or modification to current `category_id` semantics.
C. **Backfill**: deterministic mapping for 18 existing library slugs to one/many industry/domain terms; preserve original slug and category_id. Every current template receives `document_kind=checklist`; keep original seven-language item payload unchanged.
D. **Dual-read compatibility**: old clients continue old RPC; new clients use v2 endpoint (or compatible optional data) with fallback. Version/tags must not silently drift.
E. **UI enablement**: CheckAdmin library filters support sector/domain/document type and category, scoped search, permission-aware choices; CheckIn installs/use flows and CheckView read/A4 behavior remain compatible. No new "PPM" engine hidden behind a checklist.
F. **Validate**: run SQL/RLS/tenant/billing checks with fixtures on staging and Flutter unit/widget/integration tests across 3 apps/WEB. Preview assets, compare counts by template slug, version and org before/after.
G. **Controlled rollout**: flags / phased rollout, monitoring, immutable backup, rollback for new taxonomy UI/RPC without rolling back customer records; only after owner release approval.

## 4. Phase 1 prioritized implementation backlog
| ID | Priority | Deliverable | Estimate (engineering hours) | Gate |
|---|---|---|---:|---|
| P1-00 | P0 blocker | Verify & correct revision archive RLS, test multi-org entitlement and purchase revocation | 8–18 | Security gate before publishing |
| P1-01 | P1 | Taxonomy contract, normalized tables, migrations, validation constraints, reversible deploy procedures | 12–25 | Additive only; deterministic IDs |
| P1-02 | P1 | Backfill exact 79 existing template slugs into sector + domain + kind, mapping review | 8–18 | Zero orphan/loss/duplicate identities |
| P1-03 | P1 | Versioned library read RPC with permission-aware filtering, pagination, indexes | 10–22 | No cross-org leak, old RPC exact |
| P1-04 | P1 | Admin filter/search/tags UX in Arabic/English, mobile widths | 12–25 | 320dp + desktop + RTL |
| P1-05 | P1 | Viewer/Entry/install cross-app compatibility + existing offline/A4 behavior | 8–18 | Existing workflows intact |
| P1-06 | P1 | Integration tests, accessibility, performance, rollout scripts, live parity preflight | 12–25 | Independent QA & owner review |
| **Total** | | **Range, not quote** | **70–151 h** | External professional review additional |

**Estimates:** for reuse of existing Flutter/Supabase code, not all vertical-specific content or complex schedules. Larger scope/rate/cross-platform payment redesign makes it higher. On a focused single-engineer delivery, allow roughly 3–7 calendar weeks plus review; tool availability and code conflicts can vary.

## 5. P1 measurable acceptance criteria
- **Catalogue**: every existing template ID/slug, language payload, current `category_id`, version and org install retained; source expansion fixture totals 18 categories and 79 unique templates; changes in live counts reconciled, not overwritten.
- **Taxonomy**: a single template can have two sectors, two domains and one document kind without duplication; new sector names are localized; legacy `general` stays available.
- **Security**: platform owner can curate; Org A cannot read/install Org B's private templates; non-entitled users cannot fetch active or archived premium item bodies; revoked purchases lose entitlement; expired/suspended users denied; API/RLS tested with real-role fixtures.
- **Versioning**: installation always produces an org-owned draft and links back to source version; updating original does not rewrite signed/completed inspections.
- **Workflows**: A4 shape, printable report, photos, signatures, reviewer workflow, filters, offline CheckIn and automatic sync operate unchanged. Existing 320dp layouts remain usable.
- **Locale**: en/ar RTL/LTR flawless; existing seven item content fields remain accessible; unsupported locale uses explicitly documented fallback instead of empty text.
- **Performance**: library search paginated and index-backed; user with many templates does not require downloading full global library; test with >=10k catalog rows (synthetic, no actual claims).
- **Rollout**: staging backfill verified, forward-compatible client builds, fail-safe feature switch, no changed production billing until separate approval.
- **Security release gate**: P1-00 has a staging PASS and independently reviewed SQL; live parity checked before production deployment.

## 6. P2–P5 boundary to avoid disguised scope growth
- **P2**: linked assets, PPM recurrence, work-order states, readings, schedule execution, maintenance history and reviewed facility packs.
- **P3**: different schema/workflows for Method Statement, Risk Assessment (risk matrix), PTW/approvals, SOP, JSA, ITP, COP, NCR/CAR, audit trail, signer attestations.
- **P4**: medically/legally regulated sector packs, region/standard review, market localization and localization of billing.
- **P5**: multi-region/enterprise scale, dashboards, integration API and resilience compliance.

**Action after P0:** Approve P1 delivery only when ready; begin P1-00 as the first technical task. No source tree rewrite, no premature database migration, no direct production changes from P0.
