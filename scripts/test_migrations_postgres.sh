#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if ! command -v pg_config >/dev/null 2>&1; then
  if [[ "${CHECKLIST_REQUIRE_POSTGRES:-0}" == "1" ]]; then
    echo "pg_config is required for the migration integration test." >&2
    exit 1
  fi
  echo "Skipping PostgreSQL integration test: pg_config is unavailable."
  exit 0
fi

PG_BINDIR="${CHECKLIST_PG_BINDIR:-$(pg_config --bindir)}"
for binary in initdb pg_ctl psql; do
  if [[ ! -x "$PG_BINDIR/$binary" ]]; then
    if [[ "${CHECKLIST_REQUIRE_POSTGRES:-0}" == "1" ]]; then
      echo "$PG_BINDIR/$binary is required." >&2
      exit 1
    fi
    echo "Skipping PostgreSQL integration test: $binary is unavailable."
    exit 0
  fi
done

CHECKLIST_PG_TMP="$(mktemp -d "${TMPDIR:-/tmp}/daily-checklists-pg.XXXXXX")"
CHECKLIST_PG_PORT="${CHECKLIST_PG_PORT:-$((55000 + RANDOM % 5000))}"
cleanup() {
  "$PG_BINDIR/pg_ctl" -D "$CHECKLIST_PG_TMP/data" -m fast stop \
    >/dev/null 2>&1 || true
  if [[ -n "$CHECKLIST_PG_TMP" && -d "$CHECKLIST_PG_TMP" ]]; then
    rm -rf -- "$CHECKLIST_PG_TMP"
  fi
}
trap cleanup EXIT

"$PG_BINDIR/initdb" -D "$CHECKLIST_PG_TMP/data" -A trust --no-locale \
  >/dev/null
"$PG_BINDIR/pg_ctl" -D "$CHECKLIST_PG_TMP/data" \
  -l "$CHECKLIST_PG_TMP/postgres.log" \
  -o "-k $CHECKLIST_PG_TMP -p $CHECKLIST_PG_PORT" start >/dev/null

PSQL=(
  "$PG_BINDIR/psql"
  -X
  -v ON_ERROR_STOP=1
  -h "$CHECKLIST_PG_TMP"
  -p "$CHECKLIST_PG_PORT"
  postgres
)
"${PSQL[@]}" -f "$ROOT/supabase/tests/bootstrap.sql" >/dev/null
for migration in "$ROOT"/supabase/migrations/*.sql; do
  if [[ "$(basename "$migration")" == "024_refresh_unanswered_awqaf_drafts.sql" ]]; then
    "${PSQL[@]}" -f \
      "$ROOT/supabase/tests/pre_024_stale_awqaf_drafts.sql" >/dev/null
  fi
  if [[ "$(basename "$migration")" == "025_professional_moehe_b7_mech.sql" ]]; then
    "${PSQL[@]}" -f \
      "$ROOT/supabase/tests/pre_025_stale_b7_mech_drafts.sql" >/dev/null
  fi
  if [[ "$(basename "$migration")" == "026_repair_b7_m_site_binding.sql" ]]; then
    "${PSQL[@]}" -f \
      "$ROOT/supabase/tests/pre_026_wrong_b7_m_binding.sql" >/dev/null
  fi
  echo "Applying $(basename "$migration")"
  "${PSQL[@]}" -f "$migration" >/dev/null
done
"${PSQL[@]}" -f "$ROOT/supabase/tests/workflow_smoke.sql" >/dev/null
echo "PostgreSQL migration integration test passed."
