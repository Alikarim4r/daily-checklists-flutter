#!/usr/bin/env python3
"""Parse every migration and enforce critical security/workflow invariants."""

from pathlib import Path
import re
import sys

try:
    from pglast import parse_sql
except ImportError as error:
    raise SystemExit("Install pglast==8.4 before running SQL checks") from error


ROOT = Path(__file__).resolve().parents[1]
MIGRATIONS = ROOT / "supabase" / "migrations"
paths = sorted(MIGRATIONS.glob("*.sql"))
errors: list[str] = []

numbers = [int(path.name.split("_", 1)[0]) for path in paths]
expected = list(range(1, max(numbers, default=0) + 1))
if numbers != expected:
    errors.append(f"Migration sequence is not contiguous: {numbers}")

for path in paths:
    try:
        parse_sql(path.read_text(encoding="utf-8"))
    except Exception as error:  # pglast exposes parser-specific subclasses.
        errors.append(f"{path.name}: {error}")

hardening = (MIGRATIONS / "019_security_hardening.sql").read_text(encoding="utf-8")
workflow = (MIGRATIONS / "020_inspection_workflow_integrity.sql").read_text(
    encoding="utf-8"
)
operations = (MIGRATIONS / "021_ops_dashboard_batch_reads.sql").read_text(
    encoding="utf-8"
)
themes = (MIGRATIONS / "022_hierarchical_form_themes.sql").read_text(
    encoding="utf-8"
)
awqaf = (MIGRATIONS / "023_professional_awqaf_checklists.sql").read_text(
    encoding="utf-8"
)
draft_refresh = (
    MIGRATIONS / "024_refresh_unanswered_awqaf_drafts.sql"
).read_text(encoding="utf-8")
b7_mech = (MIGRATIONS / "025_professional_moehe_b7_mech.sql").read_text(
    encoding="utf-8"
)
b7_binding = (MIGRATIONS / "026_repair_b7_m_site_binding.sql").read_text(
    encoding="utf-8"
)
immutable_cleanup = (
    MIGRATIONS / "033_immutable_storage_and_safe_cleanup.sql"
).read_text(encoding="utf-8")

required_hardening = (
    "create table if not exists public.platform_owners",
    "create or replace function public.is_platform_owner()",
    "grant update (full_name) on table public.profiles to authenticated",
    "drop policy if exists profiles_update_own on public.profiles",
)
for fragment in required_hardening:
    if fragment not in hardening.lower():
        errors.append(f"019 is missing security invariant: {fragment}")

required_workflow = (
    "create or replace function public.create_checklist_inspection_draft",
    "create or replace function public.save_checklist_inspection",
    "create or replace function public.submit_checklist_inspection",
    "create or replace function public.admin_approve_inspection",
    "create or replace function public.correct_checklist_inspection_item",
    "revoke insert, update, delete on table public.checklist_inspections",
    "revoke insert, update, delete on table public.checklist_inspection_items",
)
for fragment in required_workflow:
    if fragment not in workflow.lower():
        errors.append(f"020 is missing workflow invariant: {fragment}")

correction_assignment = re.compile(
    r"into\s+v_inspection_id,\s+v_site_id,\s+v_review_status,\s+"
    r"v_version,\s+v_old_value\s+from\s+public\.checklist_inspection_items",
    re.IGNORECASE,
)
if correction_assignment.search(workflow) is None:
    errors.append("020 correction RPC has an invalid SELECT INTO assignment")

required_operations = (
    "create or replace function public.can_read_checklist_media",
    "create or replace function public.can_write_checklist_media",
    "create or replace function public.can_delete_checklist_media",
    "and public.can_read_checklist_media(name)",
    "and public.can_write_checklist_media(name)",
    "approved.review_status = 'approved'",
    "create or replace function public.list_latest_checklist_inspections",
    "create or replace function public.list_checklist_inspection_history",
    "review_status = 'approved'",
)
for fragment in required_operations:
    if fragment not in operations.lower():
        errors.append(f"021 is missing operations invariant: {fragment}")

required_themes = (
    "alter table public.organizations",
    "alter table public.zones",
    "alter table public.checklist_templates",
    "create or replace function public.resolve_checklist_form_themes",
    "public.is_org_super_admin(site.organization_id)",
    "public.has_site_access(site.id)",
)
for fragment in required_themes:
    if fragment not in themes.lower():
        errors.append(f"022 is missing hierarchical theme invariant: {fragment}")

required_awqaf = (
    "add column if not exists description_tl",
    "add column if not exists description_ta",
    "create or replace function public.populate_checklist_item_translations",
    "checklist_items_populate_translations",
    "awqaf_men_prayer",
    "awqaf_wudu",
    "awqaf_imam_house",
    "historical inspection snapshots remain unchanged",
)
for fragment in required_awqaf:
    if fragment not in awqaf.lower():
        errors.append(f"023 is missing Awqaf catalog invariant: {fragment}")

required_draft_refresh = (
    "inspection.review_status = 'draft'",
    "nullif(trim(inspection.signature_path), '') is null",
    "item.response is not null",
    "delete from public.checklist_inspection_items",
    "set version = inspection.version + 1",
)
for fragment in required_draft_refresh:
    if fragment not in draft_refresh.lower():
        errors.append(f"024 is missing safe draft-refresh invariant: {fragment}")

required_b7_mech = (
    "canonical moehe building 7 plant-room checklist",
    "template.code = 'b7_mech'",
    "item.response is not null",
    "nullif(trim(inspection.signature_path), '') is null",
    "delete from public.checklist_inspection_items",
    "set version = inspection.version + 1",
)
for fragment in required_b7_mech:
    if fragment not in b7_mech.lower():
        errors.append(f"025 is missing B7-M safety invariant: {fragment}")

required_b7_binding = (
    "upper(trim(site.building_code)) = 'b7-m'",
    "set checklist_type = 'b7_mech'",
    "inspection.review_status = 'draft'",
    "nullif(trim(inspection.signature_path), '') is null",
    "item.response is not null",
    "delete from public.checklist_inspection_items",
    "set version = inspection.version + 1",
)
for fragment in required_b7_binding:
    if fragment not in b7_binding.lower():
        errors.append(f"026 is missing B7-M binding invariant: {fragment}")

required_immutable_cleanup = (
    "drop policy if exists checklist_media_update on storage.objects",
    "create table if not exists public.checklist_media_cleanup_requests",
    "create or replace function public.delete_checklist_inspection_with_cleanup",
    "create or replace function public.complete_checklist_media_cleanup",
    "create or replace function public.list_my_pending_checklist_media_cleanup",
    "inspection.review_status <> 'approved'",
    "public.can_write_checklist_media(path)",
    "foreign key (inspection_id)",
    "on delete cascade",
)
for fragment in required_immutable_cleanup:
    if fragment not in immutable_cleanup.lower():
        errors.append(f"033 is missing immutable cleanup invariant: {fragment}")

if re.search(
    r"signingConfig\s*=\s*signingConfigs\.getByName\([\"']debug[\"']\)",
    "\n".join(
        path.read_text(encoding="utf-8")
        for path in ROOT.glob("apps/*/android/app/build.gradle.kts")
    ),
):
    errors.append("An Android release build still uses the debug signing key")

for app in ("checklist_entry", "checklist_viewer", "checklist_admin"):
    android = ROOT / "apps" / app / "android"
    for relative in (
        Path("gradlew"),
        Path("gradlew.bat"),
        Path("gradle/wrapper/gradle-wrapper.jar"),
        Path("gradle/wrapper/gradle-wrapper.properties"),
    ):
        if not (android / relative).is_file():
            errors.append(f"{app} is missing Android wrapper file: {relative}")
    manifest = (android / "app/src/main/AndroidManifest.xml").read_text(
        encoding="utf-8"
    )
    if 'android:allowBackup="false"' not in manifest:
        errors.append(f"{app} still permits Android application backup")
    if 'android:fullBackupContent="false"' not in manifest:
        errors.append(f"{app} still permits Android full backup content")

if errors:
    print("Migration/security checks failed:", file=sys.stderr)
    for error in errors:
        print(f"- {error}", file=sys.stderr)
    raise SystemExit(1)

print(f"Parsed {len(paths)} migrations; security invariants are present.")
