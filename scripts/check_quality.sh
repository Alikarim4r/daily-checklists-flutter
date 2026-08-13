#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECTS=(
  packages/checklist_shared
  apps/checklist_entry
  apps/checklist_viewer
  apps/checklist_admin
)

cd "$ROOT"
dart format --output=none --set-exit-if-changed \
  apps/checklist_entry/lib \
  apps/checklist_entry/test \
  apps/checklist_viewer/lib \
  apps/checklist_viewer/test \
  apps/checklist_admin/lib \
  apps/checklist_admin/test \
  packages/checklist_shared/lib \
  packages/checklist_shared/test

for project in "${PROJECTS[@]}"; do
  echo "=== $project: dependencies ==="
  (cd "$ROOT/$project" && flutter pub get)
  echo "=== $project: analyzer ==="
  (cd "$ROOT/$project" && flutter analyze --no-pub)
  echo "=== $project: tests ==="
  (cd "$ROOT/$project" && flutter test --no-pub)
done

"${CHECKLIST_SQL_PYTHON:-python3}" "$ROOT/scripts/check_sql_migrations.py"
"$ROOT/scripts/test_migrations_postgres.sh"
python3 "$ROOT/scripts/check_web_portal.py"
if command -v node >/dev/null 2>&1; then
  node --check "$ROOT/web_portal/portal.js"
else
  echo "Skipping portal JavaScript syntax check: node is unavailable."
fi
