-- GLOB-001 P1-03: scoped, versioned global catalog API.
-- Preserve public.list_checklist_library(uuid) and every existing client.
-- This endpoint only returns catalog metadata. Never return item bodies.
-- Metadata may include locked templates, but can_access reflects entitlement.
revoke all on public.library_taxonomy_terms from anon;
revoke all on public.library_document_kinds from anon;
revoke all on public.library_template_classification from anon;
revoke all on public.library_template_taxonomy from anon;
revoke all on public.library_template_jurisdiction from anon;
revoke all on public.library_template_locales from anon;

grant select, insert, update, delete on
  public.library_taxonomy_terms,
  public.library_document_kinds,
  public.library_template_classification,
  public.library_template_taxonomy,
  public.library_template_jurisdiction,
  public.library_template_locales
to authenticated;

create or replace function public.list_global_library_v2(
  p_organization_id uuid,
  p_sector text default null,
  p_domain text default null,
  p_kind text default null,
  p_search text default null,
  p_limit integer default 100,
  p_offset integer default 0,
  p_category text default null
)
returns setof jsonb
language plpgsql stable
security definer
set search_path = public
as $$
declare
  v_limit integer := least(greatest(coalesce(p_limit,100),1),100);
  v_offset integer := least(greatest(coalesce(p_offset,0),0),100000);
  v_search text := nullif(trim(coalesce(p_search,'')),'');
begin
  if auth.uid() is null
    or (not coalesce(public.is_platform_owner(),false) and
      (not coalesce(public.is_approved_active_user(),false)
       or p_organization_id is null
       or not public.can_access_organization(p_organization_id)))
  then
    raise exception 'not authorized to browse this organization library'
      using errcode='42501';
  end if;
  return query
  select jsonb_build_object(
    'id',t.id,
    'category_id',t.category_id,
    'category_slug',c.slug,
    'category_name_en',c.name_en,
    'category_name_ar',c.name_ar,
    'slug',t.slug,
    'version_number',t.version_number,
    'name_en',t.name_en,
    'name_ar',t.name_ar,
    'description_en',t.description_en,
    'description_ar',t.description_ar,
    'facility_tags',to_jsonb(t.facility_tags),
    'languages',to_jsonb(t.languages),
    'access_model',t.access_model,
    'minimum_plan_tier',t.minimum_plan_tier,
    'google_play_product_id',t.google_play_product_id,
    'list_price_minor',t.list_price_minor,
    'list_price_currency',t.list_price_currency,
    'form_theme',t.form_theme,
    'form_theme_accent',t.form_theme_accent,
    'item_count',(
      select count(*)
      from public.checklist_library_template_items li
      where li.library_template_id=t.id and li.is_active
    ),
    'can_access',public.can_access_library_template(t.id,p_organization_id),
    'installed_template_id',install.installed_template_id,
    'installed_library_version',install.library_version,
    'document_kind',coalesce(cl.document_kind,'checklist'),
    'document_kind_name_en',coalesce(k.name_en,'Checklist'),
    'document_kind_name_ar',coalesce(k.name_ar,'قائمة فحص'),
    'validation_status',coalesce(cl.validation_status,'unreviewed'),
    'frequency_hint',cl.frequency_hint,
    'industries',coalesce((
      select jsonb_agg(
        jsonb_build_object('slug',x.slug,'name_en',x.name_en,'name_ar',x.name_ar)
        order by x.sort_order,x.name_en
      )
      from public.library_template_taxonomy tm
      join public.library_taxonomy_terms x on x.id=tm.term_id
      where tm.template_id=t.id and x.dimension='industry' and x.is_active
    ),'[]'::jsonb),
    'domains',coalesce((
      select jsonb_agg(
        jsonb_build_object('slug',x.slug,'name_en',x.name_en,'name_ar',x.name_ar)
        order by x.sort_order,x.name_en
      )
      from public.library_template_taxonomy tm
      join public.library_taxonomy_terms x on x.id=tm.term_id
      where tm.template_id=t.id and x.dimension in ('domain','subdomain') and x.is_active
    ),'[]'::jsonb)
  )
  from public.checklist_library_templates t
  join public.checklist_library_categories c on c.id=t.category_id and c.is_active
  left join public.library_template_classification cl on cl.template_id=t.id
  left join public.library_document_kinds k on k.kind_code=cl.document_kind
  left join lateral (
    select oi.installed_template_id,oi.library_version
    from public.organization_library_installs oi
    where oi.organization_id=p_organization_id
      and oi.library_template_id=t.id
    order by oi.library_version desc,oi.installed_at desc
    limit 1
  ) install on true
  where t.is_published
    and (p_category is null or p_category='' or c.slug=p_category)
    and (p_kind is null or p_kind=''
      or coalesce(cl.document_kind,'checklist')=p_kind)
    and (v_search is null
      or t.name_en ilike ('%'||v_search||'%')
      or t.name_ar ilike ('%'||v_search||'%')
      or c.name_en ilike ('%'||v_search||'%')
      or c.name_ar ilike ('%'||v_search||'%')
      or t.slug ilike ('%'||v_search||'%')
      or exists (
        select 1 from unnest(t.facility_tags) tag
        where tag ilike ('%'||v_search||'%')
      )
      or exists (
        select 1 from public.library_template_taxonomy tt
        join public.library_taxonomy_terms term on term.id=tt.term_id
        where tt.template_id=t.id and term.is_active
          and (term.name_en ilike ('%'||v_search||'%')
            or term.name_ar ilike ('%'||v_search||'%')
            or term.slug ilike ('%'||v_search||'%'))
      ))
    and (p_sector is null or p_sector='' or exists(
      select 1 from public.library_template_taxonomy tm
      join public.library_taxonomy_terms x on x.id=tm.term_id
      where tm.template_id=t.id and x.dimension='industry'
        and x.slug=p_sector and x.is_active
    ))
    and (p_domain is null or p_domain='' or exists(
      select 1 from public.library_template_taxonomy tm
      join public.library_taxonomy_terms x on x.id=tm.term_id
      where tm.template_id=t.id and x.dimension in ('domain','subdomain')
        and x.slug=p_domain and x.is_active
    ))
  order by c.sort_order,t.sort_order,t.name_en,t.id
  limit v_limit offset v_offset;
end;
$$;
revoke all on function public.list_global_library_v2(uuid,text,text,text,text,integer,integer,text)
  from public,anon;
grant execute on function public.list_global_library_v2(uuid,text,text,text,text,integer,integer,text)
  to authenticated;

-- Query taxonomy terms without exposing paid item bodies; for server-side
-- filter choices a caller must be approved and belong to the selected org.
create or replace function public.list_global_library_facets_v2(
  p_organization_id uuid
)
returns table (
  dimension text,
  slug text,
  name_en text,
  name_ar text,
  template_count bigint
)
language plpgsql stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null
    or (not coalesce(public.is_platform_owner(),false) and
      (not coalesce(public.is_approved_active_user(),false)
        or p_organization_id is null
        or not public.can_access_organization(p_organization_id)))
  then
    raise exception 'not authorized to browse library facets'
      using errcode='42501';
  end if;
  return query
  select x.dimension,x.slug,x.name_en,x.name_ar,
         count(distinct tm.template_id) as template_count
  from public.library_taxonomy_terms x
  join public.library_template_taxonomy tm on tm.term_id=x.id
  join public.checklist_library_templates t on t.id=tm.template_id
  join public.checklist_library_categories c on c.id=t.category_id
  where x.is_active and t.is_published and c.is_active
    and x.dimension in ('industry','domain','subdomain')
  group by x.dimension,x.slug,x.name_en,x.name_ar,x.sort_order
  having count(distinct tm.template_id)>0
  order by x.dimension,x.sort_order,x.name_en;

  return query
  select 'category'::text,c.slug,c.name_en,c.name_ar,
         count(distinct t.id) as template_count
  from public.checklist_library_categories c
  join public.checklist_library_templates t on t.category_id=c.id
  where c.is_active and t.is_published
  group by c.slug,c.name_en,c.name_ar,c.sort_order
  order by c.sort_order,c.name_en;
end;
$$;
revoke all on function public.list_global_library_facets_v2(uuid) from public,anon;
grant execute on function public.list_global_library_facets_v2(uuid) to authenticated;
