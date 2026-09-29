-- OPS-002 bounded unit: purchasing and goods-receipt database foundation
-- Architecture Generation 1
-- Source of Truth: SOURCE_OF_TRUTH.md
--
-- Scope is limited to schema foundations for purchase orders, immediate supplier
-- payments, and goods receipts. Purchasing workflow behavior, inventory posting,
-- cost-history posting, attachments, auth/RBAC, and UI remain in later OPS tasks.

begin;

create table public.purchase_orders (
  id uuid primary key default gen_random_uuid(),
  po_number text not null unique,
  supplier_id uuid not null references public.suppliers(id) on delete restrict,
  status text not null default 'DRAFT',
  order_date date not null default current_date,
  expected_receipt_date date,
  actual_receipt_date date,
  freight_amount numeric(18,6) not null default 0,
  currency_code text not null default 'VND',
  payment_note text,
  document_reference text,
  responsible_user_id uuid,
  notes text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint purchase_orders_po_number_not_blank
    check (length(btrim(po_number)) > 0),
  constraint purchase_orders_status_not_blank
    check (length(btrim(status)) > 0),
  constraint purchase_orders_freight_nonnegative
    check (freight_amount >= 0),
  constraint purchase_orders_currency_code_valid
    check (currency_code ~ '^[A-Z]{3}$'),
  constraint purchase_orders_receipt_dates_valid
    check (
      actual_receipt_date is null
      or actual_receipt_date >= order_date
    ),
  constraint purchase_orders_expected_receipt_valid
    check (
      expected_receipt_date is null
      or expected_receipt_date >= order_date
    )
);

create table public.purchase_order_items (
  id uuid primary key default gen_random_uuid(),
  purchase_order_id uuid not null references public.purchase_orders(id) on delete cascade,
  product_variant_id uuid not null references public.product_variants(id) on delete restrict,
  packaging_id uuid references public.product_packaging(id) on delete restrict,
  purchase_unit text not null,
  package_quantity numeric(18,6) not null,
  units_per_purchase_unit numeric(18,6) not null,
  base_quantity numeric(18,6)
    generated always as (
      package_quantity * units_per_purchase_unit
    ) stored,
  unit_cost_per_purchase_unit numeric(18,6) not null,
  line_subtotal numeric(18,6)
    generated always as (
      package_quantity * unit_cost_per_purchase_unit
    ) stored,
  notes text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint purchase_order_items_purchase_unit_not_blank
    check (length(btrim(purchase_unit)) > 0),
  constraint purchase_order_items_package_quantity_positive
    check (package_quantity > 0),
  constraint purchase_order_items_units_per_purchase_unit_positive
    check (units_per_purchase_unit > 0),
  constraint purchase_order_items_unit_cost_nonnegative
    check (unit_cost_per_purchase_unit >= 0)
);

create table public.purchase_payments (
  id uuid primary key default gen_random_uuid(),
  purchase_order_id uuid not null references public.purchase_orders(id) on delete restrict,
  amount numeric(18,6) not null,
  payment_date date not null default current_date,
  payment_method text,
  reference text,
  evidence_attachment_id uuid,
  created_by_user_id uuid,
  notes text,
  created_at timestamptz not null default timezone('utc', now()),
  constraint purchase_payments_amount_positive
    check (amount > 0),
  constraint purchase_payments_method_not_blank
    check (payment_method is null or length(btrim(payment_method)) > 0)
);

create table public.goods_receipts (
  id uuid primary key default gen_random_uuid(),
  goods_receipt_number text not null unique,
  purchase_order_id uuid not null references public.purchase_orders(id) on delete restrict,
  received_at timestamptz not null default timezone('utc', now()),
  received_by_user_id uuid,
  document_reference text,
  notes text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint goods_receipts_number_not_blank
    check (length(btrim(goods_receipt_number)) > 0)
);

create table public.goods_receipt_items (
  id uuid primary key default gen_random_uuid(),
  goods_receipt_id uuid not null references public.goods_receipts(id) on delete cascade,
  purchase_order_item_id uuid not null references public.purchase_order_items(id) on delete restrict,
  package_quantity numeric(18,6) not null,
  units_per_purchase_unit numeric(18,6) not null,
  base_quantity numeric(18,6)
    generated always as (
      package_quantity * units_per_purchase_unit
    ) stored,
  notes text,
  created_at timestamptz not null default timezone('utc', now()),
  constraint goods_receipt_items_package_quantity_positive
    check (package_quantity > 0),
  constraint goods_receipt_items_units_per_purchase_unit_positive
    check (units_per_purchase_unit > 0)
);

create view public.purchase_order_totals as
select
  po.id as purchase_order_id,
  coalesce(sum(poi.line_subtotal), 0::numeric) as item_subtotal,
  po.freight_amount,
  coalesce(sum(poi.line_subtotal), 0::numeric) + po.freight_amount as total_amount,
  po.currency_code
from public.purchase_orders po
left join public.purchase_order_items poi
  on poi.purchase_order_id = po.id
group by po.id, po.freight_amount, po.currency_code;

create index purchase_orders_supplier_id_idx
  on public.purchase_orders(supplier_id);

create index purchase_orders_order_date_idx
  on public.purchase_orders(order_date);

create index purchase_order_items_purchase_order_id_idx
  on public.purchase_order_items(purchase_order_id);

create index purchase_order_items_product_variant_id_idx
  on public.purchase_order_items(product_variant_id);

create index purchase_payments_purchase_order_id_idx
  on public.purchase_payments(purchase_order_id);

create index purchase_payments_payment_date_idx
  on public.purchase_payments(payment_date);

create index goods_receipts_purchase_order_id_idx
  on public.goods_receipts(purchase_order_id);

create index goods_receipts_received_at_idx
  on public.goods_receipts(received_at);

create index goods_receipt_items_goods_receipt_id_idx
  on public.goods_receipt_items(goods_receipt_id);

create index goods_receipt_items_purchase_order_item_id_idx
  on public.goods_receipt_items(purchase_order_item_id);

create trigger purchase_orders_set_updated_at
before update on public.purchase_orders
for each row execute function public.set_updated_at();

create trigger purchase_order_items_set_updated_at
before update on public.purchase_order_items
for each row execute function public.set_updated_at();

create trigger goods_receipts_set_updated_at
before update on public.goods_receipts
for each row execute function public.set_updated_at();

commit;
