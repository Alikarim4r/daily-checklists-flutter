# Checklist photo persistence reliability (2026-10-10)

- Storage upload and media-evidence registration do not alone prove a photo was linked to a checklist item. The database contained 7 recent issue-photo evidence rows without a corresponding item link; no data was deleted.
- CheckView now serializes picture uploads/saves and checks the authoritative saved inspection after each attachment. A failed or unconfirmed link remains available in the open editor for a Save retry. Mobile Viewer's parent list refreshes after a confirmed save.
- Supabase's `can_write_checklist_media` RLS helper had disallowed `returned` review status, even though `save_checklist_inspection` permits editable drafts in both `draft` and `returned` states. Migration 037 aligns the rules without admitting new users, unvalidated paths, or approved inspections.
- Do not auto-relink historic unattached media without reviewing the actual inspection and user permissions. Existing media is retained pending safe recovery.
