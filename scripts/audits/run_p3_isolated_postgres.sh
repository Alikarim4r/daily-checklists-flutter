#!/usr/bin/env bash
# GLOB-001 P3 isolated disposable PG16 integration, never production.
set -euo pipefail
R="$(cd "$(dirname "$0")/../.." && pwd)"
T="$(mktemp -d "${TMPDIR:-/private/tmp}/checklists-p3-pg.XXXXXX")"
PORT="$(python3 - <<'PY'
import socket
s=socket.socket();s.bind(('127.0.0.1',0));print(s.getsockname()[1]);s.close()
PY
)"
started=0
cleanup(){ if [ "$started" = 1 ];then pg_ctl -D "$T/data" stop -m immediate >/dev/null 2>&1||true;fi;rm -rf "$T"; }
trap cleanup EXIT INT TERM
initdb -D "$T/data" --auth-local=trust --auth-host=trust -U postgres --no-instructions >"$T/init.log" 2>&1
pg_ctl -D "$T/data" -l "$T/pg.log" -o "-p $PORT -h 127.0.0.1 -k $T -F" start >"$T/start.log" 2>&1
started=1
run(){ psql -X -v ON_ERROR_STOP=1 -h 127.0.0.1 -p "$PORT" -U postgres -d postgres -f "$1"; }
run "$R/supabase/tests/p1_global_library_fixture.sql" >/dev/null
run "$R/supabase/tests/p2_ppm_fixture.sql" >/dev/null
for f in \
  20261013231000_global_library_taxonomy.sql \
  20261014001000_ppm_assets_and_schedules.sql \
  20261014002000_ppm_execution_rpc.sql \
  20261014010000_p3a_document_core.sql \
  20261014011000_p3b_document_workflows.sql \
  20261014012000_p3c_permit_itp_ncr.sql
do
 echo "Apply isolated $f"
 run "$R/supabase/migrations/$f" >"$T/migration.log" || { cat "$T/migration.log"; exit 1; }
done
run "$R/supabase/tests/p3_global_documents_integration.sql"
echo 'P3 A+B+C ISOLATED PASS'
