-- OPS-022: immutable inventory-ledger operational workflow
-- Architecture Generation 1
-- Source of Truth: SOURCE_OF_TRUTH.md
--
-- Scope:
-- - post goods-receipt lines exactly once into the immutable ledger;
-- - validate SKU/base quantity against the receipt source at the database boundary;
-- - derive stock only from inventory movements;
-- - automatically append purchase-cost history after a receipt is posted;
-- - keep the inventory costing basis NULL because SOT Section 7 defers the
--   authoritative costing method;
-- - reservation/release/issue remain OPS-023 and stocktake/adjustment remain OPS-024.

begin;

revoke all on public.inventory_stock_snapshot from public, anon;
grant select on public.inventory_stock_snapshot to authenticated, service_role;

create or replace function private.guard_inventory_goods_receipt_post()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  v_product_variant_id uuid;
  v_base_quantity numeric(18,6);
  v_received_at timestamptz;
  v_goods_receipt_number text;
begin
  if (select auth.uid()) is not null then
    new.created_by_user_id := (select auth.uid());
  end if;

  if new.movement_type <> 'GOODS_RECEIPT' then
    return new;
  end if;

  select
    poi.product_variant_id,
    gri.base_quantity,
    gr.received_at,
    gr.goods_receipt_number
  into
    v_product_variant_id,
    v_base_quantity,
    v_received_at,
    v_goods_receipt_number
  from public.goods_receipt_items gri
  join public.goods_receipts gr
    on gr.id = gri.goods_receipt_id
  join public.purchase_order_items poi
    on poi.id = gri.purchase_order_item_id
  where gri.id = new.goods_receipt_item_id;

  if not found then
    raise exception 'Goods receipt item % does not exist', new.goods_receipt_item_id;
  end if;

  if new.product_variant_id is distinct from v_product_variant_id then
    raise exception 'Inventory GOODS_RECEIPT SKU must match the receipt source';
  end if;

  if new.quantity_delta_base_units is distinct from v_base_quantity then
    raise exception 'Inventory GOODS_RECEIPT quantity must equal the receipt base quantity';
  end if;

  new.occurred_at := v_received_at;
  new.reference := coalesce(
    nullif(btrim(new.reference), ''),
    'GOODS_RECEIPT:' || v_goods_receipt_number
  );

  return new;
end;
$$;

revoke all on function private.guard_inventory_goods_receipt_post()
from public, anon, authenticated;

drop trigger if exists inventory_movements_guard_goods_receipt_source
on public.inventory_movements;

create trigger inventory_movements_guard_goods_receipt_source
before insert on public.inventory_movements
for each row execute function private.guard_inventory_goods_receipt_post();

create or replace function private.post_goods_receipt_cost_history()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  v_supplier_id uuid;
  v_po_number text;
  v_currency_code text;
  v_po_freight numeric(18,6);
  v_po_merchandise_total numeric(18,6);
  v_line_subtotal numeric(18,6);
  v_ordered_package_quantity numeric(18,6);
  v_product_variant_id uuid;
  v_packaging_id uuid;
  v_purchase_unit text;
  v_units_per_purchase_unit numeric(18,6);
  v_unit_cost numeric(18,6);
  v_received_at timestamptz;
  v_goods_receipt_number text;
  v_freight_per_purchase_unit numeric(18,6);
begin
  if new.movement_type <> 'GOODS_RECEIPT' then
    return new;
  end if;

  select
    po.supplier_id,
    po.po_number,
    po.currency_code,
    po.freight_amount,
    (
      select coalesce(sum(poi_total.line_subtotal), 0::numeric)
      from public.purchase_order_items poi_total
      where poi_total.purchase_order_id = po.id
    ),
    poi.line_subtotal,
    poi.package_quantity,
    poi.product_variant_id,
    poi.packaging_id,
    poi.purchase_unit,
    poi.units_per_purchase_unit,
    poi.unit_cost_per_purchase_unit,
    gr.received_at,
    gr.goods_receipt_number
  into
    v_supplier_id,
    v_po_number,
    v_currency_code,
    v_po_freight,
    v_po_merchandise_total,
    v_line_subtotal,
    v_ordered_package_quantity,
    v_product_variant_id,
    v_packaging_id,
    v_purchase_unit,
    v_units_per_purchase_unit,
    v_unit_cost,
    v_received_at,
    v_goods_receipt_number
  from public.goods_receipt_items gri
  join public.goods_receipts gr
    on gr.id = gri.goods_receipt_id
  join public.purchase_order_items poi
    on poi.id = gri.purchase_order_item_id
  join public.purchase_orders po
    on po.id = poi.purchase_order_id
  where gri.id = new.goods_receipt_item_id;

  if not found then
    raise exception 'Cannot derive purchase cost from goods receipt item %', new.goods_receipt_item_id;
  end if;

  v_freight_per_purchase_unit :=
    case
      when v_po_merchandise_total > 0 and v_ordered_package_quantity > 0
        then (
          v_po_freight
          * (v_line_subtotal / v_po_merchandise_total)
        ) / v_ordered_package_quantity
      else 0::numeric
    end;

  insert into public.purchase_cost_history (
    product_variant_id,
    supplier_id,
    packaging_id,
    effective_at,
    purchase_unit,
    units_per_purchase_unit,
    purchase_price_per_purchase_unit,
    freight_cost_per_purchase_unit,
    other_allocated_cost_per_purchase_unit,
    inventory_cost_basis_per_base_unit,
    currency_code,
    source_reference,
    notes
  )
  values (
    v_product_variant_id,
    v_supplier_id,
    v_packaging_id,
    v_received_at,
    v_purchase_unit,
    v_units_per_purchase_unit,
    v_unit_cost,
    v_freight_per_purchase_unit,
    0,
    null,
    v_currency_code,
    'GOODS_RECEIPT:' || v_goods_receipt_number || '/PO:' || v_po_number,
    'Automatically appended by OPS-022 when the receipt line was posted to inventory. '
      || 'PO freight is allocated pro-rata by merchandise line subtotal. '
      || 'inventory_cost_basis_per_base_unit remains NULL until the authoritative costing method is selected in SOT.'
  );

  return new;
end;
$$;

revoke all on function private.post_goods_receipt_cost_history()
from public, anon, authenticated;

drop trigger if exists inventory_movements_post_goods_receipt_cost_history
on public.inventory_movements;

create trigger inventory_movements_post_goods_receipt_cost_history
after insert on public.inventory_movements
for each row execute function private.post_goods_receipt_cost_history();

commit;
