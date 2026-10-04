-- OPS-003 bounded unit: identity and RBAC foundation
-- Architecture Generation 1
-- Source of Truth: SOURCE_OF_TRUTH.md
--
-- Scope: bind Supabase Auth identities to OPS users, define the five locked
-- V1 roles, provide role-membership helpers, and establish RLS for the RBAC
-- tables themselves. Business-table authorization policies remain later
-- bounded units within OPS-003.

begin;

create table public.users (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  is_active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint users_display_name_not_blank
    check (display_name is null or length(btrim(display_name)) > 0)
);

create table public.roles (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null unique,
  description text,
  is_system boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint roles_code_not_blank check (length(btrim(code)) > 0),
  constraint roles_name_not_blank check (length(btrim(name)) > 0)
);

create table public.user_roles (
  user_id uuid not null references public.users(id) on delete cascade,
  role_id uuid not null references public.roles(id) on delete cascade,
  assigned_by uuid references public.users(id) on delete set null,
  assigned_at timestamptz not null default timezone('utc', now()),
  primary key (user_id, role_id)
);

create index user_roles_role_id_idx on public.user_roles(role_id);
create index user_roles_assigned_by_idx on public.user_roles(assigned_by);

create trigger users_set_updated_at
before update on public.users
for each row execute function public.set_updated_at();

create trigger roles_set_updated_at
before update on public.roles
for each row execute function public.set_updated_at();

insert into public.roles (code, name, description)
values
  ('OWNER_ADMIN', 'OWNER / ADMIN', 'Full OPS system administration and business access.'),
  ('SALES', 'SALES', 'Customer, quotation, sales-order and permitted receivable access.'),
  ('ACCOUNTING', 'ACCOUNTING', 'Customer payments, receivables, cost and financial operational reporting.'),
  ('WAREHOUSE', 'WAREHOUSE', 'Goods receipt, inventory, reservation, issue, stocktake and authorized adjustments.'),
  ('PRINTER_PRODUCTION', 'PRINTER / PRODUCTION', 'Assigned print-production work without restricted financial data.')
on conflict (code) do nothing;

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.users (id, display_name)
  values (
    new.id,
    nullif(
      btrim(
        coalesce(
          new.raw_user_meta_data ->> 'display_name',
          new.raw_user_meta_data ->> 'full_name',
          split_part(coalesce(new.email, ''), '@', 1)
        )
      ),
      ''
    )
  )
  on conflict (id) do nothing;

  return new;
end;
$$;

revoke all on function public.handle_new_auth_user() from public, anon, authenticated;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_auth_user();

insert into public.users (id, display_name)
select
  au.id,
  nullif(
    btrim(
      coalesce(
        au.raw_user_meta_data ->> 'display_name',
        au.raw_user_meta_data ->> 'full_name',
        split_part(coalesce(au.email, ''), '@', 1)
      )
    ),
    ''
  )
from auth.users au
on conflict (id) do nothing;

create or replace function public.current_user_has_role(p_role_code text)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.user_roles ur
    join public.roles r on r.id = ur.role_id
    join public.users u on u.id = ur.user_id
    where ur.user_id = auth.uid()
      and u.is_active = true
      and r.code = p_role_code
  );
$$;

revoke all on function public.current_user_has_role(text) from public, anon;
grant execute on function public.current_user_has_role(text) to authenticated, service_role;

create or replace function public.current_user_is_owner_admin()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select public.current_user_has_role('OWNER_ADMIN');
$$;

revoke all on function public.current_user_is_owner_admin() from public, anon;
grant execute on function public.current_user_is_owner_admin() to authenticated, service_role;

alter table public.users enable row level security;
alter table public.roles enable row level security;
alter table public.user_roles enable row level security;

revoke all on public.users, public.roles, public.user_roles from anon;
revoke all on public.users, public.roles, public.user_roles from authenticated;

grant select on public.users to authenticated;
grant update on public.users to authenticated;

grant select, insert, update, delete on public.roles to authenticated;
grant select, insert, update, delete on public.user_roles to authenticated;

grant all on public.users, public.roles, public.user_roles to service_role;

create policy users_select_self_or_owner_admin
on public.users
for select
to authenticated
using (id = auth.uid() or public.current_user_is_owner_admin());

create policy users_update_owner_admin
on public.users
for update
to authenticated
using (public.current_user_is_owner_admin())
with check (public.current_user_is_owner_admin());

create policy roles_select_authenticated
on public.roles
for select
to authenticated
using (true);

create policy roles_mutate_owner_admin
on public.roles
for all
to authenticated
using (public.current_user_is_owner_admin())
with check (public.current_user_is_owner_admin());

create policy user_roles_select_self_or_owner_admin
on public.user_roles
for select
to authenticated
using (user_id = auth.uid() or public.current_user_is_owner_admin());

create policy user_roles_mutate_owner_admin
on public.user_roles
for all
to authenticated
using (public.current_user_is_owner_admin())
with check (public.current_user_is_owner_admin());

commit;
