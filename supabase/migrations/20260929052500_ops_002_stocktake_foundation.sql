-- OPS-002 bounded unit: stocktake and adjustment database foundation
-- Architecture Generation 1
-- Source of Truth: SOURCE_OF_TRUTH.md
--
-- Scope is limited to stocktake headers/items and authoritative linkage of
-- STOCKTAKE_ADJUSTMENT movements back to a counted stocktake line.
-- Stocktake workflow transitions, posting services, authorization, audit logs,
-- low-stock UI/reporting, and operational screens remain in later OPS tasks.

begin;

create table public.stocktakes (
  id uuid primary key default gen_random_uuid(),
  stocktake_number text not null unique,
  stocktake_date date not null default current_date,
  status text not null default 'DRAFT',
  counted_at timestamptz,
  posted_at timestamptz,
  created_by_user_id uuid,
  posted_by_user_id uuid,
  notes text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint stocktakes_number_not_blank
    check (length(btrim(stocktake_number)) > 0),
  constraint stocktakes_status_not_blank
    check (length(btrim(status)) > 0),
  constraint stocktakes_posted_after_counted
    check (
      posted_at is null
      or counted_at is null
      or posted_at >= counted_at
    )
);

create table public.stocktake_items (
  id uuid primary key default gen_random_uuid(),
  stocktake_id uuid not null references public.stocktakes(id) on delete cascade,
  product_variant_id uuid not null references public.product_variants(id) on delete restrict,
  system_on_hand_quantity numeric(18,6) not null,
  counted_on_hand_quantity numeric(18,6),
  variance_quantity numeric(18,6)
    generated always as (
      case
        when counted_on_hand_quantity is null then null
        else counted_on_hand_quantity - system_on_hand_quantity
      end
    ) stored,
  notes text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint stocktake_items_system_quantity_nonnegative
    check (system_on_hand_quantity >= 0),
  constraint stocktake_items_counted_quantity_nonnegative
    check (
      counted_on_hand_quantity is null
      or counted_on_hand_quantity >= 0
    ),
  constraint stocktake_items_one_variant_per_stocktake
    unique (stocktake_id, product_variant_id)
);

alter table public.inventory_movements
  add column stocktake_item_id uuid
    references public.stocktake_items(id) on delete restrict;

alter table public.inventory_movements
  add constraint inventory_movements_stocktake_source_valid
  check (
    (
      movement_type = 'STOCKTAKE_ADJUSTMENT'
      and stocktake_item_id is not null
    )
    or
    (
      movement_type <> 'STOCKTAKE_ADJUSTMENT'
      and stocktake_item_id is null
    )
  );

alter table public.inventory_movements
  add constraint inventory_movements_adjustment_reason_required
  check (
    movement_type not in (
      'ADJUSTMENT_IN',
      'ADJUSTMENT_OUT',
      'STOCKTAKE_ADJUSTMENT'
    )
    or (
      reason is not null
      and length(btrim(reason)) > 0
    )
  );

create unique index inventory_movements_one_stocktake_post_per_item
  on public.inventory_movements(stocktake_item_id)
  where movement_type = 'STOCKTAKE_ADJUSTMENT';

create index stocktakes_stocktake_date_idx
  on public.stocktakes(stocktake_date);

create index stocktakes_status_idx
  on public.stocktakes(status);

create index stocktake_items_stocktake_id_idx
  on public.stocktake_items(stocktake_id);

create index stocktake_items_product_variant_id_idx
  on public.stocktake_items(product_variant_id);

create index inventory_movements_stocktake_item_id_idx
  on public.inventory_movements(stocktake_item_id);

create trigger stocktakes_set_updated_at
before update on public.stocktakes
for each row execute function public.set_updated_at();

create trigger stocktake_items_set_updated_at
before update on public.stocktake_items
for each row execute function public.set_updated_at();

commit;
