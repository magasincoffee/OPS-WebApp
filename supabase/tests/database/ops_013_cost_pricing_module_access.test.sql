begin;

create extension if not exists pgtap with schema extensions;

select plan(9);

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
      and qual not like '%SALES%'
      and qual not like '%WAREHOUSE%'
      and qual not like '%PRINTER_PRODUCTION%'
  $$,
  array[1::bigint],
  'purchase cost history is limited to OWNER_ADMIN and ACCOUNTING'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'public'
      and tablename = 'purchase_cost_history'
      and policyname = 'purchase_cost_history_mutate_owner_admin'
      and cmd = 'ALL'
      and qual like '%OWNER_ADMIN%'
      and with_check like '%OWNER_ADMIN%'
  $$,
  array[1::bigint],
  'purchase cost mutation remains OWNER_ADMIN-only'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'public'
      and tablename = 'pricing_rules'
      and policyname = 'pricing_rules_select_authorized_roles'
      and cmd = 'SELECT'
      and qual like '%OWNER_ADMIN%'
      and qual like '%SALES%'
      and qual like '%ACCOUNTING%'
      and qual not like '%WAREHOUSE%'
      and qual not like '%PRINTER_PRODUCTION%'
  $$,
  array[1::bigint],
  'pricing rules are visible only to OWNER_ADMIN, SALES, and ACCOUNTING'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'public'
      and tablename = 'pricing_rules'
      and policyname = 'pricing_rules_mutate_owner_admin'
      and cmd = 'ALL'
      and qual like '%OWNER_ADMIN%'
      and with_check like '%OWNER_ADMIN%'
  $$,
  array[1::bigint],
  'pricing rule configuration remains OWNER_ADMIN-only'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'public'
      and tablename = 'price_tiers'
      and policyname = 'price_tiers_select_authorized_roles'
      and cmd = 'SELECT'
      and qual like '%OWNER_ADMIN%'
      and qual like '%SALES%'
      and qual like '%ACCOUNTING%'
      and qual not like '%WAREHOUSE%'
      and qual not like '%PRINTER_PRODUCTION%'
  $$,
  array[1::bigint],
  'quantity tiers follow pricing visibility'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'public'
      and tablename = 'price_tiers'
      and policyname = 'price_tiers_mutate_owner_admin'
      and cmd = 'ALL'
      and qual like '%OWNER_ADMIN%'
      and with_check like '%OWNER_ADMIN%'
  $$,
  array[1::bigint],
  'quantity-tier configuration remains OWNER_ADMIN-only'
);

select results_eq(
  $$
    select count(*)::bigint
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'purchase_cost_history'
      and column_name in ('purchase_cost_per_base_unit','landed_cost_per_base_unit')
      and is_generated = 'ALWAYS'
  $$,
  array[2::bigint],
  'purchase and landed base-unit costs remain database-generated'
);

select results_eq(
  $$
    select count(*)::bigint
    from information_schema.check_constraints
    where constraint_name = 'price_tiers_one_pricing_basis'
  $$,
  array[1::bigint],
  'every quantity tier has exactly one fixed, markup, or margin pricing basis'
);

select results_eq(
  $$
    select count(*)::bigint
    from information_schema.check_constraints
    where constraint_name in (
      'purchase_cost_history_units_positive',
      'purchase_cost_history_purchase_price_nonnegative',
      'purchase_cost_history_freight_nonnegative',
      'purchase_cost_history_other_cost_nonnegative',
      'pricing_rules_print_mode_valid',
      'pricing_rules_print_color_range_valid',
      'price_tiers_min_quantity_positive',
      'price_tiers_quantity_range_valid',
      'price_tiers_margin_valid'
    )
  $$,
  array[9::bigint],
  'core cost and pricing numeric/range constraints remain enforced'
);

select * from finish();

rollback;
