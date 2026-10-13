#!/usr/bin/env bash
# GLOB-001 P1: isolated, disposable PostgreSQL integration suite.
# No Supabase URL or secret is loaded; NEVER operates on production DB.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
for binary in initdb pg_ctl psql python3; do
  command -v "$binary" >/dev/null || { echo "Missing: $binary"; exit 2; }
done
TEMP="$(mktemp -d "${TMPDIR:-/private/tmp}/daily-checklists-p1-pg.XXXXXX")"
PORT="$(python3 - <<'PY'
import socket
s=socket.socket()
s.bind(('127.0.0.1',0))
print(s.getsockname()[1])
s.close()
PY
)"
started=0
cleanup() {
  if [ "$started" = 1 ]; then
    pg_ctl -D "$TEMP/db" stop -m immediate >/dev/null 2>&1 || true
  fi
  rm -rf "$TEMP"
}
trap cleanup EXIT INT TERM
initdb -D "$TEMP/db" --auth-local=trust --auth-host=trust -U postgres --no-instructions >"$TEMP/init.log" 2>&1
pg_ctl -D "$TEMP/db" -l "$TEMP/server.log" -o "-p $PORT -h 127.0.0.1 -k $TEMP -F" start >"$TEMP/start.log" 2>&1
started=1
run_sql() {
  psql -X -v ON_ERROR_STOP=1 -h 127.0.0.1 -p "$PORT" -U postgres -d postgres -f "$1"
}
run_sql "$ROOT/supabase/tests/p1_global_library_fixture.sql"
for migration in \
  20261013230000_global_library_revision_entitlement.sql \
  20261013231000_global_library_taxonomy.sql \
  20261013232000_global_library_v2_read_api.sql \
  20261013233000_global_library_owner_curation.sql; do
  echo "Apply (isolated): $migration"
  run_sql "$ROOT/supabase/migrations/$migration" >"$TEMP/migration.log"
done
echo "P1: authorization and entitlement scenarios"
run_sql "$ROOT/supabase/tests/p1_global_library_integration.sql" > "$TEMP/auth.log"
tail -5 "$TEMP/auth.log"
echo "P1: 10,000 synthetic catalog records"
run_sql "$ROOT/supabase/tests/p1_global_library_10k_load.sql" > "$TEMP/perf.log"
echo "P1: owner curation and audit"
run_sql "$ROOT/supabase/tests/p1_global_library_owner_curation.sql" > "$TEMP/curation.log"
tail -5 "$TEMP/curation.log"
echo "P1 POSTGRES ISOLATED INTEGRATION: PASS"
