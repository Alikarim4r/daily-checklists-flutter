# Daily Checklists P2 — Completion and Release Handoff

**Production implemented:** asset register, planned preventive maintenance, site hierarchy, linked A4 inspections, work order execution and immutable history, protected PPM APIs, multilingual CheckAdmin dashboard, and hourly autonomous PostgreSQL scheduling via pg_cron.

**Production cron:** `daily-checklists-ppm-hourly-v1` active, schedule `15 * * * *`, owned by `postgres`, calls `public.fm_ppm_scheduler_tick()`; privileged API not executable by ordinary users. Initial manual heartbeat passed. Each tick materializes up to 45 days ahead with bounded 3,000 jobs, IANA-local due dates and zero-duplicate unique constraints. No customer asset records were created during migration.

**Web:** CheckAdmin P2 `2bca278`, verified with exact live JavaScript checksum. CheckIn legacy-compatible PPM v1.3.11 deployed `1cd4172`, exact checksum verified. Final incremental CheckIn v1.3.12 with optional linked A4 evidence is built and published separately once QA passes. Original field dashboard layout retained; only PPM entry point, offline-sync worker and optional evidence input added. CheckView unchanged.

**Tests:** shared package 100 tests, Admin 12, CheckView 31, legacy-compatible CheckIn 11 (all pass at last run); isolated PostgreSQL PPM security, month-end schedule, tenant, assignment, idempotent retry and background scheduler tests pass. Production-role transaction tested with `ROLLBACK`; no synthetic customer data retained. Actual user authenticated GUI acceptance remains to be completed by a real account.

**Mobile blockers:** Android store AAB cannot be signed on the authorized Mac because `android/key.properties` and all `ANDROID_KEYSTORE_*` environment variables are unavailable. Do not create or use a replacement upload key; requires the existing CheckIn upload-key credentials or authorized Play App Signing key reset. App Store/iOS delivery likewise needs valid code signing and portal authorization. Source is staged on a dedicated feature branch, but mobile store publishing must not be reported as complete.

**Important content scope:** starter PPM recipes are clearly marked drafts pending professional review; Method Statements, Risk Assessments and PTW engines belong to P3, not this P2 release.
