-- GLOB-001 P1-04: atomic platform-owner curation of global classifications.
-- Never edits a library template, its legacy category, installs or signed records.
create table if not exists public.library_taxonomy_audit_log (
  id uuid primary key default gen_random_uuid(),
  template_id uuid not null references public.checklist_library_templates(id)
    on delete cascade,
  changed_by uuid,
  previous_terms jsonb not null,
  new_terms jsonb not null,
  changed_at timestamptz not null default now()
);
alter table public.library_taxonomy_audit_log enable row level security;
create policy global_taxonomy_audit_owner_read on public.library_taxonomy_audit_log
  for select to authenticated using (public.is_platform_owner());
revoke all on public.library_taxonomy_audit_log from public, anon, authenticated;
grant select on public.library_taxonomy_audit_log to authenticated;

create or replace function public.assign_global_library_taxonomy_v2(
  p_template_id uuid,
  p_industries text[],
  p_domains text[]
)
returns void
language plpgsql security definer
set search_path=public
as $$
declare
  v_industries text[];
  v_domains text[];
  v_old jsonb;
  v_new jsonb;
begin
  if auth.uid() is null or not coalesce(public.is_platform_owner(),false) then
    raise exception 'only platform owner may change global library classification'
      using errcode='42501';
  end if;
  if not exists (select 1 from public.checklist_library_templates
     where id=p_template_id) then
    raise exception 'unknown library template';
  end if;
  select coalesce(array_agg(distinct btrim(s)),array[]::text[]) into v_industries
    from unnest(coalesce(p_industries,array[]::text[])) s
    where btrim(s)<>'';
  select coalesce(array_agg(distinct btrim(s)),array[]::text[]) into v_domains
    from unnest(coalesce(p_domains,array[]::text[])) s
    where btrim(s)<>'';
  if cardinality(v_industries)=0 or cardinality(v_domains)=0 then
    raise exception 'at least one industry and one domain are required';
  end if;
  if (select count(*) from public.library_taxonomy_terms
      where dimension='industry' and is_active and slug=any(v_industries))
      <>cardinality(v_industries)
    or (select count(*) from public.library_taxonomy_terms
      where dimension in ('domain','subdomain') and is_active
        and slug=any(v_domains))<>cardinality(v_domains) then
    raise exception 'invalid or inactive industry/domain slug';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'dimension',term.dimension,'slug',term.slug) order by term.dimension,term.slug),
    '[]'::jsonb) into v_old
  from public.library_template_taxonomy m
  join public.library_taxonomy_terms term on term.id=m.term_id
  where m.template_id=p_template_id
    and term.dimension in ('industry','domain','subdomain');

  delete from public.library_template_taxonomy m
  using public.library_taxonomy_terms term
  where m.template_id=p_template_id and m.term_id=term.id
    and term.dimension in ('industry','domain','subdomain');

  insert into public.library_template_taxonomy(template_id,term_id)
  select p_template_id,term.id from public.library_taxonomy_terms term
  where (term.dimension='industry' and term.slug=any(v_industries))
    or (term.dimension in ('domain','subdomain') and term.slug=any(v_domains));

  select coalesce(jsonb_agg(jsonb_build_object(
    'dimension',term.dimension,'slug',term.slug) order by term.dimension,term.slug),
    '[]'::jsonb) into v_new
  from public.library_template_taxonomy m
  join public.library_taxonomy_terms term on term.id=m.term_id
  where m.template_id=p_template_id
    and term.dimension in ('industry','domain','subdomain');
  if v_old is distinct from v_new then
    insert into public.library_taxonomy_audit_log
      (template_id,changed_by,previous_terms,new_terms)
    values (p_template_id,auth.uid(),v_old,v_new);
  end if;
end;
$$;
revoke all on function public.assign_global_library_taxonomy_v2(uuid,text[],text[])
  from public,anon;
grant execute on function public.assign_global_library_taxonomy_v2(uuid,text[],text[])
  to authenticated;
