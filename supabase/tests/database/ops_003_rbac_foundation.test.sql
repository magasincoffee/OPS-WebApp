begin;

create extension if not exists pgtap with schema extensions;

select plan(5);

select results_eq(
  $$
    select code
    from public.roles
    order by code
  $$,
  $$ values
    ('ACCOUNTING'::text),
    ('OWNER_ADMIN'::text),
    ('PRINTER_PRODUCTION'::text),
    ('SALES'::text),
    ('WAREHOUSE'::text)
  $$,
  'OPS-003 seeds exactly the five locked V1 roles'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname in ('users', 'roles', 'user_roles')
      and c.relkind in ('r', 'p')
      and c.relrowsecurity
  $$,
  array[3::bigint],
  'RLS is enabled on all OPS identity/RBAC tables'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'public'
      and tablename in ('users', 'roles', 'user_roles')
      and policyname in (
        'users_select_self_or_owner_admin',
        'users_update_owner_admin',
        'roles_select_authenticated',
        'roles_mutate_owner_admin',
        'user_roles_select_self_or_owner_admin',
        'user_roles_mutate_owner_admin'
      )
  $$,
  array[6::bigint],
  'OPS-003 identity/RBAC policy set is present'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in (
        'handle_new_auth_user',
        'current_user_has_role',
        'current_user_is_owner_admin'
      )
      and p.prosecdef
      and coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=public, pg_temp%'
  $$,
  array[3::bigint],
  'OPS-003 security-definer helpers pin their search path'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.current_user_has_role(text)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.current_user_has_role(text)',
    'EXECUTE'
  )
  and has_function_privilege(
    'authenticated',
    'public.current_user_is_owner_admin()',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.current_user_is_owner_admin()',
    'EXECUTE'
  ),
  'Role-check helpers are executable by authenticated users but not anon'
);

select * from finish();
rollback;
