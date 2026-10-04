-- OPS-002 production hardening discovered by Supabase advisors.
-- Authorization policies remain deferred to OPS-003.

-- Pin search_path for trigger/helper functions.
alter function public.set_updated_at() set search_path = public, pg_temp;
alter function public.guard_inventory_movement_available_stock() set search_path = public, pg_temp;
alter function public.prevent_inventory_movement_mutation() set search_path = public, pg_temp;
alter function public.validate_print_job_source() set search_path = public, pg_temp;
alter function public.validate_customer_payment_source() set search_path = public, pg_temp;
alter function public.validate_customer_ledger_source() set search_path = public, pg_temp;
alter function public.prevent_customer_ledger_entry_mutation() set search_path = public, pg_temp;
alter function public.validate_delivery_item_source() set search_path = public, pg_temp;

-- The automatic-RLS helper may exist on hosted Supabase projects but is not
-- created by the version-controlled OPS migration chain. Harden it when present
-- without making fresh/local database initialization depend on hosted-only state.
do $$
begin
  if to_regprocedure('public.rls_auto_enable()') is not null then
    execute 'revoke execute on function public.rls_auto_enable() from public, anon, authenticated';
  end if;
end
$$;

-- Cover remaining foreign keys flagged by the performance advisor.
create index if not exists purchase_cost_history_packaging_id_idx
  on public.purchase_cost_history (packaging_id);

create index if not exists purchase_order_items_packaging_id_idx
  on public.purchase_order_items (packaging_id);

create index if not exists quotation_items_packaging_id_idx
  on public.quotation_items (packaging_id);

create index if not exists sales_order_items_packaging_id_idx
  on public.sales_order_items (packaging_id);

create index if not exists sales_order_items_source_quotation_item_id_idx
  on public.sales_order_items (source_quotation_item_id);

create index if not exists supplier_products_packaging_id_idx
  on public.supplier_products (packaging_id);
