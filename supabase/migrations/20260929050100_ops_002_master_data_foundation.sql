-- OPS-002 bounded unit: master-data database foundation
-- Architecture Generation 1
-- Source of Truth: SOURCE_OF_TRUTH.md
--
-- Scope of this migration is intentionally limited to master data:
-- customers, suppliers, product categories, products/SKUs, packaging conversion,
-- and supplier-product relationships. Auth/RBAC, inventory, orders, finance,
-- production, audit logs, and workflow tables are handled by later OPS tasks.

begin;

create extension if not exists pgcrypto;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = timezone('utc', now());
  return new;
end;
$$;

create table public.customers (
  id uuid primary key default gen_random_uuid(),
  customer_code text unique,
  display_name text not null,
  brand_name text,
  company_name text,
  contact_name text,
  phone text,
  address text,
  notes text,
  is_active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint customers_display_name_not_blank
    check (length(btrim(display_name)) > 0),
  constraint customers_customer_code_not_blank
    check (customer_code is null or length(btrim(customer_code)) > 0)
);

create table public.suppliers (
  id uuid primary key default gen_random_uuid(),
  supplier_code text unique,
  supplier_name text not null,
  contact_name text,
  phone text,
  address text,
  notes text,
  is_active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint suppliers_supplier_name_not_blank
    check (length(btrim(supplier_name)) > 0),
  constraint suppliers_supplier_code_not_blank
    check (supplier_code is null or length(btrim(supplier_code)) > 0)
);

create table public.product_categories (
  id uuid primary key default gen_random_uuid(),
  category_code text unique,
  name text not null unique,
  description text,
  is_active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint product_categories_name_not_blank
    check (length(btrim(name)) > 0),
  constraint product_categories_category_code_not_blank
    check (category_code is null or length(btrim(category_code)) > 0)
);

create table public.products (
  id uuid primary key default gen_random_uuid(),
  category_id uuid references public.product_categories(id) on delete restrict,
  name text not null,
  product_type text,
  description text,
  is_active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint products_name_not_blank
    check (length(btrim(name)) > 0)
);

create table public.product_variants (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete restrict,
  sku_code text not null unique,
  variant_name text,
  capacity_value numeric(18,6),
  capacity_unit text,
  base_inventory_unit text not null default 'piece',
  default_purchase_unit text,
  minimum_stock_quantity numeric(18,6) not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint product_variants_sku_code_not_blank
    check (length(btrim(sku_code)) > 0),
  constraint product_variants_base_unit_not_blank
    check (length(btrim(base_inventory_unit)) > 0),
  constraint product_variants_capacity_positive
    check (capacity_value is null or capacity_value > 0),
  constraint product_variants_minimum_stock_nonnegative
    check (minimum_stock_quantity >= 0)
);

create table public.product_packaging (
  id uuid primary key default gen_random_uuid(),
  product_variant_id uuid not null references public.product_variants(id) on delete restrict,
  package_code text not null,
  package_name text not null,
  units_per_package numeric(18,6) not null,
  is_purchase_default boolean not null default false,
  is_sale_default boolean not null default false,
  effective_from date not null default current_date,
  effective_to date,
  is_active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint product_packaging_units_positive
    check (units_per_package > 0),
  constraint product_packaging_code_not_blank
    check (length(btrim(package_code)) > 0),
  constraint product_packaging_name_not_blank
    check (length(btrim(package_name)) > 0),
  constraint product_packaging_effective_dates_valid
    check (effective_to is null or effective_to >= effective_from),
  constraint product_packaging_variant_code_effective_unique
    unique (product_variant_id, package_code, effective_from)
);

create table public.supplier_products (
  id uuid primary key default gen_random_uuid(),
  supplier_id uuid not null references public.suppliers(id) on delete restrict,
  product_variant_id uuid not null references public.product_variants(id) on delete restrict,
  packaging_id uuid references public.product_packaging(id) on delete restrict,
  supplier_sku text,
  purchase_unit text,
  is_preferred boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint supplier_products_supplier_variant_unique
    unique (supplier_id, product_variant_id)
);

create unique index supplier_products_one_preferred_supplier_per_variant
  on public.supplier_products(product_variant_id)
  where is_preferred = true and is_active = true;

create index products_category_id_idx
  on public.products(category_id);

create index product_variants_product_id_idx
  on public.product_variants(product_id);

create index product_packaging_variant_id_idx
  on public.product_packaging(product_variant_id);

create index supplier_products_supplier_id_idx
  on public.supplier_products(supplier_id);

create index supplier_products_variant_id_idx
  on public.supplier_products(product_variant_id);

create trigger customers_set_updated_at
before update on public.customers
for each row execute function public.set_updated_at();

create trigger suppliers_set_updated_at
before update on public.suppliers
for each row execute function public.set_updated_at();

create trigger product_categories_set_updated_at
before update on public.product_categories
for each row execute function public.set_updated_at();

create trigger products_set_updated_at
before update on public.products
for each row execute function public.set_updated_at();

create trigger product_variants_set_updated_at
before update on public.product_variants
for each row execute function public.set_updated_at();

create trigger product_packaging_set_updated_at
before update on public.product_packaging
for each row execute function public.set_updated_at();

create trigger supplier_products_set_updated_at
before update on public.supplier_products
for each row execute function public.set_updated_at();

commit;
