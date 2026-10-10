-- Preserve storage path validation, tenant authorization, private bucket
-- permissions and the approved-inspection write ban. A returned draft is
-- editable by save_checklist_inspection, so its photo upload must also be.
-- Production hotfix already applied; this migration is idempotent.
DO $migration$
DECLARE
  definition text;
  adjusted text;
BEGIN
  definition := pg_get_functiondef('public.can_write_checklist_media(text)'::regprocedure);
  IF definition LIKE '%inspection.review_status in (''draft'', ''returned'')%' THEN
    RETURN;
  END IF;
  IF definition NOT LIKE '%inspection.review_status = ''draft''%' THEN
    RAISE EXCEPTION 'Unexpected media-write guard; manual review required';
  END IF;
  adjusted := replace(definition,
    'inspection.review_status = ''draft''',
    'inspection.review_status in (''draft'', ''returned'')');
  EXECUTE adjusted;
END;
$migration$;
