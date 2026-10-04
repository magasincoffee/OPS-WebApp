-- OPS-003 bounded unit: quotation and sales-order RBAC policies
-- Architecture Generation 1
-- Source of Truth: SOURCE_OF_TRUTH.md
--
-- Scope is intentionally limited to quotations, quotation items, sales orders,
-- sales-order items, and their derived totals views. Production, customer
-- finance, delivery, operational tasks, and representative permission
-- verification remain later bounded units inside OPS-003.
--
-- Policy intent derived from SOT Section 5:
-- - OWNER_ADMIN: full access in this slice.
-- - SALES: manage quotations and sales orders and read their selling-price data.
-- - ACCOUNTING: read sales orders/items and order totals for financial state.
-- - WAREHOUSE and PRINTER_PRODUCTION: no direct access to sales tables in this
--   bounded unit, avoiding unnecessary exposure of selling-price/order financial
--   data. Their operational access remains through their own domain records.
-- - Downstream print/warehouse status synchronization should use bounded
--   workflows rather than granting broad UPDATE rights on sales_orders.

begin;

revoke all on
  public.quotations,
  public.quotation_items,
  public.sales_orders,
  public.sales_order_items
from anon;

revoke all on
  public.quotations,
  public.quotation_items,
  public.sales_orders,
  public.sales_order_items
from authenticated;

revoke all on
  public.quotation_totals,
  public.sales_order_totals
from anon;

revoke all on
  public.quotation_totals,
  public.sales_order_totals
from authenticated;

grant select, insert, update, delete on
  public.quotations,
  public.quotation_items,
  public.sales_orders,
  public.sales_order_items
to authenticated;

grant select on
  public.quotation_totals,
  public.sales_order_totals
to authenticated;

grant all on
  public.quotations,
  public.quotation_items,
  public.sales_orders,
  public.sales_order_items,
  public.quotation_totals,
  public.sales_order_totals
to service_role;

-- Quotations are a SALES-owned workflow. ACCOUNTING does not require direct
-- quotation access under the locked V1 role definition.
create policy quotations_select_sales_or_owner
on public.quotations
for select
to authenticated
using (
  public.current_user_has_role('OWNER_ADMIN')
  or public.current_user_has_role('SALES')
);

create policy quotations_mutate_sales_or_owner
on public.quotations
for all
to authenticated
using (
  public.current_user_has_role('OWNER_ADMIN')
  or public.current_user_has_role('SALES')
)
with check (
  public.current_user_has_role('OWNER_ADMIN')
  or public.current_user_has_role('SALES')
);

create policy quotation_items_select_sales_or_owner
on public.quotation_items
for select
to authenticated
using (
  public.current_user_has_role('OWNER_ADMIN')
  or public.current_user_has_role('SALES')
);

create policy quotation_items_mutate_sales_or_owner
on public.quotation_items
for all
to authenticated
using (
  public.current_user_has_role('OWNER_ADMIN')
  or public.current_user_has_role('SALES')
)
with check (
  public.current_user_has_role('OWNER_ADMIN')
  or public.current_user_has_role('SALES')
);

-- Sales orders are managed by SALES/OWNER. ACCOUNTING receives read-only
-- visibility required for order financial state and operational reporting.
create policy sales_orders_select_authorized_roles
on public.sales_orders
for select
to authenticated
using (
  public.current_user_has_role('OWNER_ADMIN')
  or public.current_user_has_role('SALES')
  or public.current_user_has_role('ACCOUNTING')
);

create policy sales_orders_mutate_sales_or_owner
on public.sales_orders
for all
to authenticated
using (
  public.current_user_has_role('OWNER_ADMIN')
  or public.current_user_has_role('SALES')
)
with check (
  public.current_user_has_role('OWNER_ADMIN')
  or public.current_user_has_role('SALES')
);

create policy sales_order_items_select_authorized_roles
on public.sales_order_items
for select
to authenticated
using (
  public.current_user_has_role('OWNER_ADMIN')
  or public.current_user_has_role('SALES')
  or public.current_user_has_role('ACCOUNTING')
);

create policy sales_order_items_mutate_sales_or_owner
on public.sales_order_items
for all
to authenticated
using (
  public.current_user_has_role('OWNER_ADMIN')
  or public.current_user_has_role('SALES')
)
with check (
  public.current_user_has_role('OWNER_ADMIN')
  or public.current_user_has_role('SALES')
);

commit;
