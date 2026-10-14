-- GLOB-001 P3-B: authored documents, append-only versions, independent approvals.
create or replace function public.technical_create_document(
 p_org uuid,p_kind text,p_code text,p_title text,
 p_site uuid default null,p_asset uuid default null,p_job uuid default null,
 p_country text default null,p_standard text default null,
 p_edition text default null,p_language text default 'en'
)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_id uuid;
begin
 if auth.uid() is null or not coalesce(public.is_approved_active_user(),false)
   or not public.technical_can_edit(p_org,p_site,auth.uid()) then
   raise exception 'document creation not authorized' using errcode='42501';end if;
 if p_kind not in ('method_statement','risk_assessment','jsa','sop','cop','ptw','itp','ncr') then
   raise exception 'unsupported technical document kind';end if;
 if not public.technical_verify_scope(p_org,p_site,p_asset,p_job) then
   raise exception 'document references another organization or site';end if;
 if p_code is null or btrim(p_code)='' or p_title is null or btrim(p_title)=''
 then raise exception 'document reference and title required';end if;
 insert into public.technical_documents(organization_id,site_id,asset_id,ppm_job_id,
  document_code,document_kind,title,jurisdiction_country,standard_reference,
  standard_edition,language_code,created_by)
 values(p_org,p_site,p_asset,p_job,btrim(p_code),p_kind,btrim(p_title),
  p_country,p_standard,p_edition,p_language,auth.uid()) returning id into v_id;
 return v_id;
end;
$$;

create or replace function public.technical_save_revision(
 p_document uuid,p_content jsonb,p_change_note text default ''
)
returns integer language plpgsql security definer set search_path=public,pg_temp as $$
declare d public.technical_documents%rowtype; v_next int;
begin
 select * into d from public.technical_documents where id=p_document for update;
 if d.id is null or not public.technical_can_edit(d.organization_id,d.site_id,d.created_by)
 then raise exception 'document edit denied' using errcode='42501';end if;
 if d.status not in ('draft','rejected') then
   raise exception 'cannot modify submitted, approved or superseded document';end if;
 if not public.technical_validate_payload(d.document_kind,p_content) then
   raise exception 'document content does not match required type schema';end if;
 v_next:=d.current_version+1;
 insert into public.technical_document_versions(document_id,version_no,payload,
  change_note,author_id)
 values(d.id,v_next,p_content,coalesce(p_change_note,''),auth.uid());
 update public.technical_documents set
  current_version=v_next,status='draft',approved_version=null,updated_at=now()
 where id=d.id;
 return v_next;
end;
$$;

create or replace function public.technical_submit_review(p_document uuid)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare d public.technical_documents%rowtype;
begin
 select * into d from public.technical_documents where id=p_document for update;
 if d.id is null or not public.technical_can_edit(d.organization_id,d.site_id,d.created_by)
 then raise exception 'document submission denied' using errcode='42501';end if;
 if d.current_version<1 or d.status<>'draft' then
   raise exception 'only authored drafts can be submitted';end if;
 update public.technical_documents set status='in_review',updated_at=now()
 where id=d.id;
 insert into public.technical_document_decisions(document_id,version_no,decision,actor_id)
 values(d.id,d.current_version,'submitted',auth.uid());
end;
$$;

create or replace function public.technical_decide_review(
 p_document uuid,p_approve boolean,p_remarks text default null
)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare d public.technical_documents%rowtype; v_content jsonb;
begin
 select * into d from public.technical_documents where id=p_document for update;
 if d.id is null or not public.fm_ppm_can_manage(d.organization_id) then
   raise exception 'document approval requires organization authority'
   using errcode='42501';end if;
 if d.created_by=auth.uid() then
   raise exception 'self approval prohibited; independent authorized reviewer required'
   using errcode='42501';end if;
 if d.status<>'in_review' then
   raise exception 'only submitted drafts may be reviewed';end if;
 select payload into v_content from public.technical_document_versions
  where document_id=d.id and version_no=d.current_version;
 if p_approve and not public.technical_validate_payload(d.document_kind,v_content)
 then raise exception 'current document revision invalid';end if;
 if not p_approve and length(btrim(coalesce(p_remarks,'')))<5
 then raise exception 'a rejection reason is required';end if;
 update public.technical_documents set status=case when p_approve then 'approved' else 'rejected' end,
   approved_version=case when p_approve then current_version else null end,
   reviewer_note=p_remarks,updated_at=now() where id=d.id;
 insert into public.technical_document_decisions(document_id,version_no,decision,actor_id,remarks)
 values(d.id,d.current_version,case when p_approve then 'approved' else 'rejected' end,
 auth.uid(),p_remarks);
end;
$$;

create or replace function public.technical_link_document(
 p_source uuid,p_target uuid,p_relationship text default 'related'
)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare a public.technical_documents%rowtype;b public.technical_documents%rowtype;
begin
 select * into a from public.technical_documents where id=p_source;
 select * into b from public.technical_documents where id=p_target;
 if a.id is null or b.id is null or a.organization_id<>b.organization_id
   or (a.site_id is not null and b.site_id is not null and a.site_id<>b.site_id)
 then raise exception 'linked documents must belong to compatible sites in one organization';end if;
 if not public.technical_can_edit(a.organization_id,a.site_id,a.created_by) then
   raise exception 'document linking denied' using errcode='42501';end if;
 if p_relationship not in ('supports','risk_assessment','related','supersedes')
 then raise exception 'unsupported link relationship';end if;
 if a.id=b.id then raise exception 'cannot link document to itself';end if;
 if p_relationship='risk_assessment' and
  (a.document_kind<>'ptw' or b.document_kind not in ('risk_assessment','jsa'))
 then raise exception 'PTW requires a risk assessment/JSA link';end if;
 insert into public.technical_document_links(source_id,target_id,relationship,created_by)
 values(a.id,b.id,p_relationship,auth.uid()) on conflict do nothing;
end;
$$;

-- Records cannot be altered via client INSERT/UPDATE/DELETE; approvals and
-- revisions are new rows, and historical rows are never overwritten.
-- Source is immutable after approval. Superseding requires a distinct document
-- with a 'supersedes' link. No mass editing of evidence.
revoke all on function public.technical_create_document(
 uuid,text,text,text,uuid,uuid,uuid,text,text,text,text),
 public.technical_save_revision(uuid,jsonb,text),
 public.technical_submit_review(uuid),
 public.technical_decide_review(uuid,boolean,text),
 public.technical_link_document(uuid,uuid,text)
from public,anon;
grant execute on function public.technical_create_document(
 uuid,text,text,text,uuid,uuid,uuid,text,text,text,text),
 public.technical_save_revision(uuid,jsonb,text),
 public.technical_submit_review(uuid),
 public.technical_decide_review(uuid,boolean,text),
 public.technical_link_document(uuid,uuid,text)
to authenticated;
