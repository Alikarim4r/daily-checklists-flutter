# PostgREST connection pool exhaustion — October 10, 2026

## Symptom

CheckView would not open for authenticated users. API returned `504 PGRST003`:
`Timed out acquiring connection from connection pool` even on the `/profiles`
request, so the web-page hosting was not the root cause.

## Evidence

Supabase PostgreSQL logged millions of repeated errors
`inspection was changed by another session; reload and retry` from the
`save_checklist_inspection` RPC, with SQLSTATE `40001`.
In this case, `40001` had been issued for a **stale application version**, not
for an actual serialization failure. This can result in unwanted automatic
retries, prolonged connection occupancy, and failures to read profiles.

## Recovery

The production database's save RPC conflict code changed from `40001` to
`P0001`, while keeping its message, permissions, and optimistic-concurrency
check. All 12 other application functions with the same stale-version guard
were fixed the same way. No inspection rows or form data were modified.
Afterward an unauthenticated REST read with the public key received HTTP 200
in 0.46s for organizations and 0.26s for profiles (previously timed out).
PostgREST backend sessions then settled to 2 and aborted transactions to 0.

## Prevention

- Never raise `40001` for stale edit versions. Reserve it for genuine
  transaction serialization failures.
- A client receiving a stale-version error must fetch the latest record and
  ask the user to reconcile; it must not retry the same version automatically.
- Alert on large rates of SQLSTATE 40001, HTTP 504/PGRST003, and growth in
  PostgREST pool wait times.
- Keep user-facing retry errors short and preserve unsynced local work.
