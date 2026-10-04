begin;

create extension if not exists pgtap with schema extensions;

select plan(5);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'public'
      and tablename = 'suppliers'
      and policyname = 'suppliers_select_operational_roles'
      and cmd = 'SELECT'
      and qual like '%OWNER_ADMIN%'
      and qual like '%ACCOUNTING%'
      and qual like '%WAREHOUSE%'
  $$,
  array[1::bigint],
  'supplier profiles are readable by OWNER_ADMIN, ACCOUNTING, and WAREHOUSE'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'public'
      and tablename = 'suppliers'
      and policyname = 'suppliers_mutate_owner_admin'
      and cmd = 'ALL'
      and qual like '%OWNER_ADMIN%'
      and with_check like '%OWNER_ADMIN%'
  $$,
  array[1::bigint],
  'supplier master mutation remains OWNER_ADMIN-only'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'public'
      and tablename = 'supplier_products'
      and policyname = 'supplier_products_select_procurement_roles'
      and cmd = 'SELECT'
      and qual like '%OWNER_ADMIN%'
      and qual like '%ACCOUNTING%'
      and qual like '%WAREHOUSE%'
  $$,
  array[1::bigint],
  'supplier-product mappings are visible to procurement operational roles'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'public'
      and tablename = 'purchase_cost_history'
      and policyname = 'purchase_cost_history_select_financial_roles'
      and cmd = 'SELECT'
      and qual like '%OWNER_ADMIN%'
      and qual like '%ACCOUNTING%'
      and qual not like '%WAREHOUSE%'
  $$,
  array[1::bigint],
  'WAREHOUSE is excluded from latest purchase-cost history'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'public'
      and tablename = 'purchase_orders'
      and policyname = 'purchase_orders_select_financial_roles'
      and cmd = 'SELECT'
      and qual like '%OWNER_ADMIN%'
      and qual like '%ACCOUNTING%'
      and qual not like '%WAREHOUSE%'
  $$,
  array[1::bigint],
  'WAREHOUSE is excluded from purchase-order financial history'
);

select * from finish();

rollback;
