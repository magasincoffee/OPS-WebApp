-- OPS-003 bounded unit: purchasing and warehouse RBAC policies
-- Architecture Generation 1
-- Source of Truth: SOURCE_OF_TRUTH.md
--
-- Scope is intentionally limited to purchasing, goods receipt, inventory,
-- reservation, and stocktake tables. Sales, production, customer finance,
-- delivery, operational tasks, and representative permission verification
-- remain later bounded units inside OPS-003.
--
-- Cost-protection rule:
-- purchase_orders / purchase_order_items / purchase_payments contain financial
-- or cost information and are not exposed directly to WAREHOUSE.
-- WAREHOUSE receives direct access only to goods-receipt and inventory-domain
-- records required by its operational responsibilities.

begin;

revoke all on
  public.purchase_orders,
  public.purchase_order_items,
  public.purchase_payments,
  public.goods_receipts,
  public.goods_receipt_items,
  public.inventory_reservations,
  public.inventory_movements,
  public.stocktakes,
  public.stocktake_items
from anon;

revoke all on
  public.purchase_orders,
  public.purchase_order_items,
  public.purchase_payments,
  public.goods_receipts,
  public.goods_receipt_items,
  public.inventory_reservations,
  public.inventory_movements,
  public.stocktakes,
  public.stocktake_items
from authenticated;

grant select, insert, update, delete on
  public.purchase_orders,
  public.purchase_order_items,
  public.purchase_payments,
  public.goods_receipts,
  public.goods_receipt_items,
  public.inventory_reservations,
  public.stocktakes,
  public.stocktake_items
to authenticated;

grant select, insert on public.inventory_movements to authenticated;

grant all on
  public.purchase_orders,
  public.purchase_order_items,
  public.purchase_payments,
  public.goods_receipts,
  public.goods_receipt_items,
  public.inventory_reservations,
  public.inventory_movements,
  public.stocktakes,
  public.stocktake_items
to service_role;

-- Purchasing financial records: OWNER_ADMIN controls mutations.
-- ACCOUNTING may read these records for financial operational visibility.
create policy purchase_orders_select_financial_roles
on public.purchase_orders
for select
to authenticated
using (
  public.current_user_has_role('OWNER_ADMIN')
  or public.current_user_has_role('ACCOUNTING')
);

create policy purchase_orders_mutate_owner_admin
on public.purchase_orders
for all
to authenticated
using (public.current_user_has_role('OWNER_ADMIN'))
with check (public.current_user_has_role('OWNER_ADMIN'));

create policy purchase_order_items_select_financial_roles
on public.purchase_order_items
for select
to authenticated
using (
  public.current_user_has_role('OWNER_ADMIN')
  or public.current_user_has_role('ACCOUNTING')
);

create policy purchase_order_items_mutate_owner_admin
on public.purchase_order_items
for all
to authenticated
using (public.current_user_has_role('OWNER_ADMIN'))
with check (public.current_user_has_role('OWNER_ADMIN'));

create policy purchase_payments_select_financial_roles
on public.purchase_payments
for select
to authenticated
using (
  public.current_user_has_role('OWNER_ADMIN')
  or public.current_user_has_role('ACCOUNTING')
);

create policy purchase_payments_mutate_owner_admin
on public.purchase_payments
for all
to authenticated
using (public.current_user_has_role('OWNER_ADMIN'))
with check (public.current_user_has_role('OWNER_ADMIN'));

-- Goods receipt is a warehouse responsibility. ACCOUNTING may read receipt
-- evidence/history, while mutations stay with OWNER_ADMIN/WAREHOUSE.
create policy goods_receipts_select_operational_roles
on public.goods_receipts
for select
to authenticated
using (
  public.current_user_has_role('OWNER_ADMIN')
  or public.current_user_has_role('ACCOUNTING')
  or public.current_user_has_role('WAREHOUSE')
);

create policy goods_receipts_mutate_warehouse_or_owner
on public.goods_receipts
for all
to authenticated
using (
  public.current_user_has_role('OWNER_ADMIN')
  or public.current_user_has_role('WAREHOUSE')
)
with check (
  public.current_user_has_role('OWNER_ADMIN')
  or public.current_user_has_role('WAREHOUSE')
);

create policy goods_receipt_items_select_operational_roles
on public.goods_receipt_items
for select
to authenticated
using (
  public.current_user_has_role('OWNER_ADMIN')
  or public.current_user_has_role('ACCOUNTING')
  or public.current_user_has_role('WAREHOUSE')
);

create policy goods_receipt_items_mutate_warehouse_or_owner
on public.goods_receipt_items
for all
to authenticated
using (
  public.current_user_has_role('OWNER_ADMIN')
  or public.current_user_has_role('WAREHOUSE')
)
with check (
  public.current_user_has_role('OWNER_ADMIN')
  or public.current_user_has_role('WAREHOUSE')
);

-- Inventory reservations and ledger are warehouse-domain operational records.
create policy inventory_reservations_select_warehouse_or_owner
on public.inventory_reservations
for select
to authenticated
using (
  public.current_user_has_role('OWNER_ADMIN')
  or public.current_user_has_role('WAREHOUSE')
);

create policy inventory_reservations_mutate_warehouse_or_owner
on public.inventory_reservations
for all
to authenticated
using (
  public.current_user_has_role('OWNER_ADMIN')
  or public.current_user_has_role('WAREHOUSE')
)
with check (
  public.current_user_has_role('OWNER_ADMIN')
  or public.current_user_has_role('WAREHOUSE')
);

create policy inventory_movements_select_warehouse_or_owner
on public.inventory_movements
for select
to authenticated
using (
  public.current_user_has_role('OWNER_ADMIN')
  or public.current_user_has_role('WAREHOUSE')
);

create policy inventory_movements_insert_warehouse_or_owner
on public.inventory_movements
for insert
to authenticated
with check (
  public.current_user_has_role('OWNER_ADMIN')
  or public.current_user_has_role('WAREHOUSE')
);

-- No UPDATE/DELETE policy is created for inventory_movements.
-- The ledger is append-only and existing database triggers reject mutation.

create policy stocktakes_select_warehouse_or_owner
on public.stocktakes
for select
to authenticated
using (
  public.current_user_has_role('OWNER_ADMIN')
  or public.current_user_has_role('WAREHOUSE')
);

create policy stocktakes_mutate_warehouse_or_owner
on public.stocktakes
for all
to authenticated
using (
  public.current_user_has_role('OWNER_ADMIN')
  or public.current_user_has_role('WAREHOUSE')
)
with check (
  public.current_user_has_role('OWNER_ADMIN')
  or public.current_user_has_role('WAREHOUSE')
);

create policy stocktake_items_select_warehouse_or_owner
on public.stocktake_items
for select
to authenticated
using (
  public.current_user_has_role('OWNER_ADMIN')
  or public.current_user_has_role('WAREHOUSE')
);

create policy stocktake_items_mutate_warehouse_or_owner
on public.stocktake_items
for all
to authenticated
using (
  public.current_user_has_role('OWNER_ADMIN')
  or public.current_user_has_role('WAREHOUSE')
)
with check (
  public.current_user_has_role('OWNER_ADMIN')
  or public.current_user_has_role('WAREHOUSE')
);

commit;
