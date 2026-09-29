begin;

create extension if not exists pgtap with schema extensions;

select plan(4);

select results_eq(
  $$
    select count(*)::bigint
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relkind in ('r', 'p')
      and c.relname in (
        'customers','suppliers','product_categories','products','product_variants',
        'product_packaging','supplier_products','purchase_cost_history','pricing_rules',
        'price_tiers','purchase_orders','purchase_order_items','purchase_payments',
        'goods_receipts','goods_receipt_items','quotations','quotation_items',
        'sales_orders','sales_order_items','inventory_reservations','inventory_movements',
        'stocktakes','stocktake_items','print_jobs','print_job_events','customer_payments',
        'customer_ledger_entries','deliveries','delivery_items','tasks'
      )
  $$,
  array[30::bigint],
  'OPS-002 creates all 30 authoritative foundation tables'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relkind = 'v'
      and c.relname in (
        'purchase_order_totals','quotation_totals','sales_order_totals',
        'inventory_stock_snapshot','inventory_reservation_balances','print_job_queue',
        'sales_order_receivables','customer_ledger_balances','delivery_order_status',
        'operational_task_queue'
      )
  $$,
  array[10::bigint],
  'OPS-002 creates all 10 authoritative derived views'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relkind in ('r', 'p')
      and c.relrowsecurity
      and c.relname in (
        'customers','suppliers','product_categories','products','product_variants',
        'product_packaging','supplier_products','purchase_cost_history','pricing_rules',
        'price_tiers','purchase_orders','purchase_order_items','purchase_payments',
        'goods_receipts','goods_receipt_items','quotations','quotation_items',
        'sales_orders','sales_order_items','inventory_reservations','inventory_movements',
        'stocktakes','stocktake_items','print_jobs','print_job_events','customer_payments',
        'customer_ledger_entries','deliveries','delivery_items','tasks'
      )
  $$,
  array[30::bigint],
  'RLS is enabled on every OPS-002 public table'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relkind = 'v'
      and coalesce(c.reloptions, array[]::text[]) @> array['security_invoker=true']
      and c.relname in (
        'purchase_order_totals','quotation_totals','sales_order_totals',
        'inventory_stock_snapshot','inventory_reservation_balances','print_job_queue',
        'sales_order_receivables','customer_ledger_balances','delivery_order_status',
        'operational_task_queue'
      )
  $$,
  array[10::bigint],
  'All OPS-002 public views use security_invoker'
);

select * from finish();
rollback;
