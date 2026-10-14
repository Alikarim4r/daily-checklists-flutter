-- GLOB-001 P3-A: technical document/version/approval core. Additive only.
create table if not exists public.technical_documents (
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete restrict,
 site_id uuid references public.sites(id) on delete restrict,
 asset_id uuid references public.fm_assets(id) on delete restrict,
 ppm_job_id uuid references public.fm_ppm_jobs(id) on delete restrict,
 document_code text not null check(length(btrim(document_code)) between 1 and 64),
 document_kind text not null references public.library_document_kinds(kind_code),
 title text not null check(length(btrim(title)) between 1 and 250),
 jurisdiction_country text check(jurisdiction_country is null or jurisdiction_country ~ '^[A-Z]{2}$'),
 standard_reference text,
 standard_edition text,
 language_code text not null default 'en',
 reviewer_note text,
 status text not null default 'draft'
  check(status in ('draft','in_review','approved','rejected','superseded')),
 current_version integer not null default 0 check(current_version>=0),
 approved_version integer,
 created_by uuid not null references public.profiles(id) on delete restrict default auth.uid(),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(organization_id,document_code),
 check(approved_version is null or (approved_version>0 and approved_version<=current_version))
);
create index if not exists technical_documents_org_kind_status
 on public.technical_documents(organization_id,document_kind,status,updated_at desc);
create index if not exists technical_documents_site_idx
 on public.technical_documents(site_id,updated_at desc);
create index if not exists technical_documents_asset_idx
 on public.technical_documents(asset_id,updated_at desc);
create index if not exists technical_documents_ppm_idx
 on public.technical_documents(ppm_job_id,updated_at desc);

create table if not exists public.technical_document_versions (
 document_id uuid not null references public.technical_documents(id) on delete restrict,
 version_no integer not null check(version_no>0),
 payload jsonb not null check(jsonb_typeof(payload)='object'),
 change_note text not null default '',
 author_id uuid not null references public.profiles(id) on delete restrict,
 created_at timestamptz not null default now(),
 primary key(document_id,version_no)
);

create table if not exists public.technical_document_decisions (
 id uuid primary key default gen_random_uuid(),
 document_id uuid not null references public.technical_documents(id) on delete restrict,
 version_no integer not null,
 decision text not null check(decision in ('submitted','approved','rejected','returned','superseded')),
 actor_id uuid not null references public.profiles(id) on delete restrict,
 remarks text,
 created_at timestamptz not null default now(),
 foreign key(document_id,version_no)
  references public.technical_document_versions(document_id,version_no) on delete restrict
);
create index if not exists technical_decisions_doc_created
 on public.technical_document_decisions(document_id,created_at desc);

create table if not exists public.technical_document_links (
 source_id uuid not null references public.technical_documents(id) on delete restrict,
 target_id uuid not null references public.technical_documents(id) on delete restrict,
 relationship text not null check(relationship in ('supports','risk_assessment','related','supersedes')),
 created_by uuid not null references public.profiles(id) on delete restrict,
 created_at timestamptz not null default now(),
 primary key(source_id,target_id,relationship),
 check(source_id<>target_id)
);

-- Guard all links to existing locations; prevent accidental cross-org joins.
create or replace function public.technical_verify_scope(
 p_org uuid,p_site uuid,p_asset uuid,p_job uuid)
returns boolean language plpgsql stable security definer
set search_path=public,pg_temp as $$
declare a public.fm_assets%rowtype; j public.fm_ppm_jobs%rowtype;
begin
 if p_site is not null and not exists(
   select 1 from public.sites s where s.id=p_site and s.organization_id=p_org
 ) then return false; end if;
 if p_asset is not null then
   select * into a from public.fm_assets where id=p_asset;
   if a.id is null or a.organization_id<>p_org or
      (p_site is not null and a.site_id is distinct from p_site)
   then return false; end if;
 end if;
 if p_job is not null then
   select * into j from public.fm_ppm_jobs where id=p_job;
   if j.id is null or j.organization_id<>p_org or
      (p_asset is not null and j.asset_id<>p_asset) or
      (p_site is not null and j.site_id is distinct from p_site)
   then return false; end if;
 end if;
 return true;
end;
$$;

create or replace function public.technical_can_read(
 p_org uuid,p_site uuid,p_author uuid,p_status text)
returns boolean language sql stable security definer
set search_path=public,pg_temp as $$
 select auth.uid() is not null and (
   public.fm_ppm_can_manage(p_org)
   or (coalesce(public.is_approved_active_user(),false)
       and p_site is not null and coalesce(public.has_site_access(p_site),false)
       and (p_status in ('approved','superseded') or p_author=auth.uid()))
 )
$$;
create or replace function public.technical_can_edit(
 p_org uuid,p_site uuid,p_author uuid)
returns boolean language sql stable security definer
set search_path=public,pg_temp as $$
 select auth.uid() is not null and
 (public.fm_ppm_can_manage(p_org) or (
   p_author=auth.uid() and
   p_site is not null and
   coalesce(public.fm_ppm_can_execute(p_org,p_site),false)))
$$;

create or replace function public.technical_validate_payload(p_kind text,p_payload jsonb)
returns boolean language plpgsql immutable set search_path=public,pg_temp as $$
declare row_item jsonb; initial_risk int; residual_risk int; seen_ids text[] := array[]::text[];
begin
 if p_payload is null or jsonb_typeof(p_payload)<>'object'
 then return false;end if;
 if octet_length(p_payload::text)>262144 then return false;end if;
 if p_kind in ('method_statement','sop') then
   if length(btrim(coalesce(p_payload->>'scope','')))=0 or
      jsonb_typeof(p_payload->'steps')<>'array' or
      jsonb_array_length(p_payload->'steps')<1 or
      jsonb_array_length(p_payload->'steps')>100 then return false;end if;
   for row_item in select value from jsonb_array_elements(p_payload->'steps') loop
     if jsonb_typeof(row_item)<>'string' or
       length(btrim(row_item #>> '{}'))=0 then return false;end if;
   end loop;
   return true;
 elsif p_kind in ('risk_assessment','jsa') then
   if jsonb_typeof(p_payload->'hazards')<>'array'
      or jsonb_array_length(p_payload->'hazards')=0 or
      jsonb_array_length(p_payload->'hazards')>100 then return false;end if;
   for row_item in select value from jsonb_array_elements(p_payload->'hazards') loop
     if jsonb_typeof(row_item)<>'object'
        or length(btrim(coalesce(row_item->>'hazard','')))=0
        or length(btrim(coalesce(row_item->>'controls','')))=0
        or coalesce(row_item->>'severity','') !~ '^[1-5]$'
        or coalesce(row_item->>'likelihood','') !~ '^[1-5]$'
        or coalesce(row_item->>'residual_severity','') !~ '^[1-5]$'
        or coalesce(row_item->>'residual_likelihood','') !~ '^[1-5]$'
      then return false;end if;
      initial_risk:=(row_item->>'severity')::int*(row_item->>'likelihood')::int;
      residual_risk:=(row_item->>'residual_severity')::int*
        (row_item->>'residual_likelihood')::int;
      if residual_risk>initial_risk then return false;end if;
   end loop;
   return true;
 elsif p_kind='cop' then
   return length(btrim(coalesce(p_payload->>'source','')))>0
     and length(btrim(coalesce(p_payload->>'edition','')))>0;
 elsif p_kind='ptw' then
   return length(btrim(coalesce(p_payload->>'work_scope','')))>0
    and jsonb_typeof(p_payload->'hazards')='array'
    and jsonb_array_length(p_payload->'hazards')>0
    and jsonb_typeof(p_payload->'controls')='array'
    and jsonb_array_length(p_payload->'controls')>0
    and length(btrim(coalesce(p_payload->>'emergency_plan','')))>0;
 elsif p_kind='itp' then
   if jsonb_typeof(p_payload->'checkpoints')<>'array'
    or jsonb_array_length(p_payload->'checkpoints')=0 or
    jsonb_array_length(p_payload->'checkpoints')>100 then return false;end if;
   for row_item in select value from jsonb_array_elements(p_payload->'checkpoints') loop
     if length(btrim(coalesce(row_item->>'id','')))=0 or
       row_item->>'id'=any(seen_ids) then return false;end if;
     seen_ids:=seen_ids || (row_item->>'id');
     if length(btrim(coalesce(row_item->>'description','')))=0
       or length(btrim(coalesce(row_item->>'acceptance_criteria','')))=0
       or coalesce(row_item->>'point_type','') not in ('hold','witness','review','test')
     then return false;end if;
   end loop;
   return true;
 elsif p_kind='ncr' then
   return length(btrim(coalesce(p_payload->>'finding','')))>0
    and length(btrim(coalesce(p_payload->>'corrective_action','')))>0
    and length(btrim(coalesce(p_payload->>'root_cause','')))>0;
 end if;
 -- Unknown document kinds are not executable by P3 technical engine.
 return false;
end;
$$;

-- Explicit read-only RLS. All updates are via guarded RPC transactions.
alter table public.technical_documents enable row level security;
alter table public.technical_document_versions enable row level security;
alter table public.technical_document_decisions enable row level security;
alter table public.technical_document_links enable row level security;
create policy technical_documents_read on public.technical_documents
for select to authenticated using (
 public.technical_can_read(organization_id,site_id,created_by,status));
create policy technical_versions_read on public.technical_document_versions
for select to authenticated using (
 exists(select 1 from public.technical_documents d
 where d.id=document_id and public.technical_can_read(
 d.organization_id,d.site_id,d.created_by,d.status)));
create policy technical_decisions_read on public.technical_document_decisions
for select to authenticated using (
 exists(select 1 from public.technical_documents d
 where d.id=document_id and public.technical_can_read(
 d.organization_id,d.site_id,d.created_by,d.status)));
create policy technical_links_read on public.technical_document_links
for select to authenticated using (
 exists(select 1 from public.technical_documents d
 where d.id=source_id and public.technical_can_read(
 d.organization_id,d.site_id,d.created_by,d.status))
 and exists(select 1 from public.technical_documents t
 where t.id=target_id and public.technical_can_read(
 t.organization_id,t.site_id,t.created_by,t.status))
);

revoke all on public.technical_documents,public.technical_document_versions,
public.technical_document_decisions,public.technical_document_links
from public,anon,authenticated;
grant select on public.technical_documents,public.technical_document_versions,
public.technical_document_decisions,public.technical_document_links to authenticated;
revoke all on function public.technical_can_read(uuid,uuid,uuid,text),
 public.technical_can_edit(uuid,uuid,uuid),
 public.technical_verify_scope(uuid,uuid,uuid,uuid),
 public.technical_validate_payload(text,jsonb) from public,anon;
grant execute on function public.technical_can_read(uuid,uuid,uuid,text),
 public.technical_can_edit(uuid,uuid,uuid),
 public.technical_verify_scope(uuid,uuid,uuid,uuid),
 public.technical_validate_payload(text,jsonb) to authenticated;
