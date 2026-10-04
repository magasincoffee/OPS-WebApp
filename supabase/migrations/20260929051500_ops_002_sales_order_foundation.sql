-- OPS-002 bounded unit: quotation and sales-order database foundation
-- Architecture Generation 1
-- Source of Truth: SOURCE_OF_TRUTH.md
--
-- Scope is limited to quotation and sales-order schema foundations.
-- Workflow transitions, pricing execution, inventory reservation/issue,
-- print-job creation, customer payments/receivables, auth/RBAC, attachments,
-- audit logging, and UI behavior remain in later OPS tasks.

begin;

create table public.quotations (
  id uuid primary key default gen_random_uuid(),
  quotation_number text not null unique,
  customer_id uuid not null references public.customers(id) on delete restrict,
  status text not null default 'DRAFT',
  quotation_date date not null default current_date,
  valid_until date,
  currency_code text not null default 'VND',
  created_by_user_id uuid,
  notes text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint quotations_number_not_blank
    check (length(btrim(quotation_number)) > 0),
  constraint quotations_status_not_blank
    check (length(btrim(status)) > 0),
  constraint quotations_currency_code_valid
    check (currency_code ~ '^[A-Z]{3}$'),
  constraint quotations_valid_until_valid
    check (valid_until is null or valid_until >= quotation_date)
);

create table public.quotation_items (
  id uuid primary key default gen_random_uuid(),
  quotation_id uuid not null references public.quotations(id) on delete cascade,
  product_variant_id uuid not null references public.product_variants(id) on delete restrict,
  packaging_id uuid references public.product_packaging(id) on delete restrict,
  sale_unit text not null,
  sale_quantity numeric(18,6) not null,
  units_per_sale_unit numeric(18,6) not null,
  base_quantity numeric(18,6)
    generated always as (
      sale_quantity * units_per_sale_unit
    ) stored,
  unit_price_per_sale_unit numeric(18,6) not null,
  discount_amount numeric(18,6) not null default 0,
  print_mode text not null default 'PLAIN',
  print_color_count integer,
  print_specification text,
  artwork_reference text,
  requested_due_date date,
  line_subtotal numeric(18,6)
    generated always as (
      sale_quantity * unit_price_per_sale_unit
    ) stored,
  line_total numeric(18,6)
    generated always as (
      (sale_quantity * unit_price_per_sale_unit) - discount_amount
    ) stored,
  notes text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint quotation_items_sale_unit_not_blank
    check (length(btrim(sale_unit)) > 0),
  constraint quotation_items_sale_quantity_positive
    check (sale_quantity > 0),
  constraint quotation_items_units_per_sale_unit_positive
    check (units_per_sale_unit > 0),
  constraint quotation_items_unit_price_nonnegative
    check (unit_price_per_sale_unit >= 0),
  constraint quotation_items_discount_nonnegative
    check (discount_amount >= 0),
  constraint quotation_items_discount_not_over_subtotal
    check (discount_amount <= sale_quantity * unit_price_per_sale_unit),
  constraint quotation_items_print_mode_valid
    check (print_mode in ('PRINTED', 'PLAIN')),
  constraint quotation_items_print_colors_valid
    check (
      (print_mode = 'PLAIN' and print_color_count is null)
      or
      (print_mode = 'PRINTED' and print_color_count is not null and print_color_count > 0)
    )
);

create table public.sales_orders (
  id uuid primary key default gen_random_uuid(),
  order_number text not null unique,
  customer_id uuid not null references public.customers(id) on delete restrict,
  source_quotation_id uuid references public.quotations(id) on delete restrict,
  order_status text not null default 'DRAFT',
  print_status text not null default 'NOT_REQUIRED',
  warehouse_status text not null default 'NOT_RESERVED',
  payment_status text not null default 'UNPAID',
  delivery_status text not null default 'NOT_READY',
  order_date date not null default current_date,
  requested_due_date date,
  currency_code text not null default 'VND',
  created_by_user_id uuid,
  salesperson_user_id uuid,
  notes text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint sales_orders_number_not_blank
    check (length(btrim(order_number)) > 0),
  constraint sales_orders_order_status_valid
    check (order_status in ('DRAFT', 'CONFIRMED', 'COMPLETED', 'CANCELLED')),
  constraint sales_orders_print_status_valid
    check (print_status in ('NOT_REQUIRED', 'WAITING', 'IN_PROGRESS', 'WAITING_QC', 'COMPLETED')),
  constraint sales_orders_warehouse_status_valid
    check (warehouse_status in ('NOT_RESERVED', 'RESERVED', 'ISSUED')),
  constraint sales_orders_payment_status_valid
    check (payment_status in ('UNPAID', 'PARTIALLY_PAID', 'RECEIVABLE', 'PAID')),
  constraint sales_orders_delivery_status_not_blank
    check (length(btrim(delivery_status)) > 0),
  constraint sales_orders_currency_code_valid
    check (currency_code ~ '^[A-Z]{3}$'),
  constraint sales_orders_requested_due_date_valid
    check (requested_due_date is null or requested_due_date >= order_date)
);

create table public.sales_order_items (
  id uuid primary key default gen_random_uuid(),
  sales_order_id uuid not null references public.sales_orders(id) on delete cascade,
  source_quotation_item_id uuid references public.quotation_items(id) on delete restrict,
  product_variant_id uuid not null references public.product_variants(id) on delete restrict,
  packaging_id uuid references public.product_packaging(id) on delete restrict,
  sale_unit text not null,
  sale_quantity numeric(18,6) not null,
  units_per_sale_unit numeric(18,6) not null,
  base_quantity numeric(18,6)
    generated always as (
      sale_quantity * units_per_sale_unit
    ) stored,
  unit_price_per_sale_unit numeric(18,6) not null,
  discount_amount numeric(18,6) not null default 0,
  print_mode text not null default 'PLAIN',
  print_color_count integer,
  print_specification text,
  artwork_reference text,
  requested_due_date date,
  line_subtotal numeric(18,6)
    generated always as (
      sale_quantity * unit_price_per_sale_unit
    ) stored,
  line_total numeric(18,6)
    generated always as (
      (sale_quantity * unit_price_per_sale_unit) - discount_amount
    ) stored,
  notes text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint sales_order_items_sale_unit_not_blank
    check (length(btrim(sale_unit)) > 0),
  constraint sales_order_items_sale_quantity_positive
    check (sale_quantity > 0),
  constraint sales_order_items_units_per_sale_unit_positive
    check (units_per_sale_unit > 0),
  constraint sales_order_items_unit_price_nonnegative
    check (unit_price_per_sale_unit >= 0),
  constraint sales_order_items_discount_nonnegative
    check (discount_amount >= 0),
  constraint sales_order_items_discount_not_over_subtotal
    check (discount_amount <= sale_quantity * unit_price_per_sale_unit),
  constraint sales_order_items_print_mode_valid
    check (print_mode in ('PRINTED', 'PLAIN')),
  constraint sales_order_items_print_colors_valid
    check (
      (print_mode = 'PLAIN' and print_color_count is null)
      or
      (print_mode = 'PRINTED' and print_color_count is not null and print_color_count > 0)
    )
);

create view public.quotation_totals as
select
  q.id as quotation_id,
  coalesce(sum(qi.line_subtotal), 0::numeric) as subtotal_amount,
  coalesce(sum(qi.discount_amount), 0::numeric) as discount_amount,
  coalesce(sum(qi.line_total), 0::numeric) as total_amount,
  q.currency_code
from public.quotations q
left join public.quotation_items qi
  on qi.quotation_id = q.id
group by q.id, q.currency_code;

create view public.sales_order_totals as
select
  so.id as sales_order_id,
  coalesce(sum(soi.line_subtotal), 0::numeric) as subtotal_amount,
  coalesce(sum(soi.discount_amount), 0::numeric) as discount_amount,
  coalesce(sum(soi.line_total), 0::numeric) as total_amount,
  so.currency_code
from public.sales_orders so
left join public.sales_order_items soi
  on soi.sales_order_id = so.id
group by so.id, so.currency_code;

create index quotations_customer_id_idx
  on public.quotations(customer_id);

create index quotations_quotation_date_idx
  on public.quotations(quotation_date);

create index quotation_items_quotation_id_idx
  on public.quotation_items(quotation_id);

create index quotation_items_product_variant_id_idx
  on public.quotation_items(product_variant_id);

create index sales_orders_customer_id_idx
  on public.sales_orders(customer_id);

create index sales_orders_source_quotation_id_idx
  on public.sales_orders(source_quotation_id);

create index sales_orders_order_date_idx
  on public.sales_orders(order_date);

create index sales_orders_status_dimensions_idx
  on public.sales_orders(order_status, print_status, warehouse_status, payment_status);

create index sales_order_items_sales_order_id_idx
  on public.sales_order_items(sales_order_id);

create index sales_order_items_product_variant_id_idx
  on public.sales_order_items(product_variant_id);

create trigger quotations_set_updated_at
before update on public.quotations
for each row execute function public.set_updated_at();

create trigger quotation_items_set_updated_at
before update on public.quotation_items
for each row execute function public.set_updated_at();

create trigger sales_orders_set_updated_at
before update on public.sales_orders
for each row execute function public.set_updated_at();

create trigger sales_order_items_set_updated_at
before update on public.sales_order_items
for each row execute function public.set_updated_at();

commit;
