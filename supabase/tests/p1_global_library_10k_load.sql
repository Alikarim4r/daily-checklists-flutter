-- 10k synthetic dataset, only in disposable local PostgreSQL test database.
insert into public.checklist_library_templates(
 id, category_id, slug, name_en, name_ar, is_published, access_model
)
select md5('p1synthetic-'||n::text)::uuid,
 '30000000-0000-0000-0000-000000000001',
 'synthetic_'||n::text,
 'Synthetic Maintenance Task '||n::text,
 'اختبار اصطناعي '||n::text,
 true,'starter_included'
from generate_series(1,10000) n;

insert into public.library_template_classification(template_id,document_kind)
select t.id,'checklist'
from public.checklist_library_templates t
where t.slug like 'synthetic_%';

insert into public.library_template_taxonomy(template_id,term_id)
select t.id,term.id
from public.checklist_library_templates t
cross join public.library_taxonomy_terms term
where t.slug like 'synthetic_%'
  and ((term.dimension='industry' and term.slug='facilities')
    or (term.dimension='domain' and term.slug='mechanical'));

set role authenticated;
set request.jwt.claim.sub = '10000000-0000-0000-0000-000000000001';
do $$
declare v_count int; v_start timestamp; v_ms numeric;
begin
  v_start := clock_timestamp();
  select count(*) into v_count from public.list_global_library_v2(
    '00000000-0000-0000-0000-00000000000a',p_limit=>100,p_offset=>9900);
  v_ms := extract(epoch from clock_timestamp()-v_start)*1000;
  if v_count<>100 then
    raise exception 'Page count mismatch on 10k templates: %',v_count;
  end if;
  if v_ms>6000 then
    raise exception '10k metadata page too slow: %ms',v_ms;
  end if;
  raise notice 'P1 GLOBAL LIBRARY 10k PAGE: % rows in % ms',v_count,round(v_ms,1);
end;
$$;
reset role;
