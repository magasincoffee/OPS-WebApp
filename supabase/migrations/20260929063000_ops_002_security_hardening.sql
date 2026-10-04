-- OPS-002 security hardening
-- Keep public-schema tables protected consistently across local, CI, and hosted Supabase.
-- Authorization policies and grants are intentionally deferred to OPS-003 (Auth/RBAC).

alter table public.customers enable row level security;
alter table public.suppliers enable row level security;
alter table public.product_categories enable row level security;
alter table public.products enable row level security;
alter table public.product_variants enable row level security;
alter table public.product_packaging enable row level security;
alter table public.supplier_products enable row level security;

alter table public.purchase_cost_history enable row level security;
alter table public.pricing_rules enable row level security;
alter table public.price_tiers enable row level security;

alter table public.purchase_orders enable row level security;
alter table public.purchase_order_items enable row level security;
alter table public.purchase_payments enable row level security;
alter table public.goods_receipts enable row level security;
alter table public.goods_receipt_items enable row level security;

alter table public.quotations enable row level security;
alter table public.quotation_items enable row level security;
alter table public.sales_orders enable row level security;
alter table public.sales_order_items enable row level security;

alter table public.inventory_reservations enable row level security;
alter table public.inventory_movements enable row level security;

alter table public.stocktakes enable row level security;
alter table public.stocktake_items enable row level security;

alter table public.print_jobs enable row level security;
alter table public.print_job_events enable row level security;

alter table public.customer_payments enable row level security;
alter table public.customer_ledger_entries enable row level security;

alter table public.deliveries enable row level security;
alter table public.delivery_items enable row level security;

alter table public.tasks enable row level security;

-- Public views must execute with the querying role so underlying RLS is respected.
alter view public.purchase_order_totals set (security_invoker = true);
alter view public.quotation_totals set (security_invoker = true);
alter view public.sales_order_totals set (security_invoker = true);
alter view public.inventory_stock_snapshot set (security_invoker = true);
alter view public.inventory_reservation_balances set (security_invoker = true);
alter view public.print_job_queue set (security_invoker = true);
alter view public.sales_order_receivables set (security_invoker = true);
alter view public.customer_ledger_balances set (security_invoker = true);
alter view public.delivery_order_status set (security_invoker = true);
alter view public.operational_task_queue set (security_invoker = true);
