-- Exercise Data API grants and RLS as the actual PostgREST roles. Running only
-- as the database owner bypasses RLS and cannot detect production lockouts.
begin;

insert into public.organizations (id, name_en, name_ar)
values
  ('91000000-0000-4000-8000-000000000001', 'RLS Org A', 'جهة اختبار أ'),
  ('91000000-0000-4000-8000-000000000002', 'RLS Org B', 'جهة اختبار ب');

insert into public.zones (id, organization_id, code, name_en, name_ar)
values
  (
    '92000000-0000-4000-8000-000000000001',
    '91000000-0000-4000-8000-000000000001',
    'rls_a', 'RLS Zone A', 'منطقة اختبار أ'
  ),
  (
    '92000000-0000-4000-8000-000000000002',
    '91000000-0000-4000-8000-000000000002',
    'rls_b', 'RLS Zone B', 'منطقة اختبار ب'
  );

insert into public.sites (
  id, organization_id, zone_id, name_en, name_ar, building_code,
  checklist_type, site_type, location
)
values
  (
    '93000000-0000-4000-8000-000000000001',
    '91000000-0000-4000-8000-000000000001',
    '92000000-0000-4000-8000-000000000001',
    'RLS Site A', 'موقع اختبار أ', 'RLS-A', 'DEFAULT', 'other', 'A'
  ),
  (
    '93000000-0000-4000-8000-000000000002',
    '91000000-0000-4000-8000-000000000002',
    '92000000-0000-4000-8000-000000000002',
    'RLS Site B', 'موقع اختبار ب', 'RLS-B', 'DEFAULT', 'other', 'B'
  );

insert into auth.users (id, email, raw_user_meta_data)
values
  (
    '94000000-0000-4000-8000-000000000001',
    'rls-technician@example.test',
    '{"full_name":"RLS Technician"}'
  ),
  (
    '94000000-0000-4000-8000-000000000002',
    'rls-outsider@example.test',
    '{"full_name":"RLS Outsider"}'
  );

update public.profiles
set role = 'technician', is_active = true, approval_status = 'approved'
where id in (
  '94000000-0000-4000-8000-000000000001',
  '94000000-0000-4000-8000-000000000002'
);

insert into public.user_site_access (
  user_id, site_id, role, can_read, can_write, can_manage
)
values (
  '94000000-0000-4000-8000-000000000001',
  '93000000-0000-4000-8000-000000000001',
  'technician', true, true, false
);

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '94000000-0000-4000-8000-000000000001',
  true
);

do $$
declare
  v_inspection_id uuid;
begin
  if not has_table_privilege('authenticated', 'public.sites', 'select') then
    raise exception 'authenticated is missing explicit sites SELECT';
  end if;
  if has_table_privilege(
    'authenticated', 'public.checklist_inspections', 'insert'
  ) then
    raise exception 'authenticated unexpectedly has direct inspection INSERT';
  end if;

  if (select count(*) from public.sites where building_code = 'RLS-A') <> 1 then
    raise exception 'assigned site is not visible through RLS';
  end if;
  if (select count(*) from public.sites where building_code = 'RLS-B') <> 0 then
    raise exception 'unassigned cross-organization site leaked through RLS';
  end if;
  if (
    select count(*) from public.organizations
    where id = '91000000-0000-4000-8000-000000000002'
  ) <> 0 then
    raise exception 'cross-organization row leaked through RLS';
  end if;
  if (
    select count(*) from public.profiles
    where id = '94000000-0000-4000-8000-000000000001'
  ) <> 1 then
    raise exception 'user cannot read their own profile';
  end if;
  if (
    select count(*) from public.profiles
    where id = '94000000-0000-4000-8000-000000000002'
  ) <> 0 then
    raise exception 'unrelated profile leaked through RLS';
  end if;

  update public.profiles
  set full_name = 'RLS Technician Updated'
  where id = '94000000-0000-4000-8000-000000000001';
  if not found then
    raise exception 'safe self profile update was blocked';
  end if;

  begin
    update public.profiles
    set role = 'super_admin'
    where id = '94000000-0000-4000-8000-000000000001';
    raise exception 'role escalation through profile update unexpectedly worked';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform public.admin_create_user(
      'legacy-rpc@example.test', 'not-a-real-password', 'Legacy RPC'
    );
    raise exception 'legacy direct-auth RPC remained executable';
  exception
    when insufficient_privilege then null;
  end;

  v_inspection_id := public.create_checklist_inspection_draft(
    '93000000-0000-4000-8000-000000000001',
    public.current_business_date(),
    'RLS Technician',
    '08:00',
    'ALL',
    '[]'::jsonb,
    'rls-role-smoke'
  );
  if not exists (
    select 1 from public.checklist_inspections where id = v_inspection_id
  ) then
    raise exception 'authorized RPC result is not visible to its technician';
  end if;
end;
$$;

reset role;
set local role anon;

do $$
begin
  if has_table_privilege('anon', 'public.organizations', 'select') then
    raise exception 'anon unexpectedly has organization SELECT';
  end if;
  begin
    perform 1 from public.organizations limit 1;
    raise exception 'anon organization read unexpectedly worked';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

reset role;
rollback;
