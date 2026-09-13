# Web portal deployment

The `Deploy web portal to GitHub Pages` workflow publishes only after the Quality
Gate passes on `main`. A manual run also checks that the selected commit passed.
Enable GitHub Pages with **GitHub Actions** as its source.

Configure repository secrets `SUPABASE_URL` and `SUPABASE_ANON_KEY`. These are the
public client settings; do not use a service-role key. Set `WEB_BASE_HREF` to `/`
for a custom root domain, or `/<repository-name>` for project Pages. Set
`PAGES_CNAME` when using a custom domain.

Set repository variable `NATIVE_RELEASE_TAG` (or the manual-run input) to the
GitHub Release containing the exact same version/build as all three pubspecs.
The release must contain these assets produced by the existing signing scripts:

- `checklist_entry.apk`, `checklist_viewer.apk`, `checklist_admin.apk`
- `InspectionEntry-macOS.zip`, `InspectionViewer-macOS.zip`, `InspectionAdmin-macOS.zip`

The workflow downloads these into `dist`, then uses `build_web_portal.sh` on a
macOS runner to check app versions, Android release signatures, Developer ID
signatures and macOS notarization. It requires all six verified downloads before
replacing Pages. Missing, outdated or unsigned native packages fail the build;
the previously published portal remains available. A web-only clean checkout can
therefore never silently erase the download page's existing files.

Before publishing, deploy the backend changes in `SUPABASE_SETUP.md`. Update all
three app versions and portal version/cache metadata together; the portal check
enforces their agreement. A successful source-code push is not proof that signed
native packages or a Pages deployment have been released.
