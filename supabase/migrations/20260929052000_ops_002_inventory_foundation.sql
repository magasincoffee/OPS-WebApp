-- OPS-002 bounded unit: inventory ledger and reservation database foundation
-- Architecture Generation 1
-- Source of Truth: SOURCE_OF_TRUTH.md
--
-- Scope is limited to the single-warehouse inventory ledger, reservation linkage,
-- derived on-hand/reserved/available snapshots, and ledger integrity guards.
-- Goods-receipt posting, reservation/release/issue workflow behavior, stocktake
-- workflows, auth/RBAC, audit/activity logs, and UI remain in later OPS tasks.

begin;

create table public.inventory_reservations (
  id uuid primary key default gen_random_uuid(),
  sales_order_item_id uuid not null references public.sales_order_items(id) on delete restrict,
  product_variant_id uuid not null references public.product_variants(id) on delete restrict,
  requested_base_quantity numeric(18,6) not null,
  created_by_user_id uuid,
  notes text,
  created_at timestamptz not null default timezone('utc', now()),
  constraint inventory_reservations_requested_quantity_positive
    check (requested_base_quantity > 0)
);

create table public.inventory_movements (
  id uuid primary key default gen_random_uuid(),
  product_variant_id uuid not null references public.product_variants(id) on delete restrict,
  movement_type text not null,
  quantity_delta_base_units numeric(18,6) not null,
  inventory_reservation_id uuid references public.inventory_reservations(id) on delete restrict,
  goods_receipt_item_id uuid references public.goods_receipt_items(id) on delete restrict,
  sales_order_item_id uuid references public.sales_order_items(id) on delete restrict,
  reference text,
  reason text,
  created_by_user_id uuid,
  occurred_at timestamptz not null default timezone('utc', now()),
  created_at timestamptz not null default timezone('utc', now()),
  constraint inventory_movements_type_valid
    check (
      movement_type in (
        'GOODS_RECEIPT',
        'SALES_RESERVATION',
        'RESERVATION_RELEASE',
        'SALES_ISSUE',
        'ADJUSTMENT_IN',
        'ADJUSTMENT_OUT',
        'STOCKTAKE_ADJUSTMENT'
      )
    ),
  constraint inventory_movements_quantity_nonzero
    check (quantity_delta_base_units <> 0),
  constraint inventory_movements_direction_valid
    check (
      (movement_type in ('GOODS_RECEIPT', 'SALES_RESERVATION', 'ADJUSTMENT_IN')
        and quantity_delta_base_units > 0)
      or
      (movement_type in ('RESERVATION_RELEASE', 'SALES_ISSUE', 'ADJUSTMENT_OUT')
        and quantity_delta_base_units < 0)
      or
      (movement_type = 'STOCKTAKE_ADJUSTMENT')
    ),
  constraint inventory_movements_goods_receipt_source_valid
    check (
      (movement_type = 'GOODS_RECEIPT' and goods_receipt_item_id is not null)
      or
      (movement_type <> 'GOODS_RECEIPT' and goods_receipt_item_id is null)
    ),
  constraint inventory_movements_reservation_source_valid
    check (
      (
        movement_type in ('SALES_RESERVATION', 'RESERVATION_RELEASE', 'SALES_ISSUE')
        and inventory_reservation_id is not null
        and sales_order_item_id is not null
      )
      or
      (
        movement_type not in ('SALES_RESERVATION', 'RESERVATION_RELEASE', 'SALES_ISSUE')
        and inventory_reservation_id is null
      )
    )
);

create unique index inventory_movements_one_goods_receipt_post_per_item
  on public.inventory_movements(goods_receipt_item_id)
  where movement_type = 'GOODS_RECEIPT';

create index inventory_reservations_sales_order_item_id_idx
  on public.inventory_reservations(sales_order_item_id);

create index inventory_reservations_product_variant_id_idx
  on public.inventory_reservations(product_variant_id);

create index inventory_movements_variant_occurred_at_idx
  on public.inventory_movements(product_variant_id, occurred_at);

create index inventory_movements_type_idx
  on public.inventory_movements(movement_type);

create index inventory_movements_reservation_id_idx
  on public.inventory_movements(inventory_reservation_id);

create index inventory_movements_sales_order_item_id_idx
  on public.inventory_movements(sales_order_item_id);

create view public.inventory_stock_snapshot as
with movement_totals as (
  select
    im.product_variant_id,
    sum(
      case
        when im.movement_type in (
          'GOODS_RECEIPT',
          'SALES_ISSUE',
          'ADJUSTMENT_IN',
          'ADJUSTMENT_OUT',
          'STOCKTAKE_ADJUSTMENT'
        )
          then im.quantity_delta_base_units
        else 0::numeric
      end
    ) as on_hand_quantity,
    sum(
      case
        when im.movement_type in (
          'SALES_RESERVATION',
          'RESERVATION_RELEASE',
          'SALES_ISSUE'
        )
          then im.quantity_delta_base_units
        else 0::numeric
      end
    ) as reserved_quantity
  from public.inventory_movements im
  group by im.product_variant_id
)
select
  pv.id as product_variant_id,
  coalesce(mt.on_hand_quantity, 0::numeric) as on_hand_quantity,
  coalesce(mt.reserved_quantity, 0::numeric) as reserved_quantity,
  coalesce(mt.on_hand_quantity, 0::numeric)
    - coalesce(mt.reserved_quantity, 0::numeric) as available_quantity
from public.product_variants pv
left join movement_totals mt
  on mt.product_variant_id = pv.id;

create view public.inventory_reservation_balances as
select
  ir.id as inventory_reservation_id,
  ir.sales_order_item_id,
  ir.product_variant_id,
  ir.requested_base_quantity,
  coalesce(
    sum(
      case
        when im.movement_type in (
          'SALES_RESERVATION',
          'RESERVATION_RELEASE',
          'SALES_ISSUE'
        )
          then im.quantity_delta_base_units
        else 0::numeric
      end
    ),
    0::numeric
  ) as reserved_balance_quantity
from public.inventory_reservations ir
left join public.inventory_movements im
  on im.inventory_reservation_id = ir.id
group by
  ir.id,
  ir.sales_order_item_id,
  ir.product_variant_id,
  ir.requested_base_quantity;

create or replace function public.guard_inventory_movement_available_stock()
returns trigger
language plpgsql
as $$
declare
  current_available numeric(18,6);
  available_delta numeric(18,6);
begin
  perform pg_advisory_xact_lock(
    hashtextextended(new.product_variant_id::text, 0)
  );

  select
    coalesce(
      sum(
        case
          when im.movement_type in (
            'GOODS_RECEIPT',
            'SALES_ISSUE',
            'ADJUSTMENT_IN',
            'ADJUSTMENT_OUT',
            'STOCKTAKE_ADJUSTMENT'
          )
            then im.quantity_delta_base_units
          else 0::numeric
        end
      ),
      0::numeric
    )
    -
    coalesce(
      sum(
        case
          when im.movement_type in (
            'SALES_RESERVATION',
            'RESERVATION_RELEASE',
            'SALES_ISSUE'
          )
            then im.quantity_delta_base_units
          else 0::numeric
        end
      ),
      0::numeric
    )
  into current_available
  from public.inventory_movements im
  where im.product_variant_id = new.product_variant_id;

  available_delta :=
    case
      when new.movement_type in (
        'GOODS_RECEIPT',
        'SALES_ISSUE',
        'ADJUSTMENT_IN',
        'ADJUSTMENT_OUT',
        'STOCKTAKE_ADJUSTMENT'
      )
        then new.quantity_delta_base_units
      else 0::numeric
    end
    -
    case
      when new.movement_type in (
        'SALES_RESERVATION',
        'RESERVATION_RELEASE',
        'SALES_ISSUE'
      )
        then new.quantity_delta_base_units
      else 0::numeric
    end;

  if current_available + available_delta < 0 then
    raise exception
      'Inventory movement would make available stock negative for product variant %',
      new.product_variant_id;
  end if;

  return new;
end;
$$;

create trigger inventory_movements_guard_available_stock
before insert on public.inventory_movements
for each row execute function public.guard_inventory_movement_available_stock();

create or replace function public.prevent_inventory_movement_mutation()
returns trigger
language plpgsql
as $$
begin
  raise exception
    'Inventory movements are immutable; create a compensating movement instead';
end;
$$;

create trigger inventory_movements_prevent_update
before update on public.inventory_movements
for each row execute function public.prevent_inventory_movement_mutation();

create trigger inventory_movements_prevent_delete
before delete on public.inventory_movements
for each row execute function public.prevent_inventory_movement_mutation();

commit;
