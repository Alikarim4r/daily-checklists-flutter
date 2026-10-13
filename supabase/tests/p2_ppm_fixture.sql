-- P2 isolated authorization/workflow fixture. This is NEVER deployed.
-- Load P1 fixture first for auth.uid(), fake roles, profiles and org memberships.
alter table public.profiles add column is_active boolean not null default true;
alter table public.profiles add column approval_status text not null default 'approved';
create table public.organizations(id uuid primary key,name_en text);
create table public.sites(
 id uuid primary key,organization_id uuid not null references public.organizations(id),
 name_en text not null
);
create table public.facility_buildings(id uuid primary key,site_id uuid references public.sites(id));
create table public.facility_floors(id uuid primary key,building_id uuid references public.facility_buildings(id));
create table public.facility_areas(id uuid primary key,floor_id uuid references public.facility_floors(id));
create table public.checklist_assignments(
 id uuid primary key,organization_id uuid references public.organizations(id),
 site_id uuid references public.sites(id)
);
create table public.user_location_access(
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references public.profiles(id),
 organization_id uuid not null references public.organizations(id),
 site_id uuid references public.sites(id),
 building_id uuid,floor_id uuid,area_id uuid,
 can_write boolean not null default false,
 valid_from timestamptz,valid_until timestamptz
);
create table public.user_site_access (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references public.profiles(id),
 site_id uuid not null references public.sites(id),
 can_write boolean not null default false,
 valid_from timestamptz,valid_until timestamptz
);
create table public.checklist_inspections(
 id uuid primary key,site_id uuid references public.sites(id),
 checklist_assignment_id uuid references public.checklist_assignments(id),
 status text not null default 'draft'
);
create or replace function public.is_org_super_admin(p_org uuid)
returns boolean language sql stable security definer set search_path=public
as $$ select public.is_platform_owner() or exists(select 1 from public.profiles
where id=auth.uid() and role='org_admin' and approved
and home_organization_id=p_org) $$;
create or replace function public.has_site_access(p_site uuid)
returns boolean language sql stable security definer set search_path=public
as $$select public.is_platform_owner() or exists(
select 1 from public.sites s join public.org_memberships m on m.organization_id=s.organization_id
where s.id=p_site and m.user_id=auth.uid() and public.is_approved_active_user())$$;
create or replace function public.can_write_site(p_site uuid)
returns boolean language sql stable security definer set search_path=public
as $$select public.has_site_access(p_site)$$;
insert into public.organizations values
 ('00000000-0000-0000-0000-00000000000a','Education'),
 ('00000000-0000-0000-0000-00000000000b','Hospitality');
insert into public.sites values
 ('50000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-00000000000a','HQ'),
 ('50000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-00000000000b','Hotel');
insert into public.facility_buildings values
 ('60000000-0000-0000-0000-000000000001','50000000-0000-0000-0000-000000000001');
insert into public.facility_floors values
 ('70000000-0000-0000-0000-000000000001','60000000-0000-0000-0000-000000000001');
insert into public.facility_areas values
 ('80000000-0000-0000-0000-000000000001','70000000-0000-0000-0000-000000000001');
insert into public.checklist_assignments values
 ('90000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-00000000000a','50000000-0000-0000-0000-000000000001'),
 ('90000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-00000000000b','50000000-0000-0000-0000-000000000002');
insert into public.checklist_inspections values
 ('a0000000-0000-0000-0000-000000000001','50000000-0000-0000-0000-000000000001',
 '90000000-0000-0000-0000-000000000001','submitted'),
 ('a0000000-0000-0000-0000-000000000002','50000000-0000-0000-0000-000000000002',
 '90000000-0000-0000-0000-000000000002','submitted');
update public.profiles set role='org_admin' where id='10000000-0000-0000-0000-000000000001';
-- We can test a site worker in Org A by adding one more site member.
insert into public.profiles(id,home_organization_id,approved,role) values(
 '10000000-0000-0000-0000-000000000005','00000000-0000-0000-0000-00000000000a',true,'worker');
insert into public.org_memberships values
 ('10000000-0000-0000-0000-000000000005','00000000-0000-0000-0000-00000000000a');
insert into public.user_site_access(user_id,site_id,can_write) values ('10000000-0000-0000-0000-000000000005','50000000-0000-0000-0000-000000000001',true);
grant select on public.profiles,public.sites,public.organizations,
 public.facility_buildings,public.facility_floors,public.facility_areas,
 public.checklist_assignments,public.checklist_inspections to authenticated;
