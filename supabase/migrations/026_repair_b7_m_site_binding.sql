-- Repair B7-M sites that were accidentally assigned the Building 4 template.
-- Scope by the immutable/displayed building code, not the incorrect template.

update public.sites site
set checklist_type = 'B7_MECH',
    updated_at = now()
where site.is_active = true
  and (
    upper(trim(site.building_code)) = 'B7-M'
    or site.id = 'a0000000-0000-4000-8000-000000000109'::uuid
  )
  and site.checklist_type is distinct from 'B7_MECH';

do $$
declare
  draft_row record;
  v_template_id uuid;
  v_template_max_index integer;
  refreshed_count integer := 0;
begin
  select template.id
  into strict v_template_id
  from public.checklist_templates template
  where template.code = 'B7_MECH'
    and template.is_active = true;

  for draft_row in
    select inspection.id, inspection.site_id
    from public.checklist_inspections inspection
    join public.sites site on site.id = inspection.site_id
    where inspection.status = 'draft'
      and inspection.review_status = 'draft'
      and (
        upper(trim(site.building_code)) = 'B7-M'
        or site.id = 'a0000000-0000-4000-8000-000000000109'::uuid
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
        (
          select count(*)
          from public.checklist_inspection_items item
          where item.inspection_id = inspection.id
        ) <> 22 + (
          select count(*)
          from public.site_checklist_items item
          where item.site_id = inspection.site_id
            and item.is_active = true
        )
        or exists (
          select 1
          from public.checklist_inspection_items snapshot
          left join public.checklist_template_items template_item
            on template_item.template_id = v_template_id
           and template_item.item_index = snapshot.item_index
           and template_item.is_active = true
          where snapshot.inspection_id = inspection.id
            and snapshot.is_custom = false
            and (
              template_item.id is null
              or snapshot.description is distinct from template_item.description_en
              or snapshot.description_ar is distinct from template_item.description_ar
            )
        )
      )
    for update of inspection
  loop
    delete from public.checklist_inspection_items item
    where item.inspection_id = draft_row.id;

    insert into public.checklist_inspection_items (
      inspection_id, item_index, description, description_ar,
      default_answer, is_custom, overdue_after_days
    )
    select
      draft_row.id, item.item_index, item.description_en, item.description_ar,
      item.default_answer, false, item.overdue_after_days
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
      inspection_id, item_index, description, description_ar,
      default_answer, is_custom, overdue_after_days
    )
    select
      draft_row.id,
      (v_template_max_index + row_number() over (
        order by item.sort_order, item.item_index, item.id
      ))::integer,
      item.description_en, item.description_ar,
      item.default_answer, true, item.overdue_after_days
    from public.site_checklist_items item
    where item.site_id = draft_row.site_id
      and item.is_active = true;

    update public.checklist_inspections inspection
    set version = inspection.version + 1,
        updated_at = now()
    where inspection.id = draft_row.id;

    refreshed_count := refreshed_count + 1;
  end loop;

  raise notice 'Repaired % untouched B7-M draft(s)', refreshed_count;
end;
$$;
