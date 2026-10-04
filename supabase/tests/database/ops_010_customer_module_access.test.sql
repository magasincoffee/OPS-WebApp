begin;

create extension if not exists pgtap with schema extensions;

select plan(4);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'public'
      and tablename = 'customers'
      and policyname = 'customers_select_business_roles'
      and qual like '%OWNER_ADMIN%'
      and qual like '%SALES%'
      and qual like '%ACCOUNTING%'
  $$,
  array[1::bigint],
  'customer profiles remain readable by OWNER_ADMIN, SALES, and ACCOUNTING'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'public'
      and tablename = 'customers'
      and policyname = 'customers_mutate_sales_or_owner'
      and cmd = 'ALL'
      and qual like '%OWNER_ADMIN%'
      and qual like '%SALES%'
      and with_check like '%OWNER_ADMIN%'
      and with_check like '%SALES%'
  $$,
  array[1::bigint],
  'customer mutation remains bounded to OWNER_ADMIN and SALES'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'public'
      and tablename = 'activity_logs'
      and policyname = 'activity_logs_select_customer_business_roles'
      and cmd = 'SELECT'
      and qual like '%CUSTOMER%'
      and qual like '%SALES%'
      and qual like '%ACCOUNTING%'
  $$,
  array[1::bigint],
  'SALES and ACCOUNTING can read customer-only activity history'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'public'
      and tablename = 'activity_logs'
      and policyname = 'activity_logs_select_customer_business_roles'
      and cmd in ('INSERT', 'UPDATE', 'DELETE')
  $$,
  array[0::bigint],
  'customer activity-history access adds no audit mutation capability'
);

select * from finish();

rollback;
