-- P1 owner curation audit and security, isolated PostgreSQL fixture only.
set role authenticated;
set request.jwt.claim.sub='10000000-0000-0000-0000-000000000002';
do $$
declare denied boolean:=false;
begin
  begin
    perform public.assign_global_library_taxonomy_v2(
      '20000000-0000-0000-0000-000000000001',
      array['hospitality'],array['cleaning']);
  exception when insufficient_privilege then denied:=true;
  end;
  if not denied then raise exception 'non-owner changed taxonomy'; end if;
end;
$$;
set request.jwt.claim.sub='10000000-0000-0000-0000-000000000003';
do $$
declare rejected boolean:=false; before_count int; after_count int;
begin
  begin
    perform public.assign_global_library_taxonomy_v2(
      '20000000-0000-0000-0000-000000000001',
      array['unknown-industry'],array['cleaning']);
  exception when others then rejected:=true;
  end;
  if not rejected then raise exception 'unknown global industry accepted'; end if;
  perform public.assign_global_library_taxonomy_v2(
    '20000000-0000-0000-0000-000000000001',
    array['facilities','hospitality'],array['hvac','cleaning']);
  select count(*) into after_count
  from public.library_template_taxonomy
  where template_id='20000000-0000-0000-0000-000000000001';
  if after_count <> 4 then raise exception 'expected exactly 4 mappings after replacement, got %',after_count; end if;
  select count(*) into after_count
  from public.library_taxonomy_audit_log
  where template_id='20000000-0000-0000-0000-000000000001';
  if after_count <> 1 then raise exception 'expected 1 immutable curation audit record'; end if;
  select count(*) into before_count
  from public.checklist_library_revisions
  where library_template_id='20000000-0000-0000-0000-000000000001';
  if before_count <> 1 then raise exception 'taxonomy edit rewrote old revision snapshots'; end if;
end;
$$;
reset role;
select 'P1 OWNER CURATION + AUDIT PASS' as result;
