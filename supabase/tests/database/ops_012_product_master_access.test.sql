begin;

create extension if not exists pgtap with schema extensions;

select plan(8);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'public'
      and tablename = 'product_categories'
      and policyname = 'product_categories_select_all_v1_roles'
      and cmd = 'SELECT'
      and qual like '%OWNER_ADMIN%'
      and qual like '%SALES%'
      and qual like '%ACCOUNTING%'
      and qual like '%WAREHOUSE%'
      and qual like '%PRINTER_PRODUCTION%'
  $$,
  array[1::bigint],
  'all V1 roles can read product categories'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'public'
      and tablename = 'products'
      and policyname = 'products_select_all_v1_roles'
      and cmd = 'SELECT'
      and qual like '%OWNER_ADMIN%'
      and qual like '%SALES%'
      and qual like '%ACCOUNTING%'
      and qual like '%WAREHOUSE%'
      and qual like '%PRINTER_PRODUCTION%'
  $$,
  array[1::bigint],
  'all V1 roles can read product identity'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'public'
      and tablename = 'product_variants'
      and policyname = 'product_variants_select_all_v1_roles'
      and cmd = 'SELECT'
      and qual like '%OWNER_ADMIN%'
      and qual like '%SALES%'
      and qual like '%ACCOUNTING%'
      and qual like '%WAREHOUSE%'
      and qual like '%PRINTER_PRODUCTION%'
  $$,
  array[1::bigint],
  'all V1 roles can read SKU/variant identity'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'public'
      and tablename = 'product_packaging'
      and policyname = 'product_packaging_select_all_v1_roles'
      and cmd = 'SELECT'
      and qual like '%OWNER_ADMIN%'
      and qual like '%SALES%'
      and qual like '%ACCOUNTING%'
      and qual like '%WAREHOUSE%'
      and qual like '%PRINTER_PRODUCTION%'
  $$,
  array[1::bigint],
  'all V1 roles can read packaging conversion'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'public'
      and tablename in ('product_categories','products','product_variants','product_packaging')
      and policyname like '%mutate_owner_admin'
      and cmd = 'ALL'
      and qual like '%OWNER_ADMIN%'
      and with_check like '%OWNER_ADMIN%'
  $$,
  array[4::bigint],
  'the four product-master layers remain OWNER_ADMIN mutation only'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'public'
      and tablename = 'supplier_products'
      and policyname = 'supplier_products_select_procurement_roles'
      and qual like '%WAREHOUSE%'
      and qual not like '%SALES%'
      and qual not like '%PRINTER_PRODUCTION%'
  $$,
  array[1::bigint],
  'supplier linkage remains procurement-sensitive outside general product reads'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'public'
      and tablename = 'purchase_cost_history'
      and policyname = 'purchase_cost_history_select_financial_roles'
      and qual like '%OWNER_ADMIN%'
      and qual like '%ACCOUNTING%'
      and qual not like '%SALES%'
      and qual not like '%WAREHOUSE%'
      and qual not like '%PRINTER_PRODUCTION%'
  $$,
  array[1::bigint],
  'purchase cost remains outside the general product master role surface'
);

select results_eq(
  $$
    select count(*)::bigint
    from information_schema.check_constraints
    where constraint_name in (
      'product_variants_minimum_stock_nonnegative',
      'product_packaging_units_positive',
      'product_packaging_effective_dates_valid'
    )
  $$,
  array[3::bigint],
  'SKU minimum stock and packaging conversion constraints remain enforced'
);

select * from finish();

rollback;
