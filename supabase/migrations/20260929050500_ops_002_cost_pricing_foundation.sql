-- OPS-002 bounded unit: cost and pricing database foundation
-- Architecture Generation 1
-- Source of Truth: SOURCE_OF_TRUTH.md
--
-- Scope is limited to cost history and data-driven pricing structures.
-- Purchasing workflows, quotations, sales orders, inventory movements,
-- authentication/RBAC, and UI behavior remain in their later OPS tasks.

begin;

create table public.purchase_cost_history (
  id uuid primary key default gen_random_uuid(),
  product_variant_id uuid not null references public.product_variants(id) on delete restrict,
  supplier_id uuid references public.suppliers(id) on delete restrict,
  packaging_id uuid references public.product_packaging(id) on delete restrict,
  effective_at timestamptz not null default timezone('utc', now()),
  purchase_unit text not null,
  units_per_purchase_unit numeric(18,6) not null,
  purchase_price_per_purchase_unit numeric(18,6) not null,
  freight_cost_per_purchase_unit numeric(18,6) not null default 0,
  other_allocated_cost_per_purchase_unit numeric(18,6) not null default 0,
  purchase_cost_per_base_unit numeric(18,6)
    generated always as (
      purchase_price_per_purchase_unit / units_per_purchase_unit
    ) stored,
  landed_cost_per_base_unit numeric(18,6)
    generated always as (
      (
        purchase_price_per_purchase_unit
        + freight_cost_per_purchase_unit
        + other_allocated_cost_per_purchase_unit
      ) / units_per_purchase_unit
    ) stored,
  inventory_cost_basis_per_base_unit numeric(18,6),
  currency_code text not null default 'VND',
  source_reference text,
  notes text,
  created_at timestamptz not null default timezone('utc', now()),
  constraint purchase_cost_history_purchase_unit_not_blank
    check (length(btrim(purchase_unit)) > 0),
  constraint purchase_cost_history_units_positive
    check (units_per_purchase_unit > 0),
  constraint purchase_cost_history_purchase_price_nonnegative
    check (purchase_price_per_purchase_unit >= 0),
  constraint purchase_cost_history_freight_nonnegative
    check (freight_cost_per_purchase_unit >= 0),
  constraint purchase_cost_history_other_cost_nonnegative
    check (other_allocated_cost_per_purchase_unit >= 0),
  constraint purchase_cost_history_inventory_basis_nonnegative
    check (
      inventory_cost_basis_per_base_unit is null
      or inventory_cost_basis_per_base_unit >= 0
    ),
  constraint purchase_cost_history_currency_code_valid
    check (currency_code ~ '^[A-Z]{3}$')
);

create table public.pricing_rules (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  product_variant_id uuid references public.product_variants(id) on delete restrict,
  product_type text,
  print_mode text not null default 'ANY',
  min_print_colors integer,
  max_print_colors integer,
  currency_code text not null default 'VND',
  priority integer not null default 100,
  effective_from date not null default current_date,
  effective_to date,
  is_active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint pricing_rules_name_not_blank
    check (length(btrim(name)) > 0),
  constraint pricing_rules_product_type_not_blank
    check (product_type is null or length(btrim(product_type)) > 0),
  constraint pricing_rules_print_mode_valid
    check (print_mode in ('ANY', 'PRINTED', 'PLAIN')),
  constraint pricing_rules_min_print_colors_nonnegative
    check (min_print_colors is null or min_print_colors >= 0),
  constraint pricing_rules_max_print_colors_nonnegative
    check (max_print_colors is null or max_print_colors >= 0),
  constraint pricing_rules_print_color_range_valid
    check (
      min_print_colors is null
      or max_print_colors is null
      or max_print_colors >= min_print_colors
    ),
  constraint pricing_rules_currency_code_valid
    check (currency_code ~ '^[A-Z]{3}$'),
  constraint pricing_rules_effective_dates_valid
    check (effective_to is null or effective_to >= effective_from)
);

create table public.price_tiers (
  id uuid primary key default gen_random_uuid(),
  pricing_rule_id uuid not null references public.pricing_rules(id) on delete cascade,
  min_quantity_base_units numeric(18,6) not null,
  max_quantity_base_units numeric(18,6),
  fixed_selling_price_per_base_unit numeric(18,6),
  markup_percent numeric(9,4),
  margin_percent numeric(9,4),
  print_cost_per_base_unit numeric(18,6) not null default 0,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint price_tiers_min_quantity_positive
    check (min_quantity_base_units > 0),
  constraint price_tiers_quantity_range_valid
    check (
      max_quantity_base_units is null
      or max_quantity_base_units >= min_quantity_base_units
    ),
  constraint price_tiers_fixed_price_nonnegative
    check (
      fixed_selling_price_per_base_unit is null
      or fixed_selling_price_per_base_unit >= 0
    ),
  constraint price_tiers_markup_nonnegative
    check (markup_percent is null or markup_percent >= 0),
  constraint price_tiers_margin_valid
    check (
      margin_percent is null
      or (margin_percent >= 0 and margin_percent < 100)
    ),
  constraint price_tiers_print_cost_nonnegative
    check (print_cost_per_base_unit >= 0),
  constraint price_tiers_one_pricing_basis
    check (
      num_nonnulls(
        fixed_selling_price_per_base_unit,
        markup_percent,
        margin_percent
      ) = 1
    ),
  constraint price_tiers_rule_min_quantity_unique
    unique (pricing_rule_id, min_quantity_base_units)
);

create index purchase_cost_history_variant_effective_idx
  on public.purchase_cost_history(product_variant_id, effective_at desc);

create index purchase_cost_history_supplier_id_idx
  on public.purchase_cost_history(supplier_id);

create index pricing_rules_product_variant_id_idx
  on public.pricing_rules(product_variant_id);

create index pricing_rules_active_effective_idx
  on public.pricing_rules(is_active, effective_from, effective_to);

create index price_tiers_pricing_rule_id_idx
  on public.price_tiers(pricing_rule_id);

create trigger pricing_rules_set_updated_at
before update on public.pricing_rules
for each row execute function public.set_updated_at();

create trigger price_tiers_set_updated_at
before update on public.price_tiers
for each row execute function public.set_updated_at();

commit;
