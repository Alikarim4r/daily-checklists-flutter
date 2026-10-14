# Unified Daily Checklists Filters — October 14, 2026

## Scope and product requirements
- CheckAdmin tabs remain intact; CheckIn and store releases are not modified.
- Both CheckAdmin and CheckView web clients share organization/site/building/floor/area and service-sector/service-class/department/coverage/document-kind filters.
- Soft Services has Cleaning and Hospitality departments; Hard Services starts with one General department. Departments each contain General (whole building), Washrooms, Kitchens, Pantries, Offices, Corridors, Prayer Halls, Plant Rooms and other extensible area kinds.
- Admin can manage scoped classification terms and assign taxonomy to checklists; referenced options cannot be deleted. Existing A4 checklist engineering remains unchanged.
- Users only see filters from checklist assignments in their authorized service and location scope. Legacy hidden site state is cleared on filter reset.
- CheckView departure animation TickerMode moved inside transition so it cannot freeze disappearing tab opacity.

## Security and database
- `20261014130000_unified_checklist_filters.sql` creates additive tenant-scoped term and assignment-facet tables, validation triggers, scoped readers, and guarded manager mutations.
- Server seeded 255 classification terms and linked all 29 existing checklist assignments; site and inspection counts unchanged. No synthetic customer rows inserted.
- For categories without explicit area kind, fallback to General; unambiguous washroom/prayer-hall types are mapped.
- Anonymous callers cannot execute the scoped reader and regular authenticated callers cannot directly read raw taxonomy tables.

## Tests and deployments
- PostgreSQL isolated fixture PASS.
- Flutter shared 106 tests, CheckAdmin 17, CheckIn 16, CheckView 32 = **171** tests PASS with no analyzer errors across all four packages.
- Web Release 1.5.4+28 for CheckAdmin and CheckView generated successfully; CheckIn remains unchanged.
- GitHub Pages commit, build status and live JS exact comparison are recorded in the deployment terminal log, not assumed from source creation alone.

## Unresolved independent work
- Interactive logged-in UAT with organization manager and restricted viewer required.
- P3 HSE review / PTW validation findings from Claude audit have NOT been fixed in this filter release.
- No mobile-store publishing was performed.
