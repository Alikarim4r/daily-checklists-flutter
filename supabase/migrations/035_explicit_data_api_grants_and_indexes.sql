-- =============================================================================
-- Explicit Data API privileges and foreign-key index coverage
-- Migration: 035_explicit_data_api_grants_and_indexes.sql
-- =============================================================================
--
-- Supabase projects can be configured so new public tables are not granted to
-- anon/authenticated automatically. Keep Data API exposure deterministic and
-- independent from project-level default privileges. RLS remains the authority
-- for row scope; these grants only expose the operations used by the clients.

revoke all privileges on all tables in schema public
  from public, anon, authenticated;
revoke all privileges on all sequences in schema public
  from public, anon, authenticated;

-- Read models used by Entry, Viewer and Admin. Two internal ledgers are
-- intentionally absent: platform_owners and checklist_media_cleanup_requests.
grant select on table
  public.organizations,
  public.zones,
  public.sites,
  public.profiles,
  public.user_site_access,
  public.checklist_inspections,
  public.checklist_inspection_items,
  public.checklist_corrections,
  public.checklist_templates,
  public.checklist_template_items,
  public.site_checklist_items,
  public.checklist_org_policies,
  public.checklist_audit_log,
  public.checklist_notifications,
  public.checklist_media_evidence,
  public.checklist_corrective_actions,
  public.checklist_corrective_action_comments,
  public.client_error_logs
to authenticated;

-- Catalog/hierarchy writes are still constrained by their organization/site
-- RLS policies and immutable-version triggers.
grant insert, update, delete on table
  public.organizations,
  public.zones,
  public.sites,
  public.user_site_access,
  public.checklist_templates,
  public.checklist_template_items,
  public.site_checklist_items,
  public.checklist_org_policies
to authenticated;

-- Self-service and notification writes are deliberately column-scoped.
grant update (full_name) on table public.profiles to authenticated;
grant update (read_at) on table public.checklist_notifications
  to authenticated;

-- Client error reports are insert-only for ordinary users. The SELECT grant
-- above is filtered by the owner-only RLS policy.
grant insert on table public.client_error_logs to authenticated;
grant usage, select on sequence public.client_error_logs_id_seq
  to authenticated;

-- Trusted backend jobs retain full access. This is not granted to browser or
-- mobile roles, and RLS/bypass behavior is controlled by Supabase itself.
grant all privileges on all tables in schema public to service_role;
grant all privileges on all sequences in schema public to service_role;

-- User creation has moved to the trusted Auth Admin API path. Keep the legacy
-- function for migration compatibility, but make it unreachable from clients.
revoke execute on function public.admin_create_user(text, text, text)
  from public, anon, authenticated;

-- Foreign-key indexes prevent parent updates/deletes and common scoped joins
-- from degrading into full-table scans as production history grows.
create index if not exists sites_organization_id_idx
  on public.sites (organization_id);
create index if not exists sites_zone_id_idx
  on public.sites (zone_id);
create index if not exists profiles_approved_by_idx
  on public.profiles (approved_by);
create index if not exists user_site_access_site_id_idx
  on public.user_site_access (site_id, user_id);

create index if not exists checklist_inspections_inspector_user_id_idx
  on public.checklist_inspections (inspector_user_id);
create index if not exists checklist_inspections_submitted_by_idx
  on public.checklist_inspections (submitted_by);
create index if not exists checklist_inspections_approved_by_idx
  on public.checklist_inspections (approved_by);
create index if not exists checklist_inspections_reinspection_authorized_by_idx
  on public.checklist_inspections (reinspection_authorized_by);

create index if not exists checklist_corrections_inspection_id_idx
  on public.checklist_corrections (inspection_id, created_at desc);
create index if not exists checklist_corrections_item_id_idx
  on public.checklist_corrections (item_id);
create index if not exists checklist_corrections_corrected_by_idx
  on public.checklist_corrections (corrected_by);

create index if not exists checklist_templates_source_template_id_idx
  on public.checklist_templates (source_template_id);
create index if not exists checklist_templates_published_by_idx
  on public.checklist_templates (published_by);

create index if not exists checklist_media_evidence_organization_id_idx
  on public.checklist_media_evidence (organization_id);
create index if not exists checklist_media_evidence_inspection_item_id_idx
  on public.checklist_media_evidence (inspection_item_id);
create index if not exists checklist_media_evidence_corrective_action_id_idx
  on public.checklist_media_evidence (corrective_action_id);
create index if not exists checklist_media_evidence_uploaded_by_idx
  on public.checklist_media_evidence (uploaded_by);
create index if not exists checklist_media_evidence_deactivated_by_idx
  on public.checklist_media_evidence (deactivated_by);

create index if not exists checklist_corrective_actions_organization_id_idx
  on public.checklist_corrective_actions (organization_id);
create index if not exists checklist_corrective_actions_inspection_item_id_idx
  on public.checklist_corrective_actions (inspection_item_id);
create index if not exists checklist_corrective_actions_created_by_idx
  on public.checklist_corrective_actions (created_by);
create index if not exists checklist_corrective_actions_closed_by_idx
  on public.checklist_corrective_actions (closed_by);
create index if not exists checklist_corrective_action_comments_created_by_idx
  on public.checklist_corrective_action_comments (created_by);
create index if not exists client_error_logs_user_id_idx
  on public.client_error_logs (user_id, occurred_at desc);
