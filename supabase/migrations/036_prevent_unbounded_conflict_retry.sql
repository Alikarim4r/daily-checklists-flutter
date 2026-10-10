-- A stale optimistic-concurrency version is a business conflict, not a
-- serialization failure. SQLSTATE 40001 can trigger automatic retry loops in
-- API consumers and exhaust the PostgREST connection pool (PGRST003 / 504).
-- Changing only the error code preserves all locks, validation, permissions,
-- write protections and data. No records are modified by this migration.
-- Idempotent: safe on a fresh schema or one already hotfixed in production.
DO $migration$
DECLARE
  routine record;
  definition text;
  revised text;
BEGIN
  FOR routine IN
    SELECT oid
    FROM pg_proc
    WHERE pronamespace = 'public'::regnamespace
      AND pg_get_functiondef(oid) LIKE '%errcode = ''40001''%'
  LOOP
    definition := pg_get_functiondef(routine.oid);
    IF definition NOT LIKE '%was changed by another session; reload and retry%' THEN
      RAISE EXCEPTION 'Unexpected true serialization-failure handling in %',
        routine.oid::regprocedure;
    END IF;
    revised := replace(definition,
      'errcode = ''40001''', 'errcode = ''P0001''');
    IF revised = definition THEN
      RAISE EXCEPTION 'Could not replace optimistic concurrency code in %',
        routine.oid::regprocedure;
    END IF;
    EXECUTE revised;
  END LOOP;
END;
$migration$;
