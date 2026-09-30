-- OPS-021: goods-receipt operational workflow
-- Architecture Generation 1
-- Source of Truth: SOURCE_OF_TRUTH.md
--
-- This migration adds only the receiving-specific security/integrity bridge
-- required by OPS-021. Inventory posting remains OPS-022.
--
-- Design:
-- - WAREHOUSE must receive against PO lines without seeing purchase costs.
-- - A private SECURITY DEFINER function returns a strictly sanitized projection;
--   a public security-invoker view exposes only that projection to authenticated
--   roles already permitted by the function.
-- - Receipt creation enforces the locked V1 flow: supplier payment recorded
--   before goods are received.
-- - Receipt items must belong to the receipt's PO and must preserve the PO
--   package-to-base conversion.
-- - received_by_user_id is attributed from auth.uid().
-- - purchase_orders.actual_receipt_date is derived from receipts that contain
--   at least one received line.
-- - No inventory movement is created here.

begin;

create schema if not exists private;

revoke all on schema private from public, anon;
grant usage on schema private to authenticated, service_role;

create or replace function private.goods_receipt_source_lines()
returns table (
  purchase_order_id uuid,
  po_number text,
  supplier_id uuid,
  supplier_name text,
  po_status text,
  order_date date,
  expected_receipt_date date,
  payment_ready boolean,
  purchase_order_item_id uuid,
  product_variant_id uuid,
  sku_code text,
  variant_name text,
  product_name text,
  packaging_id uuid,
  package_name text,
  purchase_unit text,
  ordered_package_quantity numeric,
  units_per_purchase_unit numeric,
  ordered_base_quantity numeric,
  received_package_quantity numeric,
  remaining_package_quantity numeric,
  received_base_quantity numeric,
  remaining_base_quantity numeric
)
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $$
  with receipt_totals as (
    select
      gri.purchase_order_item_id,
      coalesce(sum(gri.package_quantity), 0::numeric) as received_package_quantity,
      coalesce(sum(gri.base_quantity), 0::numeric) as received_base_quantity
    from public.goods_receipt_items gri
    group by gri.purchase_order_item_id
  ),
  po_payment as (
    select
      po.id as purchase_order_id,
      (
        coalesce(
          (
            select sum(pp.amount)
            from public.purchase_payments pp
            where pp.purchase_order_id = po.id
          ),
          0::numeric
        ) + 0.000001::numeric
        >=
        coalesce(
          (
            select sum(poi2.line_subtotal)
            from public.purchase_order_items poi2
            where poi2.purchase_order_id = po.id
          ),
          0::numeric
        ) + po.freight_amount
      ) as payment_ready
    from public.purchase_orders po
  )
  select
    po.id,
    po.po_number,
    po.supplier_id,
    s.supplier_name,
    po.status,
    po.order_date,
    po.expected_receipt_date,
    pay.payment_ready,
    poi.id,
    poi.product_variant_id,
    pv.sku_code,
    pv.variant_name,
    p.name,
    poi.packaging_id,
    ppkg.package_name,
    poi.purchase_unit,
    poi.package_quantity,
    poi.units_per_purchase_unit,
    poi.base_quantity,
    coalesce(rt.received_package_quantity, 0::numeric),
    poi.package_quantity - coalesce(rt.received_package_quantity, 0::numeric),
    coalesce(rt.received_base_quantity, 0::numeric),
    poi.base_quantity - coalesce(rt.received_base_quantity, 0::numeric)
  from public.purchase_orders po
  join public.suppliers s
    on s.id = po.supplier_id
  join public.purchase_order_items poi
    on poi.purchase_order_id = po.id
  join public.product_variants pv
    on pv.id = poi.product_variant_id
  join public.products p
    on p.id = pv.product_id
  left join public.product_packaging ppkg
    on ppkg.id = poi.packaging_id
  left join receipt_totals rt
    on rt.purchase_order_item_id = poi.id
  join po_payment pay
    on pay.purchase_order_id = po.id
  where
    (select auth.uid()) is not null
    and (
      public.current_user_has_role('OWNER_ADMIN')
      or public.current_user_has_role('WAREHOUSE')
      or public.current_user_has_role('ACCOUNTING')
    );
$$;

revoke all on function private.goods_receipt_source_lines()
from public, anon;
grant execute on function private.goods_receipt_source_lines()
to authenticated, service_role;

create or replace view public.goods_receipt_source_lines
with (security_invoker = true)
as
select *
from private.goods_receipt_source_lines();

revoke all on public.goods_receipt_source_lines from public, anon;
grant select on public.goods_receipt_source_lines to authenticated, service_role;

create or replace function private.guard_goods_receipt_header()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  v_status text;
  v_total numeric;
  v_paid numeric;
begin
  if tg_op = 'INSERT' then
    if (select auth.uid()) is not null then
      new.received_by_user_id := (select auth.uid());
    end if;

    select
      po.status,
      coalesce(
        (
          select sum(poi.line_subtotal)
          from public.purchase_order_items poi
          where poi.purchase_order_id = po.id
        ),
        0::numeric
      ) + po.freight_amount,
      coalesce(
        (
          select sum(pp.amount)
          from public.purchase_payments pp
          where pp.purchase_order_id = po.id
        ),
        0::numeric
      )
    into v_status, v_total, v_paid
    from public.purchase_orders po
    where po.id = new.purchase_order_id;

    if not found then
      raise exception 'Purchase order % does not exist', new.purchase_order_id;
    end if;

    if v_status = 'CANCELLED' then
      raise exception 'Cannot receive a cancelled purchase order';
    end if;

    if v_paid + 0.000001::numeric < v_total then
      raise exception 'Supplier payment must be recorded before goods receipt';
    end if;

    return new;
  end if;

  if new.purchase_order_id is distinct from old.purchase_order_id then
    raise exception 'Goods receipt purchase order linkage is immutable';
  end if;

  new.received_by_user_id := old.received_by_user_id;
  return new;
end;
$$;

revoke all on function private.guard_goods_receipt_header()
from public, anon, authenticated;

drop trigger if exists goods_receipts_guard_header
on public.goods_receipts;

create trigger goods_receipts_guard_header
before insert or update on public.goods_receipts
for each row execute function private.guard_goods_receipt_header();

create or replace function private.guard_goods_receipt_item_integrity()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  v_receipt_po_id uuid;
  v_item_po_id uuid;
  v_units_per_purchase_unit numeric;
begin
  if tg_op = 'DELETE' then
    if exists (
      select 1
      from public.inventory_movements im
      where im.goods_receipt_item_id = old.id
    ) then
      raise exception 'Posted goods receipt items are immutable; use an inventory adjustment workflow';
    end if;
    return old;
  end if;

  if tg_op = 'UPDATE' and exists (
    select 1
    from public.inventory_movements im
    where im.goods_receipt_item_id = old.id
  ) then
    raise exception 'Posted goods receipt items are immutable; use an inventory adjustment workflow';
  end if;

  select gr.purchase_order_id
  into v_receipt_po_id
  from public.goods_receipts gr
  where gr.id = new.goods_receipt_id;

  if not found then
    raise exception 'Goods receipt % does not exist', new.goods_receipt_id;
  end if;

  select
    poi.purchase_order_id,
    poi.units_per_purchase_unit
  into
    v_item_po_id,
    v_units_per_purchase_unit
  from public.purchase_order_items poi
  where poi.id = new.purchase_order_item_id;

  if not found then
    raise exception 'Purchase order item % does not exist', new.purchase_order_item_id;
  end if;

  if v_item_po_id is distinct from v_receipt_po_id then
    raise exception 'Goods receipt item must belong to the same purchase order as its receipt';
  end if;

  if new.units_per_purchase_unit is distinct from v_units_per_purchase_unit then
    raise exception 'Goods receipt conversion must match the source purchase-order line';
  end if;

  return new;
end;
$$;

revoke all on function private.guard_goods_receipt_item_integrity()
from public, anon, authenticated;

drop trigger if exists goods_receipt_items_guard_integrity
on public.goods_receipt_items;

create trigger goods_receipt_items_guard_integrity
before insert or update or delete on public.goods_receipt_items
for each row execute function private.guard_goods_receipt_item_integrity();

create or replace function private.recalculate_purchase_order_actual_receipt_date(
  p_purchase_order_id uuid
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  v_actual_date date;
begin
  select max(gr.received_at::date)
  into v_actual_date
  from public.goods_receipts gr
  where gr.purchase_order_id = p_purchase_order_id
    and exists (
      select 1
      from public.goods_receipt_items gri
      where gri.goods_receipt_id = gr.id
    );

  update public.purchase_orders po
  set actual_receipt_date = v_actual_date
  where po.id = p_purchase_order_id
    and po.actual_receipt_date is distinct from v_actual_date;
end;
$$;

revoke all on function private.recalculate_purchase_order_actual_receipt_date(uuid)
from public, anon, authenticated;

create or replace function private.sync_po_receipt_date_from_receipt()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
begin
  if tg_op = 'DELETE' then
    perform private.recalculate_purchase_order_actual_receipt_date(old.purchase_order_id);
    return old;
  end if;

  perform private.recalculate_purchase_order_actual_receipt_date(new.purchase_order_id);
  return new;
end;
$$;

revoke all on function private.sync_po_receipt_date_from_receipt()
from public, anon, authenticated;

drop trigger if exists goods_receipts_sync_po_actual_date
on public.goods_receipts;

create trigger goods_receipts_sync_po_actual_date
after insert or update or delete on public.goods_receipts
for each row execute function private.sync_po_receipt_date_from_receipt();

create or replace function private.sync_po_receipt_date_from_item()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  v_old_po_id uuid;
  v_new_po_id uuid;
begin
  if tg_op in ('UPDATE', 'DELETE') then
    select gr.purchase_order_id
    into v_old_po_id
    from public.goods_receipts gr
    where gr.id = old.goods_receipt_id;
  end if;

  if tg_op in ('INSERT', 'UPDATE') then
    select gr.purchase_order_id
    into v_new_po_id
    from public.goods_receipts gr
    where gr.id = new.goods_receipt_id;
  end if;

  if v_old_po_id is not null then
    perform private.recalculate_purchase_order_actual_receipt_date(v_old_po_id);
  end if;

  if v_new_po_id is not null and v_new_po_id is distinct from v_old_po_id then
    perform private.recalculate_purchase_order_actual_receipt_date(v_new_po_id);
  elsif v_new_po_id is not null and v_old_po_id is null then
    perform private.recalculate_purchase_order_actual_receipt_date(v_new_po_id);
  end if;

  return coalesce(new, old);
end;
$$;

revoke all on function private.sync_po_receipt_date_from_item()
from public, anon, authenticated;

drop trigger if exists goods_receipt_items_sync_po_actual_date
on public.goods_receipt_items;

create trigger goods_receipt_items_sync_po_actual_date
after insert or update or delete on public.goods_receipt_items
for each row execute function private.sync_po_receipt_date_from_item();

commit;
