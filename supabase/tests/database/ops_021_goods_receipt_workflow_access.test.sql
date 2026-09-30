begin;

create extension if not exists pgtap with schema extensions;

select plan(12);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname='public'
      and tablename='goods_receipts'
      and policyname='goods_receipts_select_operational_roles'
      and cmd='SELECT'
      and qual like '%OWNER_ADMIN%'
      and qual like '%ACCOUNTING%'
      and qual like '%WAREHOUSE%'
      and qual not like '%SALES%'
      and qual not like '%PRINTER_PRODUCTION%'
  $$,
  array[1::bigint],
  'goods receipts are visible to OWNER_ADMIN, ACCOUNTING, and WAREHOUSE'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname='public'
      and tablename='goods_receipts'
      and policyname='goods_receipts_mutate_warehouse_or_owner'
      and cmd='ALL'
      and qual like '%OWNER_ADMIN%'
      and qual like '%WAREHOUSE%'
      and with_check like '%OWNER_ADMIN%'
      and with_check like '%WAREHOUSE%'
  $$,
  array[1::bigint],
  'goods receipt mutation is OWNER_ADMIN/WAREHOUSE only'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname='public'
      and tablename='goods_receipt_items'
      and policyname='goods_receipt_items_mutate_warehouse_or_owner'
      and cmd='ALL'
      and qual like '%OWNER_ADMIN%'
      and qual like '%WAREHOUSE%'
  $$,
  array[1::bigint],
  'goods receipt item mutation is OWNER_ADMIN/WAREHOUSE only'
);

select results_eq(
  $$
    select count(*)::bigint
    from information_schema.columns
    where table_schema='public'
      and table_name='goods_receipt_source_lines'
      and column_name in (
        'unit_cost_per_purchase_unit',
        'line_subtotal',
        'freight_amount',
        'total_amount',
        'payment_amount'
      )
  $$,
  array[0::bigint],
  'warehouse receipt-source projection exposes no purchase cost or payment amounts'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_class c
    join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public'
      and c.relname='goods_receipt_source_lines'
      and c.relkind='v'
      and coalesce(c.reloptions, array[]::text[]) @> array['security_invoker=true']
  $$,
  array[1::bigint],
  'public goods-receipt source view is security-invoker'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='private'
      and p.proname='goods_receipt_source_lines'
      and p.prosecdef
  $$,
  array[1::bigint],
  'sanitized receipt-source function is isolated in private schema and security-definer'
);

select is(
  has_function_privilege('anon', 'private.goods_receipt_source_lines()', 'EXECUTE'),
  false,
  'anon cannot execute the private receipt-source function'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_trigger
    where not tgisinternal
      and tgname in (
        'goods_receipts_guard_header',
        'goods_receipt_items_guard_integrity',
        'goods_receipts_sync_po_actual_date',
        'goods_receipt_items_sync_po_actual_date'
      )
  $$,
  array[4::bigint],
  'receipt payment/source integrity and actual-date synchronization triggers are installed'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname='public'
      and tablename='attachments'
      and policyname in (
        'attachments_select_goods_receipt_operational_roles',
        'attachments_insert_goods_receipt_warehouse_document'
      )
  $$,
  array[2::bigint],
  'goods-receipt document metadata policies remain active'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname='storage'
      and tablename='objects'
      and policyname in (
        'ops_goods_receipt_attachments_select',
        'ops_goods_receipt_attachments_insert'
      )
  $$,
  array[2::bigint],
  'goods-receipt private Storage object policies remain active'
);

select results_eq(
  $$
    select count(*)::bigint
    from information_schema.columns
    where table_schema='public'
      and table_name='goods_receipt_items'
      and column_name='base_quantity'
      and is_generated='ALWAYS'
  $$,
  array[1::bigint],
  'received base quantity remains database-generated from package conversion'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_trigger
    where not tgisinternal
      and tgrelid in (
        'public.goods_receipts'::regclass,
        'public.goods_receipt_items'::regclass
      )
      and tgname in (
        'goods_receipts_capture_activity',
        'goods_receipt_items_capture_activity'
      )
  $$,
  array[2::bigint],
  'goods receipt and item activity capture remains active'
);

select * from finish();

rollback;
