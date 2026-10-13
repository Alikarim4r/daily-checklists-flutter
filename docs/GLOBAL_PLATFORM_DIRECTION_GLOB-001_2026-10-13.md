# Daily Checklists — Approved Global Platform Direction
Decision: GLOB-001 | Approved: 2026-10-13 | Status: Product-direction baseline
Owner decision: Maximum global applicability, implemented through phased delivery.

## Binding decision
Daily Checklists is a globally applicable, multi-industry, multi-country, multi-language platform for inspections, operational records, scheduled work and governed technical documentation. Facilities Management remains an initial vertical pack, never an architectural limit.
Global-ready architecture from the outset; content and specialized execution engines are progressively enabled after quality gates. Do not confuse global readiness with claiming that every jurisdiction or professional field has been validated.

## Core principles
1. One shared platform, not separate codebases per sector; preserve CheckView, CheckIn and CheckAdmin.
2. Distinct dimensions: Industry/Sector; Domain/Discipline/Subdiscipline; Document/Workflow Type; Asset/Location; Frequency; Jurisdiction/Standard; Language; Organization-specific visibility.
3. Avoid hardcoded FM or country-only terminology in canonical schemas; render appropriate sector-specific labels in the UI.
4. Retain existing Organization → Site → Building → Floor → Area → Checklist flows for FM users. Future optional flexible structure nodes must be backward-compatible, and must never erase or silently reinterpret existing locations.
5. Templates are not executed records. Versioned, immutable library originals and organization-owned copies remain separate; historical records keep their original evidence/version.
6. Multi-tenancy, RLS, roles, offline-first CheckIn, synchronized records, bilingual RTL/LTR and original A4 checklist rendering must not regress.
7. All regulated/clinical/safety templates explicitly identify their jurisdiction, standard edition, reviewer and status. No automatic or unsupported compliance certification.
8. International readiness covers localization, dates/time zones, locale formats, currency, regional hosting requirements where relevant, accessibility and scalable plans; not all are day-one launches.
9. Avoid paid AI agents and paid dependencies unless owner approves; reusable internal building blocks first.
10. Do not change databases/APIs/production/publishing as a side effect of this decision record. Each implementation phase requires tests and a production approval gate.

## Proposed global taxonomy
Industry examples: Facilities Management; Hospitality; Food & Beverage; Retail; Healthcare Operations; Education; Manufacturing; Construction; Logistics/Warehousing; Energy & Utilities; Transportation; Agriculture/Landscaping; Government/Public Services; Property/Residential; Office Operations; Environmental Services.
Domains and tasks may be shared by several industries, e.g. Cleaning, HVAC, Irrigation, Fire Safety, Electrical, Quality, Equipment Maintenance, Inventory, Waste, Sanitation, Audits.
Document/operation types are independent: Checklist, Inspection, Audit, PPM Plan/Work Order, Method Statement, Risk Assessment, JSA, SOP, COP/Reference, PTW, ITP, NCR/CAR, Asset Register, Completion Report.
COP means Code of Practice here; confirm alternative meanings if encountered by clients.
A template can carry many sectors and tags but has one canonical versioned identity.

## Phased production program
### Phase 0 — Baseline audit and contract (do first)
- Inventory existing library schemas, tags, permission checks, filters, seed data, purchase/install/revision/versioning and export flows.
- Record migration-safe domain vocabulary and UI taxonomy; write fixture-backed tests for legacy FM behavior.
- Deliver: approved taxonomy, extension model, staged migration plan, regression checklist, no production changes.
- Gate: zero ambiguity about preserving existing customer records and compatibility.

### Phase 1 — Universal Library 2.0
- Flexible industry/domain/document-type taxonomy, multi-sector tags, localized names, advanced library search/filters, organization/private vs public/library templates.
- Preserve purchase/version/install history and role-limited filters.
- Deliver: functional multi-industry categorization using the existing Checklist engine; starter sectors may initially have no professional packs.
- Gate: templates from differing sectors can be created, found, installed and used across 3 apps and web without FM-only restrictions; current FM checks remain intact.

### Phase 2 — FM excellence + reusable PPM foundation
- Asset register, linking checklist tasks to physical assets and locations, scheduled recurrences, due/overdue, evidence and work history.
- Seed reviewed professional packs for FM, cleaning, landscaping/irrigation, HSE and utilities.
- Gate: full scheduled job lifecycle and reliable offline entry/reconciliation; no data/permission regression.

### Phase 3 — Governed technical documentation
- Method Statement, Risk Assessment, SOP, COP/reference, JSA, ITP, PTW, NCR/CAR and controlled versions as distinct schemas/workflows where needed (not forced into checklist yes/no answers).
- Draft/review/approve/publish/retire, revision controls, immutable signed evidence, linking to jobs/assets.
- Gate: role-based review, audit trails, accurate risk scoring and independent professional validation for relevant regulated content.

### Phase 4 — International sector packs and market localization
- Add sector packs based on evidence of demand: hospitality, food safety, manufacturing, warehouse/logistics, construction, education, healthcare operations, agriculture, transport and others.
- Country-specific overlays, language packs, localized legal disclaimers, billing/market capabilities and availability by region; validate standards before marketing any compliance claims.
- Gate: domain expert and regional review, translation quality, relevant QA & usability tests.

### Phase 5 — Enterprise global scaling
- Advanced reporting/analytics, import/integration APIs, large multi-org and multi-region controls, regulatory lifecycle monitoring, SLAs, observability, security/privacy governance and scale tests.
- Gate: production security, data isolation, operational resilience, accessibility and business sign-off.

## Explicitly NOT approved by this decision
- No immediate claim that all countries or industries are legally supported or certified.
- No automatic creation of tens of thousands of unreviewed templates.
- No new subscription prices, external fees, cloud spend, migrations, deploys, or store submissions without implementation authorization.
- No replacement of established A4 checklist logic or CheckIn/CheckAdmin workflows.

## First actionable development deliverable
Conduct Phase 0 audit and return (a) current-state architecture/inventory, (b) backwards-compatible taxonomy/schema proposal, (c) minimal Phase 1 implementation backlog, (d) measurable acceptance tests, (e) time/cost bands. This is the basis for phased implementation rather than a wholesale rewrite.
