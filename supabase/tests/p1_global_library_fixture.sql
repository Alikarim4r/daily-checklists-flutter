-- P1 isolated PostgreSQL 16 fixture; NEVER run on production.
-- `psql -X -v ON_ERROR_STOP=1` against a disposable temp cluster only.
do $$ begin
  if not exists(select 1 from pg_roles where rolname='authenticated') then
    create role authenticated nologin;
  end if;
  if not exists(select 1 from pg_roles where rolname='anon') then
    create role anon nologin;
  end if;
end $$;
create schema if not exists auth;
create or replace function auth.uid() returns uuid language sql stable
as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;

create table public.profiles (
 id uuid primary key,
 home_organization_id uuid,
 approved boolean not null default true,
 role text not null default 'user'
);
create table public.org_memberships(user_id uuid, organization_id uuid, primary key(user_id,organization_id));

create or replace function public.is_platform_owner()
returns boolean language sql stable security definer set search_path=public
as $$ select coalesce((select p.role='owner' and p.approved from public.profiles p where p.id=auth.uid()),false) $$;
create or replace function public.is_approved_active_user()
returns boolean language sql stable security definer set search_path=public
as $$ select coalesce((select p.approved from public.profiles p where p.id=auth.uid()),false) $$;
create or replace function public.can_access_organization(p_org uuid)
returns boolean language sql stable security definer set search_path=public
as $$ select public.is_platform_owner() or exists(
  select 1 from public.org_memberships m
    where m.user_id=auth.uid() and m.organization_id=p_org
) $$;

create table public.checklist_library_categories (
 id uuid primary key,
 slug text unique not null,
 name_en text not null,
 name_ar text not null,
 is_active boolean not null default true,
 sort_order int not null default 0
);
create table public.checklist_library_templates (
 id uuid primary key,
 category_id uuid not null references public.checklist_library_categories(id),
 slug text not null unique,
 version_number int not null default 1,
 name_en text not null,
 name_ar text not null,
 description_en text,
 description_ar text,
 facility_tags text[] not null default '{}',
 languages text[] not null default array['en','ar'],
 access_model text not null default 'starter_included',
 minimum_plan_tier text not null default 'starter',
 google_play_product_id text,
 list_price_minor int,
 list_price_currency text not null default 'QAR',
 form_theme text not null default 'inherit',
 form_theme_accent text,
 is_published boolean not null default true,
 sort_order int not null default 0
);
-- Existing catalog metadata is already readable by authenticated approved users.
grant select on public.checklist_library_templates to authenticated;
create table public.checklist_library_template_items (
 id uuid primary key default gen_random_uuid(),
 library_template_id uuid not null references public.checklist_library_templates(id),
 is_active boolean not null default true
);
create table public.organization_library_installs (
 organization_id uuid not null,
 library_template_id uuid not null,
 installed_template_id uuid not null,
 library_version int not null,
 installed_at timestamptz default now()
);
create table public.organization_library_purchases (
 organization_id uuid not null,
 library_template_id uuid not null,
 purchase_state text not null default 'purchased',
 primary key(organization_id,library_template_id)
);
create table public.checklist_library_revisions (
 library_template_id uuid not null references public.checklist_library_templates(id),
 version_number int not null,
 template_snapshot jsonb not null,
 items_snapshot jsonb not null,
 primary key(library_template_id,version_number)
);
alter table public.checklist_library_revisions enable row level security;
grant select on public.checklist_library_revisions to authenticated;

create or replace function public.can_access_library_template(
 p_library_template_id uuid, p_organization_id uuid
)
returns boolean language sql stable security definer set search_path=public
as $$
 select public.is_platform_owner() or (
   auth.uid() is not null
   and public.is_approved_active_user()
   and public.can_access_organization(p_organization_id)
   and exists (
     select 1 from public.checklist_library_templates t
     where t.id=p_library_template_id and t.is_published
       and (
        t.access_model <> 'premium' or exists(
          select 1 from public.organization_library_purchases p
          where p.organization_id=p_organization_id
            and p.library_template_id=t.id
            and p.purchase_state='purchased'
        )
       )
   )
 )
$$;

insert into public.profiles(id,home_organization_id,approved,role) values
('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-00000000000a',true,'user'),
('10000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-00000000000b',true,'user'),
('10000000-0000-0000-0000-000000000003',null,true,'owner'),
('10000000-0000-0000-0000-000000000004','00000000-0000-0000-0000-00000000000a',false,'user');
insert into public.org_memberships values
('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-00000000000a'),
('10000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-00000000000b'),
('10000000-0000-0000-0000-000000000004','00000000-0000-0000-0000-00000000000a');
insert into public.checklist_library_categories(id,slug,name_en,name_ar) values
('30000000-0000-0000-0000-000000000001','technical','Technical','فني'),
('30000000-0000-0000-0000-000000000002','hygiene','Cleaning','النظافة');
insert into public.checklist_library_templates(
id,category_id,slug,name_en,name_ar,access_model,facility_tags,is_published) values
('20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','chiller_plant','Chiller Plant','محطة المبردات','premium',array['hvac'],true),
('20000000-0000-0000-0000-000000000002','30000000-0000-0000-0000-000000000002','washroom_hygiene_safety','Washroom Hygiene','نظافة الحمامات','starter_included',array['hygiene'],true),
('20000000-0000-0000-0000-000000000003','30000000-0000-0000-0000-000000000001','private_draft','Private Draft','مسودة خاصة','premium',array['hvac'],false);
insert into public.checklist_library_template_items(library_template_id) values
('20000000-0000-0000-0000-000000000001'),('20000000-0000-0000-0000-000000000002');
insert into public.checklist_library_revisions
(library_template_id,version_number,template_snapshot,items_snapshot) values
('20000000-0000-0000-0000-000000000001',1,'{}','[{"private":"premium body"}]'),
('20000000-0000-0000-0000-000000000002',1,'{}','[{"public":"free body"}]'),
('20000000-0000-0000-0000-000000000003',1,'{}','[{"secret":"draft body"}]');
insert into public.organization_library_purchases values
('00000000-0000-0000-0000-00000000000a','20000000-0000-0000-0000-000000000001','purchased');
