begin;

create extension if not exists pgtap with schema extensions;

select plan(11);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname='public'
      and tablename='purchase_orders'
      and policyname='purchase_orders_select_financial_roles'
      and cmd='SELECT'
      and qual like '%OWNER_ADMIN%'
      and qual like '%ACCOUNTING%'
      and qual not like '%WAREHOUSE%'
      and qual not like '%SALES%'
      and qual not like '%PRINTER_PRODUCTION%'
  $$,
  array[1::bigint],
  'purchase orders are visible only to OWNER_ADMIN and ACCOUNTING'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname='public'
      and tablename='purchase_orders'
      and policyname='purchase_orders_mutate_owner_admin'
      and cmd='ALL'
      and qual like '%OWNER_ADMIN%'
      and with_check like '%OWNER_ADMIN%'
  $$,
  array[1::bigint],
  'purchase-order mutation remains OWNER_ADMIN-only'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname='public'
      and tablename='purchase_order_items'
      and policyname='purchase_order_items_select_financial_roles'
      and qual like '%OWNER_ADMIN%'
      and qual like '%ACCOUNTING%'
      and qual not like '%WAREHOUSE%'
  $$,
  array[1::bigint],
  'purchase-order line cost remains hidden from WAREHOUSE'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname='public'
      and tablename='purchase_payments'
      and policyname='purchase_payments_select_financial_roles'
      and qual like '%OWNER_ADMIN%'
      and qual like '%ACCOUNTING%'
      and qual not like '%WAREHOUSE%'
  $$,
  array[1::bigint],
  'supplier payment records remain financial-role only'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname='public'
      and tablename in ('purchase_order_items','purchase_payments')
      and policyname in ('purchase_order_items_mutate_owner_admin','purchase_payments_mutate_owner_admin')
      and cmd='ALL'
      and qual like '%OWNER_ADMIN%'
      and with_check like '%OWNER_ADMIN%'
  $$,
  array[2::bigint],
  'purchase items and supplier payments remain OWNER_ADMIN-only mutations'
);

select results_eq(
  $$
    select count(*)::bigint
    from information_schema.columns
    where table_schema='public'
      and table_name='purchase_order_items'
      and column_name in ('base_quantity','line_subtotal')
      and is_generated='ALWAYS'
  $$,
  array[2::bigint],
  'base quantity and line subtotal stay database-generated from purchase inputs'
);

select results_eq(
  $$
    select count(*)::bigint
    from information_schema.check_constraints
    where constraint_name in (
      'purchase_orders_freight_nonnegative',
      'purchase_orders_currency_code_valid',
      'purchase_orders_expected_receipt_valid',
      'purchase_order_items_package_quantity_positive',
      'purchase_order_items_units_per_purchase_unit_positive',
      'purchase_order_items_unit_cost_nonnegative',
      'purchase_payments_amount_positive'
    )
  $$,
  array[7::bigint],
  'purchase-order, line, and payment numeric/date constraints remain enforced'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname='public'
      and tablename='attachments'
      and policyname='attachments_select_purchase_order_accounting'
      and cmd='SELECT'
      and qual like '%ACCOUNTING%'
      and qual like '%PURCHASE_ORDER%'
      and qual like '%PAYMENT_EVIDENCE%'
      and qual like '%DOCUMENT%'
  $$,
  array[1::bigint],
  'ACCOUNTING can read bounded PO document and payment-evidence metadata'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname='storage'
      and tablename='objects'
      and policyname='ops_purchase_order_attachments_select'
      and cmd='SELECT'
      and qual like '%OWNER_ADMIN%'
      and qual like '%ACCOUNTING%'
  $$,
  array[1::bigint],
  'private PO binary objects are readable only through financial-role policy'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname='storage'
      and tablename='objects'
      and policyname='ops_purchase_order_attachments_insert'
      and cmd='INSERT'
      and with_check like '%OWNER_ADMIN%'
      and with_check not like '%ACCOUNTING%'
  $$,
  array[1::bigint],
  'only OWNER_ADMIN can upload private PO attachment objects'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_trigger
    where not tgisinternal
      and tgrelid in (
        'public.purchase_orders'::regclass,
        'public.purchase_order_items'::regclass,
        'public.purchase_payments'::regclass
      )
      and tgname in (
        'purchase_orders_capture_activity',
        'purchase_order_items_capture_activity',
        'purchase_payments_capture_activity'
      )
  $$,
  array[3::bigint],
  'purchase order, item, and supplier-payment activity capture remains active'
);

select * from finish();

rollback;
