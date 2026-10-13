#!/usr/bin/env bash
# Repeatable isolated PostgreSQL P2 integration: no production credentials.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
T="$(mktemp -d "${TMPDIR:-/private/tmp}/daily-checklists-p2-pg.XXXXXX")"
PORT="$(python3 - <<'PY'
import socket
s=socket.socket();s.bind(('127.0.0.1',0));print(s.getsockname()[1]);s.close()
PY
)"
started=0
cleanup(){ if [ "$started" = 1 ];then pg_ctl -D "$T/db" stop -m immediate >/dev/null 2>&1||true;fi;rm -rf "$T"; }
trap cleanup EXIT INT TERM
initdb -D "$T/db" --auth-local=trust --auth-host=trust -U postgres --no-instructions >"$T/init.log" 2>&1
pg_ctl -D "$T/db" -l "$T/pg.log" -o "-p $PORT -h 127.0.0.1 -k $T -F" start >"$T/start.log" 2>&1
started=1
run(){ psql -X -v ON_ERROR_STOP=1 -h 127.0.0.1 -p "$PORT" -U postgres -d postgres -f "$1"; }
run "$ROOT/supabase/tests/p1_global_library_fixture.sql" >/dev/null
run "$ROOT/supabase/tests/p2_ppm_fixture.sql" >/dev/null
for m in 20261014001000_ppm_assets_and_schedules.sql 20261014002000_ppm_execution_rpc.sql;do
 echo "Applying $m in disposable PostgreSQL"
 run "$ROOT/supabase/migrations/$m" >/dev/null
done
run "$ROOT/supabase/tests/p2_ppm_integration.sql"
echo 'P2 PPM ISOLATED INTEGRATION PASS'
