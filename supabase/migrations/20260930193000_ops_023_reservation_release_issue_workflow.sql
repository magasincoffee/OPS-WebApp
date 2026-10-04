-- OPS-023: reservation / release / issue workflow
-- Architecture Generation 1
-- Source of Truth: SOURCE_OF_TRUTH.md
--
-- Scope:
-- - expose a non-financial warehouse reservation queue through a bounded RPC;
-- - reserve confirmed sales-order lines without exposing selling prices to WAREHOUSE;
-- - append partial/full reservation, release, and issue movements to the immutable ledger;
-- - validate all reservation movements against their source order line at the database boundary;
-- - synchronize sales_orders.warehouse_status from inventory truth;
-- - prevent SKU/quantity source drift once a sales-order item is linked to inventory;
-- - stocktake/adjustment/low-stock remain OPS-024.

begin;

create unique index if not exists inventory_reservations_one_per_sales_order_item
  on public.inventory_reservations(sales_order_item_id);

-- Reservation rows are created only by the bounded RPC below. WAREHOUSE keeps
-- read access through existing RLS, but cannot forge or rewrite reservation sources.
revoke insert, update, delete on public.inventory_reservations from authenticated;
grant select on public.inventory_reservations to authenticated;

create or replace function private.guard_sales_inventory_movement()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  v_sales_order_item_id uuid;
  v_product_variant_id uuid;
  v_requested_base_quantity numeric(18,6);
  v_order_base_quantity numeric(18,6);
  v_order_status text;
  v_order_number text;
  v_reserved_balance numeric(18,6);
  v_issued_quantity numeric(18,6);
begin
  if new.movement_type not in ('SALES_RESERVATION', 'RESERVATION_RELEASE', 'SALES_ISSUE') then
    return new;
  end if;

  perform pg_advisory_xact_lock(hashtextextended(new.inventory_reservation_id::text, 23));

  select
    ir.sales_order_item_id,
    ir.product_variant_id,
    ir.requested_base_quantity,
    soi.base_quantity,
    so.order_status,
    so.order_number
  into
    v_sales_order_item_id,
    v_product_variant_id,
    v_requested_base_quantity,
    v_order_base_quantity,
    v_order_status,
    v_order_number
  from public.inventory_reservations ir
  join public.sales_order_items soi on soi.id = ir.sales_order_item_id
  join public.sales_orders so on so.id = soi.sales_order_id
  where ir.id = new.inventory_reservation_id;

  if not found then
    raise exception 'Inventory reservation % does not exist', new.inventory_reservation_id;
  end if;

  if new.sales_order_item_id is distinct from v_sales_order_item_id then
    raise exception 'Inventory movement sales-order item must match its reservation source';
  end if;

  if new.product_variant_id is distinct from v_product_variant_id then
    raise exception 'Inventory movement SKU must match its reservation source';
  end if;

  if v_requested_base_quantity is distinct from v_order_base_quantity then
    raise exception 'Inventory reservation source quantity no longer matches the sales-order item';
  end if;

  select
    coalesce(sum(
      case
        when im.movement_type in ('SALES_RESERVATION', 'RESERVATION_RELEASE', 'SALES_ISSUE')
          then im.quantity_delta_base_units
        else 0::numeric
      end
    ), 0::numeric),
    coalesce(sum(
      case
        when im.movement_type = 'SALES_ISSUE'
          then -im.quantity_delta_base_units
        else 0::numeric
      end
    ), 0::numeric)
  into v_reserved_balance, v_issued_quantity
  from public.inventory_movements im
  where im.inventory_reservation_id = new.inventory_reservation_id;

  if new.movement_type = 'SALES_RESERVATION' then
    if v_order_status <> 'CONFIRMED' then
      raise exception 'Only CONFIRMED sales orders may reserve inventory';
    end if;

    if v_reserved_balance + v_issued_quantity + new.quantity_delta_base_units > v_requested_base_quantity then
      raise exception 'Reservation would exceed the sales-order item base quantity';
    end if;
  elsif new.movement_type = 'RESERVATION_RELEASE' then
    if -new.quantity_delta_base_units > v_reserved_balance then
      raise exception 'Release would exceed the currently reserved quantity';
    end if;
  elsif new.movement_type = 'SALES_ISSUE' then
    if v_order_status <> 'CONFIRMED' then
      raise exception 'Only CONFIRMED sales orders may issue inventory';
    end if;

    if -new.quantity_delta_base_units > v_reserved_balance then
      raise exception 'Issue would exceed the currently reserved quantity';
    end if;

    if v_issued_quantity - new.quantity_delta_base_units > v_requested_base_quantity then
      raise exception 'Issue would exceed the sales-order item base quantity';
    end if;
  end if;

  if (select auth.uid()) is not null then
    new.created_by_user_id := (select auth.uid());
  end if;

  new.reference := coalesce(
    nullif(btrim(new.reference), ''),
    'SALES_ORDER:' || v_order_number
  );

  return new;
end;
$$;

revoke all on function private.guard_sales_inventory_movement()
from public, anon, authenticated;

drop trigger if exists inventory_movements_guard_sales_source
on public.inventory_movements;

create trigger inventory_movements_guard_sales_source
before insert on public.inventory_movements
for each row execute function private.guard_sales_inventory_movement();

create or replace function private.refresh_sales_order_warehouse_status(
  p_sales_order_id uuid
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  v_line_count integer;
  v_all_issued boolean;
  v_all_allocated boolean;
  v_status text;
begin
  select
    count(*)::integer,
    coalesce(bool_and(state.issued_quantity >= soi.base_quantity), false),
    coalesce(bool_and(
      state.issued_quantity + state.reserved_balance_quantity >= soi.base_quantity
    ), false)
  into v_line_count, v_all_issued, v_all_allocated
  from public.sales_order_items soi
  left join lateral (
    select
      coalesce(sum(
        case
          when im.movement_type in ('SALES_RESERVATION', 'RESERVATION_RELEASE', 'SALES_ISSUE')
            then im.quantity_delta_base_units
          else 0::numeric
        end
      ), 0::numeric) as reserved_balance_quantity,
      coalesce(sum(
        case
          when im.movement_type = 'SALES_ISSUE'
            then -im.quantity_delta_base_units
          else 0::numeric
        end
      ), 0::numeric) as issued_quantity
    from public.inventory_reservations ir
    left join public.inventory_movements im
      on im.inventory_reservation_id = ir.id
    where ir.sales_order_item_id = soi.id
  ) state on true
  where soi.sales_order_id = p_sales_order_id;

  if v_line_count = 0 then
    v_status := 'NOT_RESERVED';
  elsif v_all_issued then
    v_status := 'ISSUED';
  elsif v_all_allocated then
    v_status := 'RESERVED';
  else
    v_status := 'NOT_RESERVED';
  end if;

  update public.sales_orders
  set warehouse_status = v_status
  where id = p_sales_order_id
    and warehouse_status is distinct from v_status;
end;
$$;

revoke all on function private.refresh_sales_order_warehouse_status(uuid)
from public, anon, authenticated;

create or replace function private.sync_sales_order_warehouse_status_from_inventory()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  v_sales_order_id uuid;
begin
  if new.movement_type not in ('SALES_RESERVATION', 'RESERVATION_RELEASE', 'SALES_ISSUE') then
    return new;
  end if;

  select soi.sales_order_id
  into v_sales_order_id
  from public.sales_order_items soi
  where soi.id = new.sales_order_item_id;

  if v_sales_order_id is not null then
    perform private.refresh_sales_order_warehouse_status(v_sales_order_id);
  end if;

  return new;
end;
$$;

revoke all on function private.sync_sales_order_warehouse_status_from_inventory()
from public, anon, authenticated;

drop trigger if exists inventory_movements_sync_sales_order_warehouse_status
on public.inventory_movements;

create trigger inventory_movements_sync_sales_order_warehouse_status
after insert on public.inventory_movements
for each row execute function private.sync_sales_order_warehouse_status_from_inventory();

create or replace function private.guard_inventory_linked_sales_order_item_source()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  v_has_inventory_link boolean;
begin
  select exists(
    select 1
    from public.inventory_reservations ir
    where ir.sales_order_item_id = old.id
  ) or exists(
    select 1
    from public.inventory_movements im
    where im.sales_order_item_id = old.id
  )
  into v_has_inventory_link;

  if not v_has_inventory_link then
    return case when tg_op = 'DELETE' then old else new end;
  end if;

  if tg_op = 'DELETE' then
    raise exception 'Cannot delete a sales-order item after inventory activity exists';
  end if;

  if new.product_variant_id is distinct from old.product_variant_id
    or new.packaging_id is distinct from old.packaging_id
    or new.sale_unit is distinct from old.sale_unit
    or new.sale_quantity is distinct from old.sale_quantity
    or new.units_per_sale_unit is distinct from old.units_per_sale_unit
  then
    raise exception 'Cannot change SKU or quantity fields after inventory activity exists';
  end if;

  return new;
end;
$$;

revoke all on function private.guard_inventory_linked_sales_order_item_source()
from public, anon, authenticated;

drop trigger if exists sales_order_items_guard_inventory_linked_source
on public.sales_order_items;

create trigger sales_order_items_guard_inventory_linked_source
before update or delete on public.sales_order_items
for each row execute function private.guard_inventory_linked_sales_order_item_source();

create or replace function public.inventory_reservation_work_queue()
returns table (
  sales_order_item_id uuid,
  sales_order_id uuid,
  inventory_reservation_id uuid,
  order_number text,
  order_status text,
  warehouse_status text,
  requested_due_date date,
  product_variant_id uuid,
  sku_code text,
  variant_name text,
  product_name text,
  base_inventory_unit text,
  base_quantity numeric,
  issued_quantity numeric,
  reserved_balance_quantity numeric,
  outstanding_quantity numeric,
  available_quantity numeric
)
language plpgsql
stable
security definer
set search_path = pg_catalog, pg_temp
as $$
begin
  if not (
    public.current_user_has_role('OWNER_ADMIN')
    or public.current_user_has_role('WAREHOUSE')
  ) then
    raise exception 'Inventory reservation queue requires OWNER_ADMIN or WAREHOUSE role'
      using errcode = '42501';
  end if;

  return query
  with reservation_state as (
    select
      ir.id as reservation_id,
      ir.sales_order_item_id,
      coalesce(sum(
        case
          when im.movement_type in ('SALES_RESERVATION', 'RESERVATION_RELEASE', 'SALES_ISSUE')
            then im.quantity_delta_base_units
          else 0::numeric
        end
      ), 0::numeric) as reserved_balance,
      coalesce(sum(
        case
          when im.movement_type = 'SALES_ISSUE'
            then -im.quantity_delta_base_units
          else 0::numeric
        end
      ), 0::numeric) as issued_quantity
    from public.inventory_reservations ir
    left join public.inventory_movements im
      on im.inventory_reservation_id = ir.id
    group by ir.id, ir.sales_order_item_id
  )
  select
    soi.id,
    so.id,
    rs.reservation_id,
    so.order_number,
    so.order_status,
    so.warehouse_status,
    coalesce(soi.requested_due_date, so.requested_due_date),
    soi.product_variant_id,
    pv.sku_code,
    pv.variant_name,
    p.name,
    pv.base_inventory_unit,
    soi.base_quantity,
    coalesce(rs.issued_quantity, 0::numeric),
    coalesce(rs.reserved_balance, 0::numeric),
    greatest(
      soi.base_quantity
        - coalesce(rs.issued_quantity, 0::numeric)
        - coalesce(rs.reserved_balance, 0::numeric),
      0::numeric
    ),
    coalesce(stock.available_quantity, 0::numeric)
  from public.sales_order_items soi
  join public.sales_orders so on so.id = soi.sales_order_id
  join public.product_variants pv on pv.id = soi.product_variant_id
  join public.products p on p.id = pv.product_id
  left join reservation_state rs on rs.sales_order_item_id = soi.id
  left join public.inventory_stock_snapshot stock
    on stock.product_variant_id = soi.product_variant_id
  where so.order_status = 'CONFIRMED'
     or coalesce(rs.reserved_balance, 0::numeric) > 0
     or coalesce(rs.issued_quantity, 0::numeric) > 0
  order by
    coalesce(soi.requested_due_date, so.requested_due_date) asc nulls last,
    so.order_number asc,
    pv.sku_code asc;
end;
$$;

revoke all on function public.inventory_reservation_work_queue()
from public, anon;
grant execute on function public.inventory_reservation_work_queue()
to authenticated, service_role;

create or replace function public.reserve_sales_order_item(
  p_sales_order_item_id uuid,
  p_quantity numeric default null
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_reservation_id uuid;
  v_product_variant_id uuid;
  v_base_quantity numeric(18,6);
  v_order_status text;
  v_reserved_balance numeric(18,6);
  v_issued_quantity numeric(18,6);
  v_outstanding numeric(18,6);
  v_quantity numeric(18,6);
  v_available numeric(18,6);
begin
  if not (
    public.current_user_has_role('OWNER_ADMIN')
    or public.current_user_has_role('WAREHOUSE')
  ) then
    raise exception 'Reserve inventory requires OWNER_ADMIN or WAREHOUSE role'
      using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_sales_order_item_id::text, 24));

  select soi.product_variant_id, soi.base_quantity, so.order_status
  into v_product_variant_id, v_base_quantity, v_order_status
  from public.sales_order_items soi
  join public.sales_orders so on so.id = soi.sales_order_id
  where soi.id = p_sales_order_item_id;

  if not found then
    raise exception 'Sales-order item % does not exist', p_sales_order_item_id;
  end if;

  if v_order_status <> 'CONFIRMED' then
    raise exception 'Only CONFIRMED sales orders may reserve inventory';
  end if;

  insert into public.inventory_reservations (
    sales_order_item_id,
    product_variant_id,
    requested_base_quantity,
    created_by_user_id
  )
  values (
    p_sales_order_item_id,
    v_product_variant_id,
    v_base_quantity,
    v_user_id
  )
  on conflict (sales_order_item_id) do nothing
  returning id into v_reservation_id;

  if v_reservation_id is null then
    select ir.id
    into v_reservation_id
    from public.inventory_reservations ir
    where ir.sales_order_item_id = p_sales_order_item_id;
  end if;

  select
    coalesce(sum(
      case
        when im.movement_type in ('SALES_RESERVATION', 'RESERVATION_RELEASE', 'SALES_ISSUE')
          then im.quantity_delta_base_units
        else 0::numeric
      end
    ), 0::numeric),
    coalesce(sum(
      case
        when im.movement_type = 'SALES_ISSUE'
          then -im.quantity_delta_base_units
        else 0::numeric
      end
    ), 0::numeric)
  into v_reserved_balance, v_issued_quantity
  from public.inventory_movements im
  where im.inventory_reservation_id = v_reservation_id;

  v_outstanding := v_base_quantity - v_issued_quantity - v_reserved_balance;
  v_quantity := coalesce(p_quantity, v_outstanding);

  if v_quantity <= 0 then
    raise exception 'Reservation quantity must be positive';
  end if;

  if v_quantity > v_outstanding then
    raise exception 'Reservation quantity exceeds the outstanding sales-order quantity';
  end if;

  select coalesce(stock.available_quantity, 0::numeric)
  into v_available
  from public.inventory_stock_snapshot stock
  where stock.product_variant_id = v_product_variant_id;

  if coalesce(v_available, 0::numeric) < v_quantity then
    raise exception 'Insufficient available stock for reservation';
  end if;

  insert into public.inventory_movements (
    product_variant_id,
    movement_type,
    quantity_delta_base_units,
    inventory_reservation_id,
    sales_order_item_id,
    created_by_user_id
  )
  values (
    v_product_variant_id,
    'SALES_RESERVATION',
    v_quantity,
    v_reservation_id,
    p_sales_order_item_id,
    v_user_id
  );

  return v_reservation_id;
end;
$$;

revoke all on function public.reserve_sales_order_item(uuid, numeric)
from public, anon;
grant execute on function public.reserve_sales_order_item(uuid, numeric)
to authenticated, service_role;

create or replace function public.release_inventory_reservation(
  p_inventory_reservation_id uuid,
  p_quantity numeric default null
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_sales_order_item_id uuid;
  v_product_variant_id uuid;
  v_reserved_balance numeric(18,6);
  v_quantity numeric(18,6);
  v_movement_id uuid;
begin
  if not (
    public.current_user_has_role('OWNER_ADMIN')
    or public.current_user_has_role('WAREHOUSE')
  ) then
    raise exception 'Release inventory requires OWNER_ADMIN or WAREHOUSE role'
      using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_inventory_reservation_id::text, 25));

  select ir.sales_order_item_id, ir.product_variant_id
  into v_sales_order_item_id, v_product_variant_id
  from public.inventory_reservations ir
  where ir.id = p_inventory_reservation_id;

  if not found then
    raise exception 'Inventory reservation % does not exist', p_inventory_reservation_id;
  end if;

  select coalesce(sum(
    case
      when im.movement_type in ('SALES_RESERVATION', 'RESERVATION_RELEASE', 'SALES_ISSUE')
        then im.quantity_delta_base_units
      else 0::numeric
    end
  ), 0::numeric)
  into v_reserved_balance
  from public.inventory_movements im
  where im.inventory_reservation_id = p_inventory_reservation_id;

  v_quantity := coalesce(p_quantity, v_reserved_balance);

  if v_quantity <= 0 then
    raise exception 'Release quantity must be positive';
  end if;

  if v_quantity > v_reserved_balance then
    raise exception 'Release quantity exceeds the currently reserved quantity';
  end if;

  insert into public.inventory_movements (
    product_variant_id,
    movement_type,
    quantity_delta_base_units,
    inventory_reservation_id,
    sales_order_item_id,
    created_by_user_id
  )
  values (
    v_product_variant_id,
    'RESERVATION_RELEASE',
    -v_quantity,
    p_inventory_reservation_id,
    v_sales_order_item_id,
    v_user_id
  )
  returning id into v_movement_id;

  return v_movement_id;
end;
$$;

revoke all on function public.release_inventory_reservation(uuid, numeric)
from public, anon;
grant execute on function public.release_inventory_reservation(uuid, numeric)
to authenticated, service_role;

create or replace function public.issue_inventory_reservation(
  p_inventory_reservation_id uuid,
  p_quantity numeric default null
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_sales_order_item_id uuid;
  v_product_variant_id uuid;
  v_order_status text;
  v_reserved_balance numeric(18,6);
  v_quantity numeric(18,6);
  v_movement_id uuid;
begin
  if not (
    public.current_user_has_role('OWNER_ADMIN')
    or public.current_user_has_role('WAREHOUSE')
  ) then
    raise exception 'Issue inventory requires OWNER_ADMIN or WAREHOUSE role'
      using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_inventory_reservation_id::text, 26));

  select ir.sales_order_item_id, ir.product_variant_id, so.order_status
  into v_sales_order_item_id, v_product_variant_id, v_order_status
  from public.inventory_reservations ir
  join public.sales_order_items soi on soi.id = ir.sales_order_item_id
  join public.sales_orders so on so.id = soi.sales_order_id
  where ir.id = p_inventory_reservation_id;

  if not found then
    raise exception 'Inventory reservation % does not exist', p_inventory_reservation_id;
  end if;

  if v_order_status <> 'CONFIRMED' then
    raise exception 'Only CONFIRMED sales orders may issue inventory';
  end if;

  select coalesce(sum(
    case
      when im.movement_type in ('SALES_RESERVATION', 'RESERVATION_RELEASE', 'SALES_ISSUE')
        then im.quantity_delta_base_units
      else 0::numeric
    end
  ), 0::numeric)
  into v_reserved_balance
  from public.inventory_movements im
  where im.inventory_reservation_id = p_inventory_reservation_id;

  v_quantity := coalesce(p_quantity, v_reserved_balance);

  if v_quantity <= 0 then
    raise exception 'Issue quantity must be positive';
  end if;

  if v_quantity > v_reserved_balance then
    raise exception 'Issue quantity exceeds the currently reserved quantity';
  end if;

  insert into public.inventory_movements (
    product_variant_id,
    movement_type,
    quantity_delta_base_units,
    inventory_reservation_id,
    sales_order_item_id,
    created_by_user_id
  )
  values (
    v_product_variant_id,
    'SALES_ISSUE',
    -v_quantity,
    p_inventory_reservation_id,
    v_sales_order_item_id,
    v_user_id
  )
  returning id into v_movement_id;

  return v_movement_id;
end;
$$;

revoke all on function public.issue_inventory_reservation(uuid, numeric)
from public, anon;
grant execute on function public.issue_inventory_reservation(uuid, numeric)
to authenticated, service_role;

commit;
