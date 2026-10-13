#!/usr/bin/env python3
"""Read-only P0 baseline audit. No cloud/API/DB calls, migrations, or writes."""
from __future__ import annotations

import argparse
import json
import re
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def run() -> dict:
    expansion = read("supabase/migrations/20261004110000_expand_checklist_library_v2.sql")
    core = read("supabase/migrations/20261003223000_checklist_library_marketplace.sql")
    revisions = read("supabase/migrations/20261004102000_checklist_library_revision_history.sql")
    quality = read("supabase/migrations/20261004101500_checklist_library_quality_gate.sql")
    library_repo = read("packages/checklist_shared/lib/src/repositories/checklist_library_repository.dart")
    admin_ui = read("apps/checklist_admin/lib/screens/checklist_library_pane.dart")
    site_categories = read("packages/checklist_shared/lib/src/utils/checklist_categories.dart")

    category_part = expansion.split("insert into public.checklist_library_templates", 1)[0]
    categories = re.findall(r"\('([a-z][a-z0-9_]*)','[^'\n]*','[^'\n]*','[^'\n]*',\d+\)", category_part)
    templates = re.findall(
        r"\(\(select id from public\.checklist_library_categories where slug='([^']+)'\),'([^']+)'",
        expansion,
    )
    revisions_policy = re.search(
        r"create policy checklist_library_revisions_read\b(.*?);", revisions, re.I | re.S
    )
    read_rule = revisions_policy.group(1) if revisions_policy else ""
    premium_history_is_exposed = (
        "public.is_approved_active_user()" in read_rule
        and "can_access_library_template" not in read_rule
        and "organization_id" not in read_rule
        and bool(re.search(r"grant select on public\.checklist_library_revisions to authenticated", revisions, re.I))
    )

    observations = {
        "source_scope_only": True,
        "seed_category_count": len(categories),
        "seed_categories": categories,
        "seed_template_count": len(templates),
        "unique_template_slug_count": len({s for _, s in templates}),
        "template_category_distribution": dict(sorted(Counter(c for c, _ in templates).items())),
        "declared_content_languages": ["en", "ar", "bn", "hi", "ml", "tl", "ta"],
        "library_uses_current_single_category_id": "category_id uuid not null" in core,
        "legacy_library_tags_named_facility_tags": "facility_tags text[]" in core,
        "library_listing_is_rpc": "'list_checklist_library'" in library_repo,
        "library_install_is_rpc": "'install_checklist_library_template'" in library_repo,
        "library_models_store_purchase_product_id": "google_play_product_id" in core,
        "catalog_entitlement_guard_exists": "can_access_library_template" in core,
        "library_install_server_authorization_exists": "is_org_super_admin" in core,
        "catalog_quality_gate_requires_7_languages": "cardinality(new.languages) <> 7" in quality,
        "admin_library_filters_currently_single_category": "template.categorySlug != category" in admin_ui,
        "legacy_checklist_category_has_finite_slugs": "static const ids = [" in site_categories,
        "revision_snapshots_contain_item_bodies": "items_snapshot jsonb not null" in revisions,
        "premium_revision_entitlement_gap_in_repository_policy": premium_history_is_exposed,
    }

    blockers = []
    if premium_history_is_exposed:
        blockers.append({
            "id": "SEC-P0-001",
            "severity": "high",
            "summary": "Authenticated approved users appear able to read revision item snapshots without checking template entitlement.",
            "evidence": "supabase/migrations/20261004102000_checklist_library_revision_history.sql lines 14-21",
            "required_before_phase1_release": True,
            "qualification": "Static migration finding; actual deployed DB policy has not been verified.",
        })
    if len(categories) != 18 or len(templates) != 79 or len(templates) != len({s for _, s in templates}):
        blockers.append({
            "id": "DATA-P0-002",
            "severity": "medium",
            "summary": "The checked-in V2 content seed differs from the expected 18-category / 79-template unique baseline.",
            "required_before_phase1_release": True,
        })
    return {
        "decision": "GLOB-001",
        "phase": "P0",
        "inspection": "static-source-only",
        "counts": {
            "categories": observations["seed_category_count"],
            "templates": observations["seed_template_count"],
            "languages": len(observations["declared_content_languages"]),
        },
        "observations": observations,
        "blockers": blockers,
        "phase1_release_ready": not blockers,
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json", action="store_true", help="Print machine-readable audit.")
    args = parser.parse_args()
    result = run()
    if args.json:
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        print(f"GLOB-001 P0 | static catalog: {result['counts']}")
        print(f"Phase 1 release ready: {result['phase1_release_ready']}")
        for item in result["blockers"]:
            print(f"BLOCKER {item['id']} ({item['severity']}): {item['summary']}")
        if not result["blockers"]:
            print("No source-level release blockers found (live verification remains necessary).")
    # A valid audit completes successfully even if it discovers release blockers.
