-- All checks run in a disposable PostgreSQL instance.
set role authenticated;
set request.jwt.claim.sub='10000000-0000-0000-0000-000000000001';
do $$
declare a uuid;ra uuid; ptw uuid;itp uuid;ncr uuid;ms uuid;sop uuid;cop uuid;jsa uuid;
  job uuid;v integer;denied boolean;
  ra_payload jsonb := '{"hazards":[{"hazard":"Uncontrolled energy","controls":"LOTO by authorized staff","severity":5,"likelihood":4,"residual_severity":5,"residual_likelihood":1}]}';
begin
 a:=public.fm_ppm_save_asset('00000000-0000-0000-0000-00000000000a','P3-CH-01',
  'Plant Chiller','chiller','50000000-0000-0000-0000-000000000001');
 ra:=public.technical_create_document('00000000-0000-0000-0000-00000000000a',
  'risk_assessment','RA-01','Chiller Plant Risk Assessment',
  '50000000-0000-0000-0000-000000000001',a);
 perform set_config('test.p3.ra',ra::text,false);
 v:=public.technical_save_revision(ra,ra_payload,'Initial risk register');
 if v<>1 then raise exception 'RA first version unexpected';end if;
 denied:=false;
 begin
   perform public.technical_save_revision(ra,
     '{"hazards":[{"hazard":"Heat","controls":"PPE","severity":1,"likelihood":1,"residual_severity":5,"residual_likelihood":5}]}'::jsonb);
 exception when others then denied:=true;end;
 if not denied then raise exception 'worse residual risk accepted';end if;
 perform public.technical_submit_review(ra);
 denied:=false;
 begin perform public.technical_decide_review(ra,true);
 exception when insufficient_privilege then denied:=true;end;
 if not denied then raise exception 'self approval accepted';end if;

 ptw:=public.technical_create_document('00000000-0000-0000-0000-00000000000a',
  'ptw','PTW-01','Chiller lockout permit','50000000-0000-0000-0000-000000000001',a);
 perform set_config('test.p3.ptw',ptw::text,false);
 perform public.technical_save_revision(ptw,
   '{"work_scope":"Chiller isolations","hazards":["electrical"],"controls":["LOTO"],"emergency_plan":"Evacuate and call emergency response"}'::jsonb);
 perform public.technical_link_document(ptw,ra,'risk_assessment');
 perform public.technical_submit_review(ptw);

 itp:=public.technical_create_document('00000000-0000-0000-0000-00000000000a',
  'itp','ITP-01','Plant inspection test plan','50000000-0000-0000-0000-000000000001',a);
 perform set_config('test.p3.itp',itp::text,false);
 perform public.technical_save_revision(itp,
 '{"checkpoints":[{"id":"H1","point_type":"hold","description":"Witness pressure testing","acceptance_criteria":"Meets approved test procedure"}]}'::jsonb);
 perform public.technical_submit_review(itp);

 ncr:=public.technical_create_document('00000000-0000-0000-0000-00000000000a',
  'ncr','NCR-01','Defective valve correction','50000000-0000-0000-0000-000000000001',a);
 perform set_config('test.p3.ncr',ncr::text,false);
 perform public.technical_save_revision(ncr,
 '{"finding":"Valve leaks","root_cause":"Failed gasket","corrective_action":"Replace gasket and retest"}'::jsonb);
 perform public.technical_submit_review(ncr);

 ms:=public.technical_create_document('00000000-0000-0000-0000-00000000000a',
  'method_statement','MS-01','Chiller method statement','50000000-0000-0000-0000-000000000001',a);
 perform public.technical_save_revision(ms,
 '{"scope":"Replace gasket safely","steps":["Isolate equipment","Verify zero energy","Replace gasket","Retest"]}'::jsonb);
 perform public.technical_submit_review(ms);
 sop:=public.technical_create_document('00000000-0000-0000-0000-00000000000a',
  'sop','SOP-01','Pump operations procedure','50000000-0000-0000-0000-000000000001',a);
 perform public.technical_save_revision(sop,
 '{"scope":"Pump operations","steps":["Inspect equipment","Record readings"]}'::jsonb);
 perform public.technical_submit_review(sop);
 cop:=public.technical_create_document('00000000-0000-0000-0000-00000000000a',
  'cop','COP-01','Regulatory reference','50000000-0000-0000-0000-000000000001',a);
 perform public.technical_save_revision(cop,
 '{"source":"Example regulator","edition":"2026"}'::jsonb);
 perform public.technical_submit_review(cop);
 jsa:=public.technical_create_document('00000000-0000-0000-0000-00000000000a',
  'jsa','JSA-01','Plant access hazard analysis','50000000-0000-0000-0000-000000000001',a);
 perform public.technical_save_revision(jsa,ra_payload);
 perform public.technical_submit_review(jsa);
 if (select count(*) from public.technical_document_versions)<>8 then
   raise exception 'P3-B kind coverage missing';end if;
end $$;

-- Unauthorized Org B cannot see Org A documents or approve them.
set request.jwt.claim.sub='10000000-0000-0000-0000-000000000002';
do $$
declare cnt integer;denied boolean:=false;
begin
 select count(*) into cnt from public.technical_documents;
 if cnt<>0 then raise exception 'cross-tenant documents exposed: %',cnt;end if;
 select count(*) into cnt from public.technical_document_versions;
 if cnt<>0 then raise exception 'cross-tenant version snapshots exposed';end if;
 begin
 perform public.technical_decide_review(
   current_setting('test.p3.ra')::uuid,true);
 exception when insufficient_privilege then denied:=true;end;
 if not denied then raise exception 'cross-tenant reviewer bypass';end if;
end $$;

-- Independent platform reviewer accepts submitted revisions.
set request.jwt.claim.sub='10000000-0000-0000-0000-000000000003';
do $$
declare d record;v_ptw uuid;v_ra uuid;v_itp uuid;v_ncr uuid;v_permit uuid;
 denied boolean:=false;v_signed uuid;
begin
 for d in select id from public.technical_documents where status='in_review'
 loop perform public.technical_decide_review(d.id,true,'Reviewed and accepted as internal document');end loop;
 v_ptw:=current_setting('test.p3.ptw')::uuid;
 v_ra:=current_setting('test.p3.ra')::uuid;
 v_itp:=current_setting('test.p3.itp')::uuid;
 v_ncr:=current_setting('test.p3.ncr')::uuid;
 if (select count(*) from public.technical_documents where status='approved')<>8
 then raise exception 'independent approvals missing';end if;
 begin
   perform public.technical_save_revision(v_ra,
     '{"hazards":[]}'::jsonb);
 exception when others then denied:=true;end;
 if not denied then raise exception 'approved version edited';end if;
 v_permit:=public.technical_issue_permit(v_ptw,v_ra,now(),now()+interval '4 hours');
 if (select state from public.technical_permit_issues where id=v_permit)<>'active'
 then raise exception 'PTW not issued';end if;
 perform public.technical_transition_permit(v_permit,'suspended','Suspended for access review');
 perform public.technical_transition_permit(v_permit,'resumed','Controls verified again');
 perform public.technical_transition_permit(v_permit,'closed','All work completed safely');
 denied:=false;
 begin perform public.technical_transition_permit(v_permit,'resumed','Replay');
 exception when others then denied:=true;end;
 if not denied then raise exception 'closed permit resumed';end if;
 v_signed:=public.technical_sign_itp(v_itp,'H1','pass',
   'Pressure test witness verified on approved limits',
   'a0000000-0000-0000-0000-000000000001');
 if v_signed is null then raise exception 'ITP hold signoff missing';end if;
 perform public.technical_close_ncr(v_ncr,'corrected','Verified gasket replacement and retest',
 'a0000000-0000-0000-0000-000000000001');
 if (select count(*) from public.technical_ncr_closures)<>1 then
   raise exception 'NCR not closed';end if;
 if (select count(*) from public.technical_permit_events where permit_id=v_permit)<>4
 then raise exception 'PTW immutable event history incomplete';end if;
end $$;

-- Audited supersession requires two independently approved documents.
set request.jwt.claim.sub='10000000-0000-0000-0000-000000000003';
do $$
declare new_ra uuid;
begin
 new_ra:=public.technical_create_document(
  '00000000-0000-0000-0000-00000000000a',
  'risk_assessment','RA-02','Revised plant risk assessment',
  '50000000-0000-0000-0000-000000000001');
 perform public.technical_save_revision(new_ra,
  '{"hazards":[{"hazard":"Stored energy","controls":"LOTO and verification","severity":5,"likelihood":3,"residual_severity":5,"residual_likelihood":1}]}'::jsonb);
 perform public.technical_submit_review(new_ra);
 perform set_config('test.p3.new_ra',new_ra::text,false);
end $$;
set request.jwt.claim.sub='10000000-0000-0000-0000-000000000001';
do $$
declare old_ra uuid:=current_setting('test.p3.ra')::uuid;
  new_ra uuid:=current_setting('test.p3.new_ra')::uuid;
begin
 perform public.technical_decide_review(new_ra,true,'Independent revision approval');
 perform public.technical_supersede_document(old_ra,new_ra,
  'Updated assessment supersedes previous revision');
 if (select status from public.technical_documents where id=old_ra)<>'superseded'
 or not exists (select 1 from public.technical_document_links
  where source_id=new_ra and target_id=old_ra and relationship='supersedes')
 then raise exception 'supersession not recorded correctly';end if;
 if (select count(*) from public.technical_document_versions where document_id=old_ra)<>1
 then raise exception 'supersession changed original version';end if;
end $$;

-- Direct table mutation is unavailable to authenticated sessions.
set request.jwt.claim.sub='10000000-0000-0000-0000-000000000001';
do $$
declare denied boolean:=false;v_ra uuid:=current_setting('test.p3.ra')::uuid;
begin
 begin delete from public.technical_document_versions where document_id=v_ra;
 exception when insufficient_privilege then denied:=true;end;
 if not denied then raise exception 'historical evidence was deletable';end if;
end $$;
reset role;
select 'P3 A B C: 8 DOCUMENT KINDS, RLS, APPROVAL, PTW, ITP, NCR PASS' as result;
