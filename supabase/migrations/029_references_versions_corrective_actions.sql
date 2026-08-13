-- =============================================================================
-- Stable references, checklist version lineage, media metadata and corrective
-- actions. All changes are additive and preserve existing inspection snapshots.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Checklist version lineage
-- -----------------------------------------------------------------------------
alter table public.checklist_templates
  add column if not exists family_code text,
  add column if not exists version_number int,
  add column if not exists lifecycle_status text,
  add column if not exists source_template_id uuid
    references public.checklist_templates (id) on delete restrict,
  add column if not exists published_at timestamptz,
  add column if not exists published_by uuid
    references public.profiles (id) on delete set null;

update public.checklist_templates
set family_code = coalesce(family_code, code),
    version_number = coalesce(version_number, 1),
    lifecycle_status = coalesce(lifecycle_status, 'published'),
    published_at = coalesce(published_at, created_at)
where family_code is null
   or version_number is null
   or lifecycle_status is null
   or published_at is null;

alter table public.checklist_templates
  alter column family_code set not null,
  alter column version_number set not null,
  alter column lifecycle_status set not null,
  alter column version_number set default 1,
  alter column lifecycle_status set default 'draft';

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'checklist_templates_version_positive'
  ) then
    alter table public.checklist_templates
      add constraint checklist_templates_version_positive
      check (version_number > 0);
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'checklist_templates_lifecycle_valid'
  ) then
    alter table public.checklist_templates
      add constraint checklist_templates_lifecycle_valid
      check (lifecycle_status in ('draft', 'published', 'retired'));
  end if;
end;
$$;

create unique index if not exists checklist_templates_family_version_uidx
  on public.checklist_templates (family_code, version_number);
create index if not exists checklist_templates_family_lifecycle_idx
  on public.checklist_templates (family_code, lifecycle_status, version_number desc);

create or replace function public.assign_checklist_template_lineage()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.family_code := coalesce(nullif(trim(new.family_code), ''), new.code);
  new.version_number := coalesce(new.version_number, 1);
  new.lifecycle_status := coalesce(nullif(trim(new.lifecycle_status), ''), 'draft');
  return new;
end;
$$;

drop trigger if exists checklist_templates_assign_lineage
  on public.checklist_templates;
create trigger checklist_templates_assign_lineage
  before insert on public.checklist_templates
  for each row execute function public.assign_checklist_template_lineage();

create or replace function public.guard_published_checklist_template()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if old.lifecycle_status <> 'draft' and (
    new.code is distinct from old.code
    or new.family_code is distinct from old.family_code
    or new.version_number is distinct from old.version_number
    or new.name_en is distinct from old.name_en
    or new.name_ar is distinct from old.name_ar
    or new.form_theme is distinct from old.form_theme
    or new.form_theme_accent is distinct from old.form_theme_accent
  ) then
    raise exception 'published checklist versions are immutable; create a new version';
  end if;
  return new;
end;
$$;

drop trigger if exists checklist_templates_guard_published
  on public.checklist_templates;
create trigger checklist_templates_guard_published
  before update on public.checklist_templates
  for each row execute function public.guard_published_checklist_template();

create or replace function public.guard_published_checklist_template_item()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_template_id uuid := case when tg_op = 'DELETE'
    then old.template_id else new.template_id end;
  v_status text;
begin
  select lifecycle_status into v_status
  from public.checklist_templates
  where id = v_template_id;
  if v_status is distinct from 'draft' then
    raise exception 'published checklist versions are immutable; create a new version';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

drop trigger if exists checklist_template_items_guard_published
  on public.checklist_template_items;
create trigger checklist_template_items_guard_published
  before insert or update or delete on public.checklist_template_items
  for each row execute function public.guard_published_checklist_template_item();

-- -----------------------------------------------------------------------------
-- Stable inspection identity and immutable template snapshot metadata
-- -----------------------------------------------------------------------------
create sequence if not exists public.checklist_inspection_reference_seq;

alter table public.checklist_inspections
  add column if not exists reference_no text,
  add column if not exists template_id uuid
    references public.checklist_templates (id) on delete restrict,
  add column if not exists template_code_snapshot text,
  add column if not exists template_version_snapshot int,
  add column if not exists template_name_en_snapshot text,
  add column if not exists template_name_ar_snapshot text;

create or replace function public.new_checklist_inspection_reference(
  p_inspection_date date
)
returns text
language sql
volatile
set search_path = public
as $$
  select 'INS-' || extract(year from p_inspection_date)::int::text || '-'
    || lpad(nextval('public.checklist_inspection_reference_seq')::text, 7, '0')
$$;

-- Migration backfill only: approved inspections are immutable in normal
-- operation, so temporarily suspend the mutation guard while adding the new
-- identity metadata to historical rows. The trigger is re-enabled immediately
-- after both backfills and the migration itself runs transactionally.
alter table public.checklist_inspections
  disable trigger checklist_inspections_guard_mutation;

update public.checklist_inspections inspection
set reference_no = public.new_checklist_inspection_reference(
  inspection.inspection_date
)
where inspection.reference_no is null;

update public.checklist_inspections inspection
set template_id = template.id,
    template_code_snapshot = template.family_code,
    template_version_snapshot = template.version_number,
    template_name_en_snapshot = template.name_en,
    template_name_ar_snapshot = template.name_ar
from public.sites site
join public.checklist_templates template
  on template.code = site.checklist_type
where inspection.site_id = site.id
  and inspection.template_id is null;

alter table public.checklist_inspections
  enable trigger checklist_inspections_guard_mutation;

create unique index if not exists checklist_inspections_reference_uidx
  on public.checklist_inspections (reference_no)
  where reference_no is not null;
create index if not exists checklist_inspections_template_idx
  on public.checklist_inspections (template_id);

create or replace function public.assign_checklist_inspection_identity()
returns trigger
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
declare
  v_template public.checklist_templates%rowtype;
begin
  if nullif(trim(new.reference_no), '') is null then
    new.reference_no := public.new_checklist_inspection_reference(
      new.inspection_date
    );
  end if;
  if new.template_id is null then
    select template.*
    into v_template
    from public.sites site
    join public.checklist_templates template
      on template.code = site.checklist_type
    where site.id = new.site_id
    order by template.version_number desc
    limit 1;
    if v_template.id is not null then
      new.template_id := v_template.id;
      new.template_code_snapshot := v_template.family_code;
      new.template_version_snapshot := v_template.version_number;
      new.template_name_en_snapshot := v_template.name_en;
      new.template_name_ar_snapshot := v_template.name_ar;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists checklist_inspections_assign_identity
  on public.checklist_inspections;
create trigger checklist_inspections_assign_identity
  before insert on public.checklist_inspections
  for each row execute function public.assign_checklist_inspection_identity();

create or replace function public.guard_checklist_inspection_identity()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.reference_no is distinct from old.reference_no
     or new.template_id is distinct from old.template_id
     or new.template_code_snapshot is distinct from old.template_code_snapshot
     or new.template_version_snapshot is distinct from old.template_version_snapshot
     or new.template_name_en_snapshot is distinct from old.template_name_en_snapshot
     or new.template_name_ar_snapshot is distinct from old.template_name_ar_snapshot then
    raise exception 'inspection reference and template snapshot are immutable';
  end if;
  return new;
end;
$$;

drop trigger if exists checklist_inspections_guard_identity
  on public.checklist_inspections;
create trigger checklist_inspections_guard_identity
  before update on public.checklist_inspections
  for each row execute function public.guard_checklist_inspection_identity();

-- Owner-managed version creation keeps the published version untouched until
-- an explicit publish operation switches the affected sites atomically.
create or replace function public.clone_checklist_template_version(
  p_source_template_id uuid,
  p_reason text default ''
)
returns uuid
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
declare
  v_source public.checklist_templates%rowtype;
  v_new_id uuid;
  v_version int;
  v_code text;
begin
  if not public.is_platform_owner() then
    raise exception 'only the platform owner can create checklist versions';
  end if;
  select * into v_source
  from public.checklist_templates
  where id = p_source_template_id
  for share;
  if v_source.id is null then raise exception 'checklist template not found'; end if;

  perform pg_advisory_xact_lock(hashtextextended(v_source.family_code, 0));
  select coalesce(max(version_number), 0) + 1 into v_version
  from public.checklist_templates
  where family_code = v_source.family_code;
  v_code := left(v_source.family_code, 48) || '_V' || v_version;

  perform set_config('app.audit_reason', nullif(trim(p_reason), ''), true);
  insert into public.checklist_templates (
    code, family_code, version_number, lifecycle_status, source_template_id,
    name_en, name_ar, is_active, form_theme, form_theme_accent
  ) values (
    v_code, v_source.family_code, v_version, 'draft', v_source.id,
    v_source.name_en, v_source.name_ar, false,
    v_source.form_theme, v_source.form_theme_accent
  ) returning id into v_new_id;

  insert into public.checklist_template_items (
    template_id, item_index, default_answer,
    description_en, description_ar, description_bn, description_hi,
    description_ml, description_tl, description_ta,
    sort_order, is_active, overdue_after_days
  )
  select
    v_new_id, item_index, default_answer,
    description_en, description_ar, description_bn, description_hi,
    description_ml, description_tl, description_ta,
    sort_order, is_active, overdue_after_days
  from public.checklist_template_items
  where template_id = v_source.id;
  return v_new_id;
end;
$$;

revoke all on function public.clone_checklist_template_version(uuid, text)
  from public;
grant execute on function public.clone_checklist_template_version(uuid, text)
  to authenticated;

create or replace function public.publish_checklist_template_version(
  p_template_id uuid,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
declare
  v_template public.checklist_templates%rowtype;
begin
  if not public.is_platform_owner() then
    raise exception 'only the platform owner can publish checklist versions';
  end if;
  if nullif(trim(p_reason), '') is null then
    raise exception 'a publication reason is required';
  end if;
  select * into v_template
  from public.checklist_templates
  where id = p_template_id
  for update;
  if v_template.id is null then raise exception 'checklist template not found'; end if;
  if v_template.lifecycle_status <> 'draft' then
    raise exception 'only a draft checklist version can be published';
  end if;
  if not exists (
    select 1 from public.checklist_template_items item
    where item.template_id = p_template_id and item.is_active
  ) then
    raise exception 'cannot publish an empty checklist version';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(v_template.family_code, 0));
  perform set_config('app.audit_reason', trim(p_reason), true);
  update public.checklist_templates
  set lifecycle_status = 'retired', is_active = false
  where family_code = v_template.family_code
    and lifecycle_status = 'published';
  update public.checklist_templates
  set lifecycle_status = 'published', is_active = true,
      published_at = now(), published_by = auth.uid()
  where id = p_template_id;
  update public.sites site
  set checklist_type = v_template.code
  where site.checklist_type in (
    select version.code from public.checklist_templates version
    where version.family_code = v_template.family_code
      and version.id <> p_template_id
  );
end;
$$;

revoke all on function public.publish_checklist_template_version(uuid, text)
  from public;
grant execute on function public.publish_checklist_template_version(uuid, text)
  to authenticated;

-- -----------------------------------------------------------------------------
-- Normalized evidence metadata (existing item columns remain compatible).
-- -----------------------------------------------------------------------------
create table if not exists public.checklist_media_evidence (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete restrict,
  site_id uuid not null references public.sites (id) on delete restrict,
  inspection_id uuid not null references public.checklist_inspections (id) on delete restrict,
  inspection_item_id uuid references public.checklist_inspection_items (id) on delete restrict,
  corrective_action_id uuid,
  storage_path text not null unique,
  media_kind text not null,
  reference_no text not null,
  uploaded_by uuid references public.profiles (id) on delete set null,
  uploaded_at timestamptz not null default now(),
  deactivated_at timestamptz,
  deactivated_by uuid references public.profiles (id) on delete set null,
  constraint checklist_media_kind_valid check (
    media_kind in ('signature', 'issue_photo', 'fix_photo', 'action_photo', 'action_document')
  )
);

alter table public.checklist_media_evidence enable row level security;
create index if not exists checklist_media_inspection_idx
  on public.checklist_media_evidence (inspection_id, inspection_item_id);
create index if not exists checklist_media_site_idx
  on public.checklist_media_evidence (site_id, uploaded_at desc);

drop policy if exists checklist_media_evidence_select
  on public.checklist_media_evidence;
create policy checklist_media_evidence_select
  on public.checklist_media_evidence for select to authenticated
  using (public.has_site_access(site_id));

revoke all on public.checklist_media_evidence from anon, authenticated;
grant select on public.checklist_media_evidence to authenticated;

insert into public.checklist_media_evidence (
  organization_id, site_id, inspection_id, storage_path,
  media_kind, reference_no, uploaded_by, uploaded_at
)
select site.organization_id, inspection.site_id, inspection.id,
       inspection.signature_path, 'signature', 'SIG',
       inspection.inspector_user_id, inspection.created_at
from public.checklist_inspections inspection
join public.sites site on site.id = inspection.site_id
where nullif(trim(inspection.signature_path), '') is not null
on conflict (storage_path) do nothing;

insert into public.checklist_media_evidence (
  organization_id, site_id, inspection_id, inspection_item_id, storage_path,
  media_kind, reference_no, uploaded_by, uploaded_at
)
select site.organization_id, inspection.site_id, inspection.id, item.id,
       item.image_path, 'issue_photo', item.item_index::text || '.1',
       inspection.inspector_user_id, item.created_at
from public.checklist_inspection_items item
join public.checklist_inspections inspection on inspection.id = item.inspection_id
join public.sites site on site.id = inspection.site_id
where nullif(trim(item.image_path), '') is not null
on conflict (storage_path) do nothing;

create or replace function public.register_checklist_media_evidence(
  p_inspection_id uuid,
  p_item_id uuid,
  p_storage_path text,
  p_media_kind text
)
returns text
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
declare
  v_site_id uuid;
  v_org_id uuid;
  v_item_index int;
  v_reference text;
  v_count int;
begin
  select inspection.site_id, site.organization_id
  into v_site_id, v_org_id
  from public.checklist_inspections inspection
  join public.sites site on site.id = inspection.site_id
  where inspection.id = p_inspection_id;
  if v_site_id is null then raise exception 'inspection not found'; end if;
  if not public.can_write_site(v_site_id) then
    raise exception 'not allowed to register evidence for this inspection';
  end if;
  if public.storage_path_inspection_id(p_storage_path) is distinct from p_inspection_id then
    raise exception 'evidence storage path does not match inspection';
  end if;
  if not exists (
    select 1 from storage.objects object
    where object.bucket_id = 'checklist-media'
      and object.name = trim(p_storage_path)
  ) then
    raise exception 'evidence object was not found in private storage';
  end if;
  if p_media_kind not in ('signature', 'issue_photo', 'fix_photo') then
    raise exception 'invalid inspection media kind';
  end if;
  if p_item_id is not null then
    select item.item_index into v_item_index
    from public.checklist_inspection_items item
    where item.id = p_item_id and item.inspection_id = p_inspection_id;
    if v_item_index is null then raise exception 'inspection item not found'; end if;
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    p_inspection_id::text || ':' || coalesce(p_item_id::text, 'signature'), 0
  ));
  if p_media_kind = 'signature' then
    v_reference := 'SIG';
  else
    select count(*) + 1 into v_count
    from public.checklist_media_evidence evidence
    where evidence.inspection_id = p_inspection_id
      and evidence.inspection_item_id = p_item_id
      and evidence.media_kind in ('issue_photo', 'fix_photo');
    v_reference := v_item_index::text || '.' || v_count::text;
  end if;
  insert into public.checklist_media_evidence (
    organization_id, site_id, inspection_id, inspection_item_id,
    storage_path, media_kind, reference_no, uploaded_by
  ) values (
    v_org_id, v_site_id, p_inspection_id, p_item_id,
    trim(p_storage_path), p_media_kind, v_reference, auth.uid()
  )
  on conflict (storage_path) do update set
    deactivated_at = null, deactivated_by = null
  returning reference_no into v_reference;
  return v_reference;
end;
$$;

revoke all on function public.register_checklist_media_evidence(
  uuid, uuid, text, text
) from public;
grant execute on function public.register_checklist_media_evidence(
  uuid, uuid, text, text
) to authenticated;

-- -----------------------------------------------------------------------------
-- Corrective actions
-- -----------------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_type where typname = 'corrective_action_priority') then
    create type public.corrective_action_priority as enum ('low', 'medium', 'high', 'critical');
  end if;
  if not exists (select 1 from pg_type where typname = 'corrective_action_status') then
    create type public.corrective_action_status as enum (
      'open', 'in_progress', 'pending_verification', 'closed', 'canceled'
    );
  end if;
end;
$$;

create sequence if not exists public.corrective_action_reference_seq;

create table if not exists public.checklist_corrective_actions (
  id uuid primary key default gen_random_uuid(),
  reference_no text not null unique default (
    'CA-' || extract(year from current_date)::int::text || '-'
    || lpad(nextval('public.corrective_action_reference_seq')::text, 7, '0')
  ),
  organization_id uuid not null references public.organizations (id) on delete restrict,
  site_id uuid not null references public.sites (id) on delete restrict,
  inspection_id uuid not null references public.checklist_inspections (id) on delete restrict,
  inspection_item_id uuid not null references public.checklist_inspection_items (id) on delete restrict,
  description text not null,
  assigned_user_id uuid references public.profiles (id) on delete set null,
  priority public.corrective_action_priority not null default 'medium',
  status public.corrective_action_status not null default 'open',
  due_date date not null,
  evidence_required boolean not null default true,
  closure_comment text,
  created_by uuid not null references public.profiles (id) on delete restrict,
  closed_by uuid references public.profiles (id) on delete set null,
  closed_at timestamptz,
  version bigint not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'checklist_media_corrective_action_fk'
  ) then
    alter table public.checklist_media_evidence
      add constraint checklist_media_corrective_action_fk
      foreign key (corrective_action_id)
      references public.checklist_corrective_actions (id) on delete restrict;
  end if;
end;
$$;

create table if not exists public.checklist_corrective_action_comments (
  id uuid primary key default gen_random_uuid(),
  corrective_action_id uuid not null
    references public.checklist_corrective_actions (id) on delete restrict,
  comment text not null,
  created_by uuid not null references public.profiles (id) on delete restrict,
  created_at timestamptz not null default now()
);

create index if not exists checklist_corrective_actions_scope_idx
  on public.checklist_corrective_actions (site_id, status, due_date);
create index if not exists checklist_corrective_actions_assignee_idx
  on public.checklist_corrective_actions (assigned_user_id, status, due_date);
create index if not exists checklist_corrective_actions_inspection_idx
  on public.checklist_corrective_actions (inspection_id, inspection_item_id);
create index if not exists checklist_corrective_comments_action_idx
  on public.checklist_corrective_action_comments (corrective_action_id, created_at);

create trigger checklist_corrective_actions_set_updated_at
  before update on public.checklist_corrective_actions
  for each row execute function public.set_checklist_updated_at();

alter table public.checklist_corrective_actions enable row level security;
alter table public.checklist_corrective_action_comments enable row level security;

drop policy if exists checklist_corrective_actions_select
  on public.checklist_corrective_actions;
create policy checklist_corrective_actions_select
  on public.checklist_corrective_actions for select to authenticated
  using (public.has_site_access(site_id));

drop policy if exists checklist_corrective_comments_select
  on public.checklist_corrective_action_comments;
create policy checklist_corrective_comments_select
  on public.checklist_corrective_action_comments for select to authenticated
  using (
    exists (
      select 1 from public.checklist_corrective_actions action
      where action.id = corrective_action_id
        and public.has_site_access(action.site_id)
    )
  );

revoke all on public.checklist_corrective_actions from anon, authenticated;
revoke all on public.checklist_corrective_action_comments from anon, authenticated;
grant select on public.checklist_corrective_actions to authenticated;
grant select on public.checklist_corrective_action_comments to authenticated;

create or replace function public.create_corrective_action(
  p_inspection_item_id uuid,
  p_description text,
  p_assigned_user_id uuid,
  p_priority public.corrective_action_priority,
  p_due_date date,
  p_evidence_required boolean default true
)
returns uuid
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
declare
  v_action_id uuid;
  v_inspection_id uuid;
  v_site_id uuid;
  v_org_id uuid;
  v_response public.checklist_response;
  v_default text;
begin
  select item.inspection_id, inspection.site_id, site.organization_id,
         item.response, item.default_answer
  into v_inspection_id, v_site_id, v_org_id, v_response, v_default
  from public.checklist_inspection_items item
  join public.checklist_inspections inspection on inspection.id = item.inspection_id
  join public.sites site on site.id = inspection.site_id
  where item.id = p_inspection_item_id;
  if v_site_id is null then raise exception 'inspection item not found'; end if;
  if not public.can_write_site(v_site_id) then
    raise exception 'not allowed to create a corrective action for this site';
  end if;
  if nullif(trim(p_description), '') is null then
    raise exception 'corrective action description is required';
  end if;
  if p_due_date < public.current_business_date() then
    raise exception 'corrective action due date cannot be in the past';
  end if;
  if v_response is null or (
    (upper(v_default) = 'Y' and v_response = 'yes')
    or (upper(v_default) = 'N' and v_response = 'no')
    or (upper(v_default) = 'NA' and v_response = 'na')
  ) then
    raise exception 'corrective actions can only be linked to a failed item';
  end if;
  if p_assigned_user_id is not null and not exists (
    select 1 from public.user_site_access access_row
    where access_row.user_id = p_assigned_user_id
      and access_row.site_id = v_site_id
      and access_row.can_read
  ) then
    raise exception 'assigned user does not have access to this site';
  end if;

  insert into public.checklist_corrective_actions (
    organization_id, site_id, inspection_id, inspection_item_id,
    description, assigned_user_id, priority, due_date,
    evidence_required, created_by
  ) values (
    v_org_id, v_site_id, v_inspection_id, p_inspection_item_id,
    trim(p_description), p_assigned_user_id, coalesce(p_priority, 'medium'),
    p_due_date, coalesce(p_evidence_required, true), auth.uid()
  ) returning id into v_action_id;
  return v_action_id;
end;
$$;

revoke all on function public.create_corrective_action(
  uuid, text, uuid, public.corrective_action_priority, date, boolean
) from public;
grant execute on function public.create_corrective_action(
  uuid, text, uuid, public.corrective_action_priority, date, boolean
) to authenticated;

create or replace function public.transition_corrective_action(
  p_action_id uuid,
  p_expected_version bigint,
  p_transition text,
  p_comment text
)
returns bigint
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
declare
  v_action public.checklist_corrective_actions%rowtype;
  v_next public.corrective_action_status;
  v_version bigint;
  v_can_manage boolean;
begin
  select * into v_action
  from public.checklist_corrective_actions
  where id = p_action_id
  for update;
  if v_action.id is null then raise exception 'corrective action not found'; end if;
  if v_action.version is distinct from p_expected_version then
    raise exception using errcode = '40001',
      message = 'corrective action was changed by another session; reload and retry';
  end if;
  if not public.has_site_access(v_action.site_id) then
    raise exception 'not allowed to access this corrective action';
  end if;
  if v_action.status in ('closed', 'canceled') then
    raise exception 'closed corrective actions are immutable';
  end if;
  v_can_manage := public.can_manage_site(v_action.site_id);
  if not v_can_manage and v_action.assigned_user_id is distinct from auth.uid() then
    raise exception 'only the assignee or a site manager can update this action';
  end if;
  if nullif(trim(p_comment), '') is null then
    raise exception 'a transition comment is required';
  end if;

  v_next := case trim(lower(p_transition))
    when 'start' then 'in_progress'::public.corrective_action_status
    when 'request_close' then 'pending_verification'::public.corrective_action_status
    when 'close' then 'closed'::public.corrective_action_status
    when 'cancel' then 'canceled'::public.corrective_action_status
    else null
  end;
  if v_next is null then raise exception 'invalid corrective action transition'; end if;
  if v_next in ('closed', 'canceled') and not v_can_manage then
    raise exception 'only a site manager can close or cancel an action';
  end if;
  if v_next in ('pending_verification', 'closed')
     and (v_action.evidence_required or v_action.priority = 'critical')
     and not exists (
       select 1 from public.checklist_media_evidence evidence
       where evidence.corrective_action_id = v_action.id
         and evidence.deactivated_at is null
     ) then
    raise exception 'evidence is required before closing this corrective action';
  end if;

  perform set_config('app.audit_reason', trim(p_comment), true);
  update public.checklist_corrective_actions
  set status = v_next,
      closure_comment = case when v_next in ('closed', 'canceled')
        then trim(p_comment) else closure_comment end,
      closed_at = case when v_next = 'closed' then now() else closed_at end,
      closed_by = case when v_next = 'closed' then auth.uid() else closed_by end,
      version = version + 1
  where id = p_action_id
  returning version into v_version;
  insert into public.checklist_corrective_action_comments (
    corrective_action_id, comment, created_by
  ) values (p_action_id, trim(p_comment), auth.uid());
  return v_version;
end;
$$;

revoke all on function public.transition_corrective_action(
  uuid, bigint, text, text
) from public;
grant execute on function public.transition_corrective_action(
  uuid, bigint, text, text
) to authenticated;

create or replace function public.register_corrective_action_evidence(
  p_action_id uuid,
  p_storage_path text,
  p_media_kind text
)
returns text
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
declare
  v_action public.checklist_corrective_actions%rowtype;
  v_reference text;
  v_count int;
begin
  select * into v_action
  from public.checklist_corrective_actions
  where id = p_action_id;
  if v_action.id is null then raise exception 'corrective action not found'; end if;
  if not public.can_write_site(v_action.site_id)
     and v_action.assigned_user_id is distinct from auth.uid() then
    raise exception 'not allowed to add evidence to this corrective action';
  end if;
  if v_action.status in ('closed', 'canceled') then
    raise exception 'closed corrective actions are immutable';
  end if;
  if p_media_kind not in ('action_photo', 'action_document') then
    raise exception 'invalid corrective action media kind';
  end if;
  if public.storage_path_inspection_id(p_storage_path)
     is distinct from v_action.inspection_id then
    raise exception 'evidence storage path does not match inspection';
  end if;
  if not exists (
    select 1 from storage.objects object
    where object.bucket_id = 'checklist-media'
      and object.name = trim(p_storage_path)
  ) then
    raise exception 'evidence object was not found in private storage';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_action_id::text, 0));
  select count(*) + 1 into v_count
  from public.checklist_media_evidence
  where corrective_action_id = p_action_id;
  v_reference := v_action.reference_no || '.' || v_count::text;
  insert into public.checklist_media_evidence (
    organization_id, site_id, inspection_id, inspection_item_id,
    corrective_action_id, storage_path, media_kind, reference_no, uploaded_by
  ) values (
    v_action.organization_id, v_action.site_id, v_action.inspection_id,
    v_action.inspection_item_id, v_action.id, trim(p_storage_path),
    p_media_kind, v_reference, auth.uid()
  ) returning reference_no into v_reference;
  return v_reference;
end;
$$;

revoke all on function public.register_corrective_action_evidence(
  uuid, text, text
) from public;
grant execute on function public.register_corrective_action_evidence(
  uuid, text, text
) to authenticated;

-- Audit and assignment notifications.
create or replace function public.audit_corrective_action_change()
returns trigger
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
begin
  perform public.append_checklist_audit(
    'corrective_action.' || lower(tg_op),
    'corrective_action',
    coalesce(new.id, old.id)::text,
    coalesce(new.site_id, old.site_id),
    coalesce(new.organization_id, old.organization_id),
    case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) else null end,
    case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) else null end,
    nullif(current_setting('app.audit_reason', true), '')
  );
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

drop trigger if exists checklist_corrective_actions_audit
  on public.checklist_corrective_actions;
create trigger checklist_corrective_actions_audit
  after insert or update or delete on public.checklist_corrective_actions
  for each row execute function public.audit_corrective_action_change();

create or replace function public.notify_corrective_action_assignment()
returns trigger
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
begin
  if new.assigned_user_id is not null and (
    tg_op = 'INSERT' or new.assigned_user_id is distinct from old.assigned_user_id
  ) then
    insert into public.checklist_notifications (
      user_id, inspection_id, site_id, kind,
      title_en, title_ar, body_en, body_ar
    ) values (
      new.assigned_user_id, new.inspection_id, new.site_id,
      'corrective_action_assigned',
      'Corrective action assigned', 'تم إسناد إجراء تصحيحي',
      new.reference_no || ' — ' || new.description,
      new.reference_no || ' — ' || new.description
    );
  end if;
  return new;
end;
$$;

drop trigger if exists checklist_corrective_actions_notify
  on public.checklist_corrective_actions;
create trigger checklist_corrective_actions_notify
  after insert or update of assigned_user_id
  on public.checklist_corrective_actions
  for each row execute function public.notify_corrective_action_assignment();
