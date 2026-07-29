# Daily Checklists Flutter

MOEHE Facility Daily Inspection — Flutter apps with a **dedicated** Supabase backend.

This project is independent from `smart-meters-platform`. Do not share that project's URL, keys, or migrations.

## Apps

| App | Path | Role |
|-----|------|------|
| Entry | `apps/checklist_entry` | Technician daily inspection (photos, signature, Y/N/NA) |
| Viewer | `apps/checklist_viewer` | View / edit / submit inspections |
| Admin | `apps/checklist_admin` | Search, correct, delete + Storage media |

Shared package: `packages/checklist_shared`

## Backend (dedicated)

- Supabase project: **daily-checklists** (`xhdpyiklhouqwrtdwztn`)
- Migrations: `supabase/migrations/001` … `005` (orgs, zones, sites, profiles, inspections, storage, MOEHE seed)
- Setup details: [`docs/SUPABASE_SETUP.md`](docs/SUPABASE_SETUP.md)

```bash
# already linked on this machine:
npx supabase link --project-ref xhdpyiklhouqwrtdwztn
npx supabase db push
```

Fill `.env.local` from `.env.example` with **this** project's URL + anon key only.

## Run

```bash
./scripts/run_staging_app.sh entry
./scripts/run_staging_app.sh viewer
./scripts/run_staging_app.sh admin
```

## Data

Buildings (B1–B7 + DC/Mech/BMS) and checklist lists (127 items, multi-language labels) are embedded in:

- `packages/checklist_shared/lib/src/data/buildings.dart`
- `packages/checklist_shared/lib/src/data/checklist_lists.dart`
- `packages/checklist_shared/lib/src/data/ui_labels.dart`

## Source

Ported from Daily Checklists RAR (`EntryV2`, `ViewerEdit`, `deletetool`).
