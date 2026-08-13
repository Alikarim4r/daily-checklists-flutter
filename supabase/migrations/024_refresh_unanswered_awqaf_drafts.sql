-- Refresh only untouched Awqaf drafts that still snapshot an older catalog.
-- Answered/submitted/signed drafts are immutable and remain available for audit.

do $$
declare
  draft_row record;
  v_template_id uuid;
  v_template_max_index integer;
  refreshed_count integer := 0;
begin
  for draft_row in
    select inspection.id, inspection.site_id, site.checklist_type
    from public.checklist_inspections inspection
    join public.sites site on site.id = inspection.site_id
    where inspection.status = 'draft'
      and inspection.review_status = 'draft'
      and site.checklist_type in (
        'AWQAF_MEN_PRAYER',
        'AWQAF_WUDU',
        'AWQAF_IMAM_HOUSE'
      )
      and nullif(trim(inspection.signature_path), '') is null
      and not exists (
        select 1
        from public.checklist_inspection_items item
        where item.inspection_id = inspection.id
          and (
            item.response is not null
            or nullif(trim(item.actions_taken), '') is not null
            or nullif(trim(item.image_path), '') is not null
            or nullif(trim(item.issue_image_path), '') is not null
            or nullif(trim(item.fix_image_path), '') is not null
          )
      )
      and (
        select count(*)
        from public.checklist_inspection_items item
        where item.inspection_id = inspection.id
      ) <> (
        select count(*)
        from public.checklist_templates template
        join public.checklist_template_items item
          on item.template_id = template.id
         and item.is_active = true
        where template.code = site.checklist_type
          and template.is_active = true
      ) + (
        select count(*)
        from public.site_checklist_items item
        where item.site_id = inspection.site_id
          and item.is_active = true
      )
    for update of inspection
  loop
    select template.id
    into strict v_template_id
    from public.checklist_templates template
    where template.code = draft_row.checklist_type
      and template.is_active = true;

    delete from public.checklist_inspection_items item
    where item.inspection_id = draft_row.id;

    insert into public.checklist_inspection_items (
      inspection_id,
      item_index,
      description,
      description_ar,
      default_answer,
      is_custom,
      overdue_after_days
    )
    select
      draft_row.id,
      item.item_index,
      item.description_en,
      item.description_ar,
      item.default_answer,
      false,
      item.overdue_after_days
    from public.checklist_template_items item
    where item.template_id = v_template_id
      and item.is_active = true
    order by item.item_index;

    select coalesce(max(item.item_index), 0)
    into v_template_max_index
    from public.checklist_template_items item
    where item.template_id = v_template_id
      and item.is_active = true;

    insert into public.checklist_inspection_items (
      inspection_id,
      item_index,
      description,
      description_ar,
      default_answer,
      is_custom,
      overdue_after_days
    )
    select
      draft_row.id,
      (
        v_template_max_index
        + row_number() over (
          order by item.sort_order, item.item_index, item.id
        )
      )::integer,
      item.description_en,
      item.description_ar,
      item.default_answer,
      true,
      item.overdue_after_days
    from public.site_checklist_items item
    where item.site_id = draft_row.site_id
      and item.is_active = true;

    update public.checklist_inspections inspection
    set version = inspection.version + 1,
        updated_at = now()
    where inspection.id = draft_row.id;

    refreshed_count := refreshed_count + 1;
  end loop;

  raise notice 'Refreshed % untouched Awqaf draft(s)', refreshed_count;
end;
$$;
