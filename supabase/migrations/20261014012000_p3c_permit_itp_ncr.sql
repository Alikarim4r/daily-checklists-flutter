-- GLOB-001 P3-C: controlled PTW issuance, ITP hold/witness sign-off,
-- and NCR closure with immutable evidence.
create table if not exists public.technical_permit_issues (
 id uuid primary key default gen_random_uuid(),
 document_id uuid not null unique references public.technical_documents(id) on delete restrict,
 ra_document_id uuid not null references public.technical_documents(id) on delete restrict,
 organization_id uuid not null references public.organizations(id) on delete restrict,
 valid_from timestamptz not null,
 valid_until timestamptz not null,
 state text not null default 'active' check(state in ('active','suspended','closed')),
 issued_by uuid not null references public.profiles(id),
 issued_at timestamptz not null default now(),
 closed_by uuid references public.profiles(id),
 closure_note text,
 closed_at timestamptz,
 check(valid_until>valid_from)
);
create index if not exists technical_permit_org_valid_idx
 on public.technical_permit_issues(organization_id,state,valid_until);

create table if not exists public.technical_permit_events (
 id uuid primary key default gen_random_uuid(),
 permit_id uuid not null references public.technical_permit_issues(id) on delete restrict,
 event text not null check(event in ('issued','suspended','resumed','closed')),
 actor_id uuid not null references public.profiles(id) on delete restrict,
 note text,
 happened_at timestamptz not null default now()
);

create table if not exists public.technical_itp_results (
 id uuid primary key default gen_random_uuid(),
 document_id uuid not null references public.technical_documents(id) on delete restrict,
 checkpoint_id text not null,
 point_type text not null check(point_type in ('hold','witness','review','test')),
 result text not null check(result in ('pass','fail')),
 evidence_note text not null check(length(btrim(evidence_note))>=5),
 inspection_id uuid references public.checklist_inspections(id) on delete restrict,
 signer_id uuid not null references public.profiles(id) on delete restrict,
 signed_at timestamptz not null default now(),
 unique(document_id,checkpoint_id)
);

create table if not exists public.technical_ncr_closures (
 document_id uuid primary key references public.technical_documents(id) on delete restrict,
 disposition text not null check(disposition in ('corrected','accepted_deviation','rework')),
 verified_notes text not null check(length(btrim(verified_notes))>=5),
 inspection_id uuid references public.checklist_inspections(id) on delete restrict,
 closed_by uuid not null references public.profiles(id) on delete restrict,
 closed_at timestamptz not null default now()
);
alter table public.technical_permit_issues enable row level security;
alter table public.technical_permit_events enable row level security;
alter table public.technical_itp_results enable row level security;
alter table public.technical_ncr_closures enable row level security;

create policy technical_permit_issues_read on public.technical_permit_issues
for select to authenticated using(
 exists(select 1 from public.technical_documents d where d.id=document_id
 and public.technical_can_read(d.organization_id,d.site_id,d.created_by,d.status)));
create policy technical_permit_events_read on public.technical_permit_events
for select to authenticated using(
 exists(select 1 from public.technical_permit_issues p
  join public.technical_documents d on d.id=p.document_id where p.id=permit_id
 and public.technical_can_read(d.organization_id,d.site_id,d.created_by,d.status)));
create policy technical_itp_results_read on public.technical_itp_results
for select to authenticated using(
 exists(select 1 from public.technical_documents d where d.id=document_id
 and public.technical_can_read(d.organization_id,d.site_id,d.created_by,d.status)));
create policy technical_ncr_closures_read on public.technical_ncr_closures
for select to authenticated using(
 exists(select 1 from public.technical_documents d where d.id=document_id
 and public.technical_can_read(d.organization_id,d.site_id,d.created_by,d.status)));
revoke all on public.technical_permit_issues,public.technical_permit_events,
 public.technical_itp_results,public.technical_ncr_closures from public,anon,authenticated;
grant select on public.technical_permit_issues,public.technical_permit_events,
 public.technical_itp_results,public.technical_ncr_closures to authenticated;

-- Permit: issue only an independently approved PTW referencing an independently
-- approved risk assessment at the same company and compatible site.
create or replace function public.technical_issue_permit(
 p_ptw uuid,p_ra uuid,p_from timestamptz,p_until timestamptz)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare d public.technical_documents%rowtype;r public.technical_documents%rowtype;v_id uuid;
begin
 select * into d from public.technical_documents where id=p_ptw for update;
 select * into r from public.technical_documents where id=p_ra;
 if d.id is null or d.document_kind<>'ptw' or d.status<>'approved'
  or not public.fm_ppm_can_manage(d.organization_id) then
    raise exception 'PTW issuance denied or PTW unapproved' using errcode='42501';end if;
 if r.id is null or r.document_kind not in ('risk_assessment','jsa')
  or r.status<>'approved' or r.organization_id<>d.organization_id
  or (d.site_id is not null and r.site_id is not null and d.site_id<>r.site_id)
  or not exists(select 1 from public.technical_document_links l
    where l.source_id=d.id and l.target_id=r.id and l.relationship='risk_assessment')
 then raise exception 'an approved linked risk assessment is required';end if;
 if p_from is null or p_until is null or p_until<=p_from or
    p_until>p_from+interval '30 days' or p_until<=now()
 then raise exception 'permit validity must be in the future and at most 30 days';end if;
 if exists (select 1 from public.technical_permit_issues where document_id=d.id)
 then raise exception 'permit was issued already; a new permit needs a new PTW';end if;
 insert into public.technical_permit_issues
  (document_id,ra_document_id,organization_id,valid_from,valid_until,issued_by)
 values(d.id,r.id,d.organization_id,p_from,p_until,auth.uid()) returning id into v_id;
 insert into public.technical_permit_events(permit_id,event,actor_id,note)
 values(v_id,'issued',auth.uid(),'Issued for approved PTW and linked approved RA');
 return v_id;
end;
$$;

create or replace function public.technical_transition_permit(
 p_permit uuid,p_action text,p_note text default null)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare p public.technical_permit_issues%rowtype;
begin
 select * into p from public.technical_permit_issues where id=p_permit for update;
 if p.id is null or not public.fm_ppm_can_manage(p.organization_id)
 then raise exception 'permit status management denied' using errcode='42501';end if;
 if p_action='suspended' and p.state='active' then
  update public.technical_permit_issues set state='suspended' where id=p.id;
 elsif p_action='resumed' and p.state='suspended' and
      now() between p.valid_from and p.valid_until then
  update public.technical_permit_issues set state='active' where id=p.id;
 elsif p_action='closed' and p.state in ('active','suspended') and
      length(btrim(coalesce(p_note,'')))>=5 then
  update public.technical_permit_issues set state='closed',
    closure_note=btrim(p_note),closed_at=now(),closed_by=auth.uid() where id=p.id;
 else raise exception 'illegal permit transition or missing closure reason';end if;
 insert into public.technical_permit_events(permit_id,event,actor_id,note)
 values(p.id,p_action,auth.uid(),p_note);
end;
$$;

-- ITP checkpoints: immutable inspection signoff, with hold points signed only
-- by an authorized reviewer who did not author the original document.
create or replace function public.technical_sign_itp(
 p_document uuid,p_checkpoint text,p_result text,p_note text,
 p_inspection uuid default null)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare d public.technical_documents%rowtype;
  v_payload jsonb; v_point jsonb;v_type text;v_id uuid;
begin
 select * into d from public.technical_documents where id=p_document;
 if d.id is null or d.document_kind<>'itp' or d.status<>'approved' then
  raise exception 'approved ITP required';end if;
 if not public.fm_ppm_can_execute(d.organization_id,d.site_id) then
  raise exception 'ITP sign-off denied' using errcode='42501';end if;
 select payload into v_payload from public.technical_document_versions
 where document_id=d.id and version_no=d.approved_version;
 select x into v_point from jsonb_array_elements(v_payload->'checkpoints') x
 where x->>'id'=p_checkpoint limit 1;
 if v_point is null then raise exception 'ITP checkpoint not found';end if;
 v_type:=v_point->>'point_type';
 if v_type in ('hold','witness') and
  (not public.fm_ppm_can_manage(d.organization_id) or d.created_by=auth.uid())
 then raise exception 'independent authorized inspector needed for hold/witness point'
  using errcode='42501';end if;
 if p_result not in ('pass','fail') or length(btrim(coalesce(p_note,'')))<5
 then raise exception 'result and evidence note are required';end if;
 if p_inspection is not null and not exists (
  select 1 from public.checklist_inspections i
  join public.sites s on s.id=i.site_id
  where i.id=p_inspection and s.organization_id=d.organization_id
   and (d.site_id is null or i.site_id=d.site_id) and i.status='submitted'
 ) then raise exception 'ITP inspection evidence must be submitted and same tenant';end if;
 insert into public.technical_itp_results(document_id,checkpoint_id,point_type,
 result,evidence_note,inspection_id,signer_id)
 values(d.id,p_checkpoint,v_type,p_result,btrim(p_note),p_inspection,auth.uid())
 returning id into v_id;
 return v_id;
end;
$$;

create or replace function public.technical_close_ncr(
 p_document uuid,p_disposition text,p_notes text,p_inspection uuid default null)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare d public.technical_documents%rowtype;
begin
 select * into d from public.technical_documents where id=p_document for update;
 if d.id is null or d.document_kind<>'ncr' or d.status<>'approved'
  or not public.fm_ppm_can_manage(d.organization_id)
 then raise exception 'NCR closure denied or NCR not approved' using errcode='42501';end if;
 if d.created_by=auth.uid() then
  raise exception 'independent NCR verification required' using errcode='42501';end if;
 if p_disposition not in ('corrected','accepted_deviation','rework')
  or length(btrim(coalesce(p_notes,'')))<5
 then raise exception 'NCR disposition and verification required';end if;
 if p_inspection is not null and not exists(
  select 1 from public.checklist_inspections i
   join public.sites s on s.id=i.site_id
  where i.id=p_inspection and i.status='submitted'
   and s.organization_id=d.organization_id
   and (d.site_id is null or i.site_id=d.site_id)
 ) then raise exception 'NCR inspection evidence not in scope';end if;
 insert into public.technical_ncr_closures
  (document_id,disposition,verified_notes,inspection_id,closed_by)
 values(d.id,p_disposition,btrim(p_notes),p_inspection,auth.uid());
end;
$$;

-- P3 controlled lifecycle supersession (preserves all historical versions).
create or replace function public.technical_supersede_document(
 p_old uuid,p_new uuid,p_reason text
)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare old_doc public.technical_documents%rowtype;
  replacement public.technical_documents%rowtype;
begin
 select * into old_doc from public.technical_documents where id=p_old for update;
 select * into replacement from public.technical_documents where id=p_new for update;
 if old_doc.id is null or replacement.id is null
   or old_doc.id=replacement.id or old_doc.organization_id<>replacement.organization_id
   or old_doc.document_kind<>replacement.document_kind
   or old_doc.status<>'approved' or replacement.status<>'approved'
   or not public.fm_ppm_can_manage(old_doc.organization_id)
 then raise exception 'supersession requires two approved documents of the same type and organization'
  using errcode='42501';end if;
 if length(btrim(coalesce(p_reason,'')))<5 then raise exception 'supersession reason required';end if;
 if exists(select 1 from public.technical_permit_issues
   where document_id=p_old and state<>'closed' and valid_until>now())
 then raise exception 'active PTW must be closed before supersession';end if;
 insert into public.technical_document_links(source_id,target_id,relationship,created_by)
 values(p_new,p_old,'supersedes',auth.uid()) on conflict do nothing;
 update public.technical_documents set status='superseded',updated_at=now()
 where id=p_old;
 insert into public.technical_document_decisions
  (document_id,version_no,decision,actor_id,remarks)
 values(old_doc.id,old_doc.current_version,'superseded',auth.uid(),p_reason);
end;
$$;
revoke all on function public.technical_supersede_document(uuid,uuid,text)
 from public,anon;
grant execute on function public.technical_supersede_document(uuid,uuid,text)
 to authenticated;

revoke all on function public.technical_issue_permit(uuid,uuid,timestamptz,timestamptz),
 public.technical_transition_permit(uuid,text,text),
 public.technical_sign_itp(uuid,text,text,text,uuid),
 public.technical_close_ncr(uuid,text,text,uuid) from public,anon;
grant execute on function public.technical_issue_permit(uuid,uuid,timestamptz,timestamptz),
 public.technical_transition_permit(uuid,text,text),
 public.technical_sign_itp(uuid,text,text,text,uuid),
 public.technical_close_ncr(uuid,text,text,uuid) to authenticated;
