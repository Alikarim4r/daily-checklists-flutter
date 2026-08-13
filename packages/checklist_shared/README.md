# checklist_shared

Private shared Flutter package for the Daily Checklists applications. It owns
the domain models, Supabase repositories, authorization/session helpers,
offline outbox, photo policy, reporting, theming, and common UI components used
by the Entry, Viewer, and Admin applications.

## Scope

- Typed checklist, organization, site, user, media, and operations models.
- Supabase-backed repositories using the secured inspection workflow RPCs.
- Encrypted offline inspection queue with idempotent synchronization.
- Biometric session locking without storing account passwords.
- Arabic/English reports, form themes, branding, and shared widgets.
- Photo-pair, carry-forward, overdue, and submission policy enforcement.

## Development

This package is workspace-private (`publish_to: none`). Run its checks from the
repository root with:

```bash
./scripts/check_quality.sh
```

Applications consume it through a local path dependency. Database changes that
affect repositories must remain compatible with the ordered migrations under
`supabase/migrations` and their integration smoke test.

## Security notes

Supabase owns the authenticated session. Raw account passwords must never be
stored locally. The secure-storage v10 dependency is intentionally held for one
production bridge release so installations upgrading from v9 can migrate their
encrypted data before a later upgrade to v11.

This package and its assets are proprietary and are not published to pub.dev.
