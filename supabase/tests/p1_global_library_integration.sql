-- P1 isolated SQL integration checks (p1 fixture + 3 migrations).
set role authenticated;
set request.jwt.claim.sub = '10000000-0000-0000-0000-000000000001';
do $$
declare
  v_json jsonb;
  v_count int;
begin
  select count(*) into v_count from public.checklist_library_revisions;
  if v_count <> 2 then raise exception 'Org A: expected premium+free archive, got %',v_count; end if;
  select count(*) into v_count
    from public.list_global_library_v2('00000000-0000-0000-0000-00000000000a');
  if v_count <> 2 then raise exception 'Org A: expected 2 published catalog rows, got %',v_count; end if;
  select x into v_json
    from public.list_global_library_v2('00000000-0000-0000-0000-00000000000a') x
    where x->>'slug'='chiller_plant';
  if v_json->>'can_access' <> 'true' then
    raise exception 'purchased template must be accessible before revocation';
  end if;
  if jsonb_array_length(v_json->'industries') <> 2 or
     jsonb_array_length(v_json->'domains') < 2 or
     v_json->>'document_kind'<>'checklist' then
     raise exception 'taxonomy backfill must support 2+ sectors and domains: %',v_json;
  end if;
  if v_json ? 'items_snapshot' or v_json ? 'description_items' then
     raise exception 'catalog metadata must never expose item bodies';
  end if;
  select count(*) into v_count from public.list_global_library_v2(
    '00000000-0000-0000-0000-00000000000a',
    p_sector=>'facilities',p_domain=>'hvac',p_kind=>'checklist');
  if v_count <> 1 then raise exception 'industry+domain+kind combination incorrectly filtered: %',v_count; end if;
  select count(*) into v_count from public.list_global_library_v2(
    '00000000-0000-0000-0000-00000000000a', p_sector=>'manufacturing');
  if v_count <> 0 then raise exception 'industry filter did not narrow properly'; end if;
  select count(*) into v_count from public.list_global_library_v2(
    '00000000-0000-0000-0000-00000000000a',p_search=>'Chiller');
  if v_count <> 1 then raise exception 'keyword search failed'; end if;
  select count(*) into v_count from public.list_global_library_v2(
    '00000000-0000-0000-0000-00000000000a',p_limit=>1,p_offset=>1);
  if v_count <> 1 then raise exception 'paging failed'; end if;
  select count(*) into v_count from public.list_global_library_facets_v2(
    '00000000-0000-0000-0000-00000000000a') where dimension='industry';
  if v_count < 2 then raise exception 'facets should include multiple sectors'; end if;
  select count(*) into v_count from public.list_global_library_facets_v2(
    '00000000-0000-0000-0000-00000000000a') where dimension='category';
  if v_count <> 2 then raise exception 'full category facets missing: %', v_count; end if;
  select count(*) into v_count from public.list_global_library_v2(
    '00000000-0000-0000-0000-00000000000a', p_category=>'technical');
  if v_count <> 1 then raise exception 'category server filter failed: %',v_count; end if;
end;
$$;

-- Org B sees the public library metadata, not the premium snapshots or access.
set request.jwt.claim.sub = '10000000-0000-0000-0000-000000000002';
do $$
declare v_json jsonb; v_count int; v_denied boolean := false;
begin
  select count(*) into v_count from public.checklist_library_revisions;
  if v_count <> 1 then raise exception 'Org B must only see one free archive: %',v_count; end if;
  select x into v_json
    from public.list_global_library_v2('00000000-0000-0000-0000-00000000000b') x
    where x->>'slug'='chiller_plant';
  if v_json->>'can_access' <> 'false' then raise exception 'locked paid content marked accessible'; end if;
  begin
    perform 1 from public.list_global_library_v2('00000000-0000-0000-0000-00000000000a');
  exception when insufficient_privilege then v_denied := true;
  end;
  if not v_denied then raise exception 'Org B was allowed to browse as Org A'; end if;
end;
$$;

-- Suspended profile must not see revisions or search metadata.
set request.jwt.claim.sub = '10000000-0000-0000-0000-000000000004';
do $$
declare v_count int; v_denied boolean := false;
begin
  select count(*) into v_count from public.checklist_library_revisions;
  if v_count <> 0 then raise exception 'suspended user can read snapshots'; end if;
  begin
    perform 1 from public.list_global_library_v2('00000000-0000-0000-0000-00000000000a');
  exception when insufficient_privilege then v_denied := true;
  end;
  if not v_denied then raise exception 'suspended user can browse catalog'; end if;
end;
$$;

-- Platform owner can access unpublished archival records.
set request.jwt.claim.sub = '10000000-0000-0000-0000-000000000003';
do $$
declare v_count int;
begin
  select count(*) into v_count from public.checklist_library_revisions;
  if v_count <> 3 then raise exception 'platform owner must see 3 snapshots: %',v_count; end if;
end;
$$;
reset role;

-- Simulate verified paid purchase cancellation, then A loses archived body.
update public.organization_library_purchases set purchase_state='revoked'
where organization_id='00000000-0000-0000-0000-00000000000a';
set role authenticated;
set request.jwt.claim.sub = '10000000-0000-0000-0000-000000000001';
do $$
declare v_count int; v_access text;
begin
  select count(*) into v_count from public.checklist_library_revisions;
  if v_count <> 1 then raise exception 'revoked purchase should lose archive access: %',v_count; end if;
  select x->>'can_access' into v_access
    from public.list_global_library_v2('00000000-0000-0000-0000-00000000000a') x
    where x->>'slug'='chiller_plant';
  if v_access <> 'false' then raise exception 'revoked paid content must be locked'; end if;
end;
$$;
reset role;
select 'P1 SQL ISOLATED AUTHORIZATION AND METADATA TESTS PASSED' as result;
