do $$
declare
  v_technician uuid := '10000000-0000-4000-8000-000000000001';
  v_manager uuid := '10000000-0000-4000-8000-000000000002';
  v_site_id uuid;
  v_org_id uuid;
  v_inspection_id uuid;
  v_item_id uuid;
  v_signature_path text;
  v_photo_path text;
  v_items jsonb;
  v_items_without_photo jsonb;
  v_version bigint;
  v_theme_key text;
  v_theme_source text;
begin
  select site.id, site.organization_id
  into v_site_id, v_org_id
  from public.sites site
  join public.checklist_templates template
    on template.code = site.checklist_type
   and template.is_active = true
  where site.is_active = true
    and site.building_code is not null
  order by site.created_at
  limit 1;

  if v_site_id is null then
    raise exception 'smoke test requires an active checklist site';
  end if;

  insert into auth.users (id, email, raw_user_meta_data)
  values
    (v_technician, 'migration-tech@example.test', '{"full_name":"Tech"}'),
    (v_manager, 'migration-manager@example.test', '{"full_name":"Manager"}');

  update public.profiles
  set role = 'technician', is_active = true, approval_status = 'approved'
  where id = v_technician;
  update public.profiles
  set role = 'site_admin', is_active = true, approval_status = 'approved'
  where id = v_manager;

  insert into public.user_site_access (
    user_id, site_id, role, can_read, can_write, can_manage
  )
  values
    (v_technician, v_site_id, 'technician', true, true, false),
    (v_manager, v_site_id, 'site_admin', true, true, true);

  -- Hierarchical theme smoke: inherited site/zone resolves from organization.
  update public.organizations
  set form_theme = 'custom', form_theme_accent = '#123456'
  where id = v_org_id;

  perform set_config('request.jwt.claim.sub', v_technician::text, false);
  select resolved.theme_key, resolved.source_scope
  into v_theme_key, v_theme_source
  from public.resolve_checklist_form_themes(array[v_site_id]) resolved;
  if v_theme_key <> 'custom' or v_theme_source <> 'organization' then
    raise exception 'unexpected inherited theme: % from %',
      v_theme_key, v_theme_source;
  end if;

  update public.checklist_templates template
  set lifecycle_status = 'draft'
  from public.sites site
  where site.id = v_site_id
    and template.code = site.checklist_type;
  update public.checklist_templates template
  set form_theme = 'teal', form_theme_accent = null
  from public.sites site
  where site.id = v_site_id
    and template.code = site.checklist_type;
  update public.checklist_templates template
  set lifecycle_status = 'published'
  from public.sites site
  where site.id = v_site_id
    and template.code = site.checklist_type;
  select resolved.theme_key, resolved.source_scope
  into v_theme_key, v_theme_source
  from public.resolve_checklist_form_themes(array[v_site_id]) resolved;
  if v_theme_key <> 'teal' or v_theme_source <> 'template' then
    raise exception 'unexpected list-type theme: % from %',
      v_theme_key, v_theme_source;
  end if;

  begin
    perform public.create_checklist_inspection_draft(
      v_site_id,
      public.current_business_date() + 1,
      'Future date must fail',
      '08:00',
      'ALL',
      '[]'::jsonb,
      'migration-future-date-smoke'
    );
    raise exception 'future inspection date unexpectedly succeeded';
  exception
    when others then
      if sqlerrm <> 'future inspection dates are not allowed' then
        raise;
      end if;
  end;

  v_inspection_id := public.create_checklist_inspection_draft(
    v_site_id,
    public.current_business_date(),
    'Migration technician',
    '08:00',
    'ALL',
    '[]'::jsonb,
    'migration-workflow-smoke'
  );

  v_signature_path := v_org_id::text || '/' || v_site_id::text || '/'
    || v_inspection_id::text || '/signature.png';
  insert into storage.objects (bucket_id, name)
  values ('checklist-media', v_signature_path);

  select jsonb_agg(jsonb_build_object(
    'item_index', item.item_index,
    'response', case when item.default_answer = 'N' then 'no' else 'yes' end,
    'is_custom', item.is_custom
  ) order by item.item_index)
  into v_items
  from public.checklist_inspection_items item
  where item.inspection_id = v_inspection_id;

  v_version := public.save_checklist_inspection(
    v_inspection_id,
    1,
    jsonb_build_object('signature_path', v_signature_path),
    v_items
  );
  if v_version <> 2 then
    raise exception 'unexpected version after save: %', v_version;
  end if;

  if public.can_delete_checklist_media(v_signature_path) then
    raise exception 'technician could delete stored draft evidence';
  end if;

  begin
    perform public.save_checklist_inspection(
      v_inspection_id,
      v_version,
      jsonb_build_object('signature_path', null),
      v_items
    );
    raise exception 'technician removed stored signature evidence';
  exception
    when others then
      if sqlerrm <> 'stored signature evidence is part of inspection history and cannot be removed' then
        raise;
      end if;
  end;

  begin
    perform public.owner_change_inspection_date(
      v_inspection_id,
      v_version,
      public.current_business_date() - 1,
      'technician must not change dates'
    );
    raise exception 'technician changed inspection date';
  exception
    when others then
      if sqlerrm <> 'only the platform owner can change an inspection date' then
        raise;
      end if;
  end;

  v_photo_path := v_org_id::text || '/' || v_site_id::text || '/'
    || v_inspection_id::text || '/issue-smoke.jpg';
  insert into storage.objects (bucket_id, name)
  values ('checklist-media', v_photo_path);
  v_items := jsonb_set(v_items, '{0,issue_image_path}', to_jsonb(v_photo_path));
  v_version := public.save_checklist_inspection(
    v_inspection_id,
    v_version,
    jsonb_build_object('signature_path', v_signature_path),
    v_items
  );
  if v_version <> 3 then
    raise exception 'unexpected version after evidence save: %', v_version;
  end if;

  v_items_without_photo := jsonb_set(
    v_items,
    '{0,issue_image_path}',
    'null'::jsonb
  );
  begin
    perform public.save_checklist_inspection(
      v_inspection_id,
      v_version,
      jsonb_build_object('signature_path', v_signature_path),
      v_items_without_photo
    );
    raise exception 'technician removed stored photo evidence';
  exception
    when others then
      if sqlerrm <> 'stored photo evidence is part of inspection history and cannot be removed' then
        raise;
      end if;
  end;

  v_version := public.submit_checklist_inspection(v_inspection_id, v_version);
  if v_version <> 4 then
    raise exception 'unexpected version after submit: %', v_version;
  end if;

  perform set_config('request.jwt.claim.sub', v_manager::text, false);
  if public.can_delete_checklist_media(v_signature_path) then
    raise exception 'site manager could delete referenced historical evidence';
  end if;
  begin
    perform public.save_checklist_inspection(
      v_inspection_id,
      v_version,
      jsonb_build_object('signature_path', null),
      v_items
    );
    raise exception 'site manager detached stored signature evidence';
  exception
    when others then
      if sqlerrm <>
        'stored signature evidence is part of inspection history and cannot be removed' then
        raise;
      end if;
  end;
  v_version := public.admin_approve_inspection(v_inspection_id, v_version);
  if v_version <> 5 then
    raise exception 'unexpected version after approval: %', v_version;
  end if;
  if public.can_write_checklist_media(v_signature_path) then
    raise exception 'approved inspection media remained writable';
  end if;
  if public.can_delete_checklist_media(v_signature_path) then
    raise exception 'approved inspection media remained deletable';
  end if;
  if not public.can_read_checklist_media(v_signature_path) then
    raise exception 'approved inspection media is not readable in scope';
  end if;
  if public.storage_path_inspection_id('malformed/path') is not null then
    raise exception 'malformed storage path was accepted';
  end if;

  select item.id
  into v_item_id
  from public.checklist_inspection_items item
  where item.inspection_id = v_inspection_id
  order by item.item_index
  limit 1;

  begin
    perform public.correct_checklist_inspection_item(
      v_item_id, v_version, 'actions_taken', 'forbidden', 'smoke test'
    );
    raise exception 'approved inspection correction unexpectedly succeeded';
  exception
    when others then
      if sqlerrm <> 'approved inspections are immutable' then
        raise;
      end if;
  end;

  begin
    perform public.delete_checklist_inspection(v_inspection_id, v_version);
    raise exception 'approved inspection deletion unexpectedly succeeded';
  exception
    when others then
      if sqlerrm <> 'approved inspections are immutable' then
        raise;
      end if;
  end;

  if not exists (
    select 1
    from public.checklist_audit_log audit
    where audit.entity_type = 'inspection'
      and audit.entity_id = v_inspection_id::text
      and audit.action = 'inspection.approved'
  ) then
    raise exception 'approval audit event was not recorded';
  end if;
end;
$$;

do $$
declare
  v_technician uuid := '10000000-0000-4000-8000-000000000001';
  v_manager uuid := '10000000-0000-4000-8000-000000000002';
  v_site_id uuid;
  v_org_id uuid;
  v_inspection_id uuid;
  v_version bigint;
  v_path text;
  v_orphan_path text;
  v_deleted_paths text[];
begin
  if exists (
    select 1 from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'checklist_media_update'
  ) then
    raise exception 'checklist evidence objects are still mutable';
  end if;

  select site.id, site.organization_id
  into v_site_id, v_org_id
  from public.sites site
  where site.is_active = true
    and site.building_code is not null
  order by site.id
  limit 1;

  insert into public.user_site_access (
    user_id, site_id, role, can_read, can_write, can_manage
  ) values (
    v_manager, v_site_id, 'site_admin', true, true, true
  ) on conflict (user_id, site_id) do update set
    can_read = true, can_write = true, can_manage = true;
  insert into public.user_site_access (
    user_id, site_id, role, can_read, can_write, can_manage
  ) values (
    v_technician, v_site_id, 'technician', true, true, false
  ) on conflict (user_id, site_id) do update set
    can_read = true, can_write = true;

  perform set_config('request.jwt.claim.sub', v_technician::text, false);
  v_inspection_id := public.create_checklist_reinspection_draft(
    v_site_id,
    public.current_business_date(),
    'Immutable cleanup smoke',
    '10:00',
    'ALL',
    '[]'::jsonb,
    'immutable-cleanup-smoke',
    'Cleanup lifecycle smoke test'
  );
  select version into v_version
  from public.checklist_inspections
  where id = v_inspection_id;

  v_path := v_org_id::text || '/' || v_site_id::text || '/'
    || v_inspection_id::text || '/signature_0123456789abcdef.png';
  v_orphan_path := v_org_id::text || '/' || v_site_id::text || '/'
    || v_inspection_id::text || '/photo_orphan_0123456789abcdef.jpg';
  insert into storage.objects (bucket_id, name)
  values ('checklist-media', v_orphan_path);
  if not public.can_delete_checklist_media(v_orphan_path) then
    raise exception 'technician could not clean an unreferenced failed upload';
  end if;
  delete from storage.objects
  where bucket_id = 'checklist-media' and name = v_orphan_path;

  insert into storage.objects (bucket_id, name)
  values ('checklist-media', v_path);
  perform public.register_checklist_media_evidence(
    v_inspection_id, null, v_path, 'signature'
  );

  update public.profiles
  set role = 'super_admin', home_organization_id = v_org_id
  where id = v_manager;
  perform set_config('request.jwt.claim.sub', v_manager::text, false);
  v_deleted_paths := public.delete_checklist_inspection_with_cleanup(
    v_inspection_id, v_version
  );
  if not (v_path = any(v_deleted_paths)) then
    raise exception 'delete cleanup did not return registered evidence';
  end if;
  if exists (
    select 1 from public.checklist_inspections where id = v_inspection_id
  ) then
    raise exception 'authorized draft was not deleted';
  end if;
  if not public.can_delete_checklist_media(v_path) then
    raise exception 'cleanup authorization was not created';
  end if;
  if not (v_path = any(public.list_my_pending_checklist_media_cleanup())) then
    raise exception 'pending cleanup path was not recoverable by the requester';
  end if;

  delete from storage.objects
  where bucket_id = 'checklist-media' and name = v_path;
  perform public.complete_checklist_media_cleanup(array[v_path]);
  if public.can_delete_checklist_media(v_path) then
    raise exception 'completed cleanup authorization remained active';
  end if;
  if cardinality(public.list_my_pending_checklist_media_cleanup()) <> 0 then
    raise exception 'completed cleanup path remained in the pending list';
  end if;
  update public.profiles
  set role = 'site_admin'
  where id = v_manager;
end;
$$;

-- Temporary grants must stop authorizing immediately after expiry. The test
-- restores the fixture so it remains independent from later smoke assertions.
do $$
declare
  v_technician uuid := '10000000-0000-4000-8000-000000000001';
  v_site_id uuid;
begin
  select site_id
  into v_site_id
  from public.user_site_access
  where user_id = v_technician
    and can_read
  order by site_id
  limit 1;

  if v_site_id is null then
    raise exception 'temporary access smoke requires a technician grant';
  end if;

  update public.user_site_access
  set valid_from = now() - interval '2 days',
      valid_until = now() - interval '1 day'
  where user_id = v_technician;

  perform set_config('request.jwt.claim.sub', v_technician::text, false);
  if public.has_site_access(v_site_id) then
    raise exception 'expired site grant still authorizes read access';
  end if;
  if public.can_write_site(v_site_id) then
    raise exception 'expired site grant still authorizes write access';
  end if;

  update public.user_site_access
  set valid_from = null,
      valid_until = null
  where user_id = v_technician;

  insert into public.client_error_logs (
    user_id, app_key, app_version, build_number, platform, module,
    error_type, error_message, stack_summary
  ) values (
    v_technician, 'smoke', '1.0.0', '1', 'postgres', 'migration',
    'SmokeError', 'sanitized smoke event', 'workflow_smoke.sql'
  );

  if not exists (
    select 1 from public.client_error_logs
    where user_id = v_technician and app_key = 'smoke'
  ) then
    raise exception 'structured client error log was not stored';
  end if;
end;
$$;

do $$
declare
  v_technician uuid := '10000000-0000-4000-8000-000000000001';
  v_manager uuid := '10000000-0000-4000-8000-000000000002';
  v_site_id uuid;
  v_org_id uuid;
  v_inspection_id uuid;
  v_item_id uuid;
  v_action_id uuid;
  v_signature_path text;
  v_evidence_path text;
  v_items jsonb;
  v_version bigint;
  v_action_version bigint;
  v_reference text;
begin
  select site.id, site.organization_id
  into v_site_id, v_org_id
  from public.sites site
  join public.checklist_templates template
    on template.code = site.checklist_type
  where site.is_active and nullif(trim(site.building_code), '') is not null
  order by site.created_at
  limit 1;

  perform set_config('request.jwt.claim.sub', v_technician::text, false);
  v_inspection_id := public.create_checklist_reinspection_draft(
    v_site_id,
    public.current_business_date(),
    'Corrective action smoke',
    '10:00',
    'ALL',
    '[]'::jsonb,
    'migration-corrective-action-smoke',
    'Verification of controlled same-day reinspection'
  );

  select inspection.reference_no
  into v_reference
  from public.checklist_inspections inspection
  where inspection.id = v_inspection_id
    and inspection.template_id is not null
    and inspection.template_version_snapshot = 1;
  if nullif(trim(v_reference), '') is null then
    raise exception 'inspection stable reference/template snapshot was not assigned';
  end if;

  v_signature_path := v_org_id::text || '/' || v_site_id::text || '/'
    || v_inspection_id::text || '/signature.png';
  insert into storage.objects (bucket_id, name)
  values ('checklist-media', v_signature_path);

  select jsonb_agg(jsonb_build_object(
    'item_index', item.item_index,
    'response', case
      when item.row_no = 1
        then case when item.default_answer = 'N' then 'yes' else 'no' end
      when item.default_answer = 'N' then 'no'
      else 'yes'
    end,
    'is_custom', item.is_custom
  ) order by item.item_index)
  into v_items
  from (
    select source.*,
           row_number() over (order by source.item_index) as row_no
    from public.checklist_inspection_items source
    where source.inspection_id = v_inspection_id
  ) item;

  v_version := public.save_checklist_inspection(
    v_inspection_id,
    1,
    jsonb_build_object('signature_path', v_signature_path),
    v_items
  );
  select item.id into v_item_id
  from public.checklist_inspection_items item
  where item.inspection_id = v_inspection_id
  order by item.item_index
  limit 1;

  v_reference := public.register_checklist_media_evidence(
    v_inspection_id, null, v_signature_path, 'signature'
  );
  if v_reference <> 'SIG' then
    raise exception 'unexpected signature evidence reference: %', v_reference;
  end if;

  v_action_id := public.create_corrective_action(
    v_item_id,
    'Repair and verify the failed checklist item',
    v_technician,
    'critical',
    public.current_business_date() + 1,
    true
  );
  v_action_version := public.transition_corrective_action(
    v_action_id, 1, 'start', 'Work started'
  );
  begin
    perform public.transition_corrective_action(
      v_action_id, v_action_version, 'request_close', 'Repair completed'
    );
    raise exception 'critical action closed without evidence';
  exception when others then
    if sqlerrm <> 'evidence is required before closing this corrective action' then
      raise;
    end if;
  end;

  v_evidence_path := v_org_id::text || '/' || v_site_id::text || '/'
    || v_inspection_id::text || '/action-' || v_action_id::text || '.jpg';
  insert into storage.objects (bucket_id, name)
  values ('checklist-media', v_evidence_path);
  v_reference := public.register_corrective_action_evidence(
    v_action_id, v_evidence_path, 'action_photo'
  );
  if v_reference not like 'CA-%' then
    raise exception 'unexpected corrective action evidence reference: %', v_reference;
  end if;
  v_action_version := public.transition_corrective_action(
    v_action_id, v_action_version, 'request_close', 'Evidence attached'
  );

  perform set_config('request.jwt.claim.sub', v_manager::text, false);
  v_action_version := public.transition_corrective_action(
    v_action_id, v_action_version, 'close', 'Verified by site manager'
  );
  if v_action_version <> 4 then
    raise exception 'unexpected corrective action version: %', v_action_version;
  end if;
  if not exists (
    select 1 from public.checklist_audit_log audit
    where audit.entity_type = 'corrective_action'
      and audit.entity_id = v_action_id::text
  ) then
    raise exception 'corrective action audit trail was not recorded';
  end if;
  if not exists (
    select 1 from public.checklist_notifications notice
    where notice.user_id = v_technician
      and notice.kind = 'corrective_action_assigned'
      and notice.inspection_id = v_inspection_id
  ) then
    raise exception 'corrective action assignment notification was not recorded';
  end if;
end;
$$;

do $$
declare
  v_count int;
begin
  select count(*)
  into v_count
  from public.checklist_template_items item
  join public.checklist_templates template on template.id = item.template_id
  where template.code = 'B7_MECH'
    and item.is_active = true
    and item.description_en is not null
    and item.description_ar is not null
    and item.description_bn is not null
    and item.description_hi is not null
    and item.description_ml is not null
    and item.description_tl is not null
    and item.description_ta is not null;
  if v_count <> 22 then
    raise exception 'B7_MECH expected 22 complete multilingual items, found %',
      v_count;
  end if;

  select count(*)
  into v_count
  from public.checklist_inspection_items
  where inspection_id = '25000000-0000-4000-8000-000000000001';
  if v_count <> 22 then
    raise exception 'untouched B7-M draft was not refreshed: % items', v_count;
  end if;

  select count(*)
  into v_count
  from public.checklist_inspection_items
  where inspection_id = '25000000-0000-4000-8000-000000000002'
    and response = 'yes';
  if v_count <> 1 then
    raise exception 'answered B7-M draft was modified';
  end if;

  select count(*)
  into v_count
  from public.sites site
  where upper(trim(site.building_code)) = 'B7-M'
    and site.is_active = true
    and site.checklist_type <> 'B7_MECH';
  if v_count <> 0 then
    raise exception 'B7-M site binding was not repaired';
  end if;

  select count(*)
  into v_count
  from public.checklist_inspection_items item
  join public.checklist_template_items template_item
    on template_item.item_index = item.item_index
  join public.checklist_templates template
    on template.id = template_item.template_id
   and template.code = 'B7_MECH'
  where item.inspection_id = '26000000-0000-4000-8000-000000000001'
    and template_item.is_active = true
    and item.description = template_item.description_en
    and item.description_ar = template_item.description_ar;
  if v_count <> 22 then
    raise exception 'wrong-bound untouched B7-M draft was not repaired: % items',
      v_count;
  end if;

  select count(*)
  into v_count
  from public.checklist_inspection_items
  where inspection_id = '26000000-0000-4000-8000-000000000002';
  if v_count <> 19 then
    raise exception 'wrong-bound answered B7-M draft item count changed: %',
      v_count;
  end if;

  select count(*)
  into v_count
  from public.checklist_inspection_items
  where inspection_id = '26000000-0000-4000-8000-000000000002'
    and response = 'yes';
  if v_count <> 1 then
    raise exception 'wrong-bound answered B7-M response was modified';
  end if;
end;
$$;

do $$
declare
  v_technician uuid := '10000000-0000-4000-8000-000000000001';
  v_site_id uuid;
  v_inspection_id uuid;
  v_count int;
begin
  select site.id
  into v_site_id
  from public.sites site
  where site.checklist_type = 'AWQAF_MEN_PRAYER'
    and site.is_active = true
  order by site.id
  limit 1;

  if v_site_id is null then
    raise exception 'Awqaf translation smoke requires a prayer-hall site';
  end if;

  insert into public.user_site_access (
    user_id, site_id, role, can_read, can_write, can_manage
  )
  values (v_technician, v_site_id, 'technician', true, true, false)
  on conflict (user_id, site_id) do update set
    can_read = true,
    can_write = true;

  perform set_config('request.jwt.claim.sub', v_technician::text, false);
  v_inspection_id := public.create_checklist_inspection_draft(
    v_site_id,
    public.current_business_date(),
    'Awqaf multilingual smoke',
    '09:00',
    'ALL',
    '[]'::jsonb,
    'migration-awqaf-translation-smoke'
  );

  select count(*)
  into v_count
  from public.checklist_inspection_items item
  where item.inspection_id = v_inspection_id
    and item.description_bn is not null
    and item.description_hi is not null
    and item.description_ml is not null
    and item.description_tl is not null
    and item.description_ta is not null;
  if v_count <> 24 then
    raise exception 'Awqaf draft expected 24 translated snapshots, found %',
      v_count;
  end if;
end;
$$;

do $$
declare
  v_code text;
  v_count int;
begin
  select count(*)
  into v_count
  from public.checklist_inspection_items
  where inspection_id = '24000000-0000-4000-8000-000000000001';
  if v_count <> 24 then
    raise exception 'untouched stale Awqaf draft was not refreshed: % items',
      v_count;
  end if;

  select count(*)
  into v_count
  from public.checklist_inspection_items
  where inspection_id = '24000000-0000-4000-8000-000000000002'
    and response = 'yes';
  if v_count <> 1 then
    raise exception 'answered stale Awqaf draft was modified';
  end if;

  foreach v_code in array array[
    'AWQAF_MEN_PRAYER',
    'AWQAF_WUDU',
    'AWQAF_IMAM_HOUSE'
  ] loop
    select count(*)
    into v_count
    from public.checklist_template_items item
    join public.checklist_templates template on template.id = item.template_id
    where template.code = v_code
      and item.is_active = true
      and item.description_en is not null
      and item.description_ar is not null
      and item.description_bn is not null
      and item.description_hi is not null
      and item.description_ml is not null
      and item.description_tl is not null
      and item.description_ta is not null;
    if v_count <> 24 then
      raise exception '% expected 24 complete multilingual items, found %',
        v_code, v_count;
    end if;
  end loop;

  if not exists (
    select 1
    from pg_trigger
    where tgname = 'checklist_items_populate_translations'
      and not tgisinternal
  ) then
    raise exception 'inspection translation snapshot trigger is missing';
  end if;
end;
$$;
