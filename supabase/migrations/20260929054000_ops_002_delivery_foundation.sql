-- OPS-002 bounded unit: delivery database foundation
-- Architecture Generation 1
-- Source of Truth: SOURCE_OF_TRUTH.md
--
-- Scope is limited to delivery headers/items, operational delivery state,
-- parcel/carrier/consignee data, and source-integrity validation against
-- sales-order items. Dispatch workflow, authorization, audit/activity logs,
-- attachments, notifications, and UI remain in later OPS tasks.

begin;

create table public.deliveries (
  id uuid primary key default gen_random_uuid(),
  delivery_number text not null unique,
  sales_order_id uuid not null references public.sales_orders(id) on delete restrict,
  status text not null default 'NOT_READY',
  consignee_name text not null,
  consignee_phone text,
  consignee_address text,
  parcel_info text,
  carrier_note text,
  delivery_reference text,
  ready_at timestamptz,
  dispatch_date date,
  completed_at timestamptz,
  created_by_user_id uuid,
  notes text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint deliveries_number_not_blank
    check (length(btrim(delivery_number)) > 0),
  constraint deliveries_consignee_name_not_blank
    check (length(btrim(consignee_name)) > 0),
  constraint deliveries_status_valid
    check (
      status in (
        'NOT_READY',
        'READY_TO_SHIP',
        'DISPATCHED',
        'COMPLETED',
        'CANCELLED'
      )
    ),
  constraint deliveries_dispatch_state_valid
    check (
      (
        status in ('NOT_READY', 'READY_TO_SHIP')
        and dispatch_date is null
        and completed_at is null
      )
      or
      (
        status = 'DISPATCHED'
        and dispatch_date is not null
        and completed_at is null
      )
      or
      (
        status = 'COMPLETED'
        and dispatch_date is not null
        and completed_at is not null
      )
      or
      (
        status = 'CANCELLED'
        and completed_at is null
      )
    )
);

create table public.delivery_items (
  id uuid primary key default gen_random_uuid(),
  delivery_id uuid not null references public.deliveries(id) on delete cascade,
  sales_order_item_id uuid not null references public.sales_order_items(id) on delete restrict,
  product_variant_id uuid not null references public.product_variants(id) on delete restrict,
  quantity_base_units numeric(18,6) not null,
  notes text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint delivery_items_quantity_positive
    check (quantity_base_units > 0),
  constraint delivery_items_delivery_order_line_unique
    unique (delivery_id, sales_order_item_id)
);

create or replace function public.validate_delivery_item_source()
returns trigger
language plpgsql
as $$
declare
  delivery_order_id uuid;
  source_order_id uuid;
  source_variant_id uuid;
begin
  select d.sales_order_id
  into delivery_order_id
  from public.deliveries d
  where d.id = new.delivery_id;

  if delivery_order_id is null then
    raise exception
      'Delivery % does not exist',
      new.delivery_id;
  end if;

  select
    soi.sales_order_id,
    soi.product_variant_id
  into
    source_order_id,
    source_variant_id
  from public.sales_order_items soi
  where soi.id = new.sales_order_item_id;

  if source_order_id is null then
    raise exception
      'Delivery source sales-order item % does not exist',
      new.sales_order_item_id;
  end if;

  if source_order_id <> delivery_order_id then
    raise exception
      'Delivery item sales-order item must belong to the delivery sales order';
  end if;

  if new.product_variant_id <> source_variant_id then
    raise exception
      'Delivery item product_variant_id must match its source sales-order item';
  end if;

  return new;
end;
$$;

create trigger delivery_items_validate_source
before insert or update of delivery_id, sales_order_item_id, product_variant_id
on public.delivery_items
for each row execute function public.validate_delivery_item_source();

create view public.delivery_order_status as
select
  so.id as sales_order_id,
  case
    when count(d.id) = 0 then 'NOT_READY'
    when bool_or(d.status = 'DISPATCHED') then 'DISPATCHED'
    when bool_and(d.status = 'COMPLETED') then 'COMPLETED'
    when bool_or(d.status = 'READY_TO_SHIP') then 'READY_TO_SHIP'
    else 'NOT_READY'
  end as derived_delivery_status,
  count(d.id) as delivery_count
from public.sales_orders so
left join public.deliveries d
  on d.sales_order_id = so.id
  and d.status <> 'CANCELLED'
group by so.id;

create index deliveries_sales_order_id_idx
  on public.deliveries(sales_order_id);

create index deliveries_status_dispatch_date_idx
  on public.deliveries(status, dispatch_date);

create index delivery_items_delivery_id_idx
  on public.delivery_items(delivery_id);

create index delivery_items_sales_order_item_id_idx
  on public.delivery_items(sales_order_item_id);

create index delivery_items_product_variant_id_idx
  on public.delivery_items(product_variant_id);

create trigger deliveries_set_updated_at
before update on public.deliveries
for each row execute function public.set_updated_at();

create trigger delivery_items_set_updated_at
before update on public.delivery_items
for each row execute function public.set_updated_at();

commit;
