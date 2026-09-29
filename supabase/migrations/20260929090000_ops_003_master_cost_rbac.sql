-- OPS-003 bounded unit: master-data and cost/pricing RBAC policies
-- Architecture Generation 1
-- Source of Truth: SOURCE_OF_TRUTH.md
--
-- Scope is intentionally limited to the master-data and cost/pricing tables.
-- Purchase/order/inventory/production/finance/delivery/task authorization remains
-- in later bounded units inside OPS-003.
--
-- Policy intent derived from SOT Section 5:
-- - OWNER_ADMIN: full access in this slice.
-- - SALES: manage customers; read product/catalog data and permitted pricing.
-- - ACCOUNTING: read customer/supplier/product data plus cost/pricing data.
-- - WAREHOUSE: read supplier/product data required for receiving/inventory work.
-- - PRINTER_PRODUCTION: read product identity/specification data only.
-- - Cost history is restricted to OWNER_ADMIN and ACCOUNTING.
-- - Supplier-product relationships are restricted from SALES and PRODUCTION.

begin;

-- The application roles all connect through Supabase's authenticated DB role.
-- Table grants make operations possible; RLS remains the authoritative app-role gate.
revoke all on
  public.customers,
  public.suppliers,
  public.product_categories,
  public.products,
  public.product_variants,
  public.product_packaging,
  public.supplier_products,
  public.purchase_cost_history,
  public.pricing_rules,
  public.price_tiers
from anon;

grant select, insert, update, delete on
  public.customers,
  public.suppliers,
  public.product_categories,
  public.products,
  public.product_variants,
  public.product_packaging,
  public.supplier_products,
  public.purchase_cost_history,
  public.pricing_rules,
  public.price_tiers
to authenticated;

grant all on
  public.customers,
  public.suppliers,
  public.product_categories,
  public.products,
  public.product_variants,
  public.product_packaging,
  public.supplier_products,
  public.purchase_cost_history,
  public.pricing_rules,
  public.price_tiers
to service_role;

-- Customers: SALES owns normal customer-master work; ACCOUNTING may read it.
create policy customers_select_business_roles
on public.customers
for select
to authenticated
using (
  public.current_user_has_role('OWNER_ADMIN')
  or public.current_user_has_role('SALES')
  or public.current_user_has_role('ACCOUNTING')
);

create policy customers_mutate_sales_or_owner
on public.customers
for all
to authenticated
using (
  public.current_user_has_role('OWNER_ADMIN')
  or public.current_user_has_role('SALES')
)
with check (
  public.current_user_has_role('OWNER_ADMIN')
  or public.current_user_has_role('SALES')
);

-- Suppliers: procurement context is available to OWNER/ACCOUNTING/WAREHOUSE.
create policy suppliers_select_operational_roles
on public.suppliers
for select
to authenticated
using (
  public.current_user_has_role('OWNER_ADMIN')
  or public.current_user_has_role('ACCOUNTING')
  or public.current_user_has_role('WAREHOUSE')
);

create policy suppliers_mutate_owner_admin
on public.suppliers
for all
to authenticated
using (public.current_user_has_role('OWNER_ADMIN'))
with check (public.current_user_has_role('OWNER_ADMIN'));

-- Product identity and packaging are operational reference data required across roles.
create policy product_categories_select_all_v1_roles
on public.product_categories
for select
to authenticated
using (
  public.current_user_has_role('OWNER_ADMIN')
  or public.current_user_has_role('SALES')
  or public.current_user_has_role('ACCOUNTING')
  or public.current_user_has_role('WAREHOUSE')
  or public.current_user_has_role('PRINTER_PRODUCTION')
);

create policy product_categories_mutate_owner_admin
on public.product_categories
for all
to authenticated
using (public.current_user_has_role('OWNER_ADMIN'))
with check (public.current_user_has_role('OWNER_ADMIN'));

create policy products_select_all_v1_roles
on public.products
for select
to authenticated
using (
  public.current_user_has_role('OWNER_ADMIN')
  or public.current_user_has_role('SALES')
  or public.current_user_has_role('ACCOUNTING')
  or public.current_user_has_role('WAREHOUSE')
  or public.current_user_has_role('PRINTER_PRODUCTION')
);

create policy products_mutate_owner_admin
on public.products
for all
to authenticated
using (public.current_user_has_role('OWNER_ADMIN'))
with check (public.current_user_has_role('OWNER_ADMIN'));

create policy product_variants_select_all_v1_roles
on public.product_variants
for select
to authenticated
using (
  public.current_user_has_role('OWNER_ADMIN')
  or public.current_user_has_role('SALES')
  or public.current_user_has_role('ACCOUNTING')
  or public.current_user_has_role('WAREHOUSE')
  or public.current_user_has_role('PRINTER_PRODUCTION')
);

create policy product_variants_mutate_owner_admin
on public.product_variants
for all
to authenticated
using (public.current_user_has_role('OWNER_ADMIN'))
with check (public.current_user_has_role('OWNER_ADMIN'));

create policy product_packaging_select_all_v1_roles
on public.product_packaging
for select
to authenticated
using (
  public.current_user_has_role('OWNER_ADMIN')
  or public.current_user_has_role('SALES')
  or public.current_user_has_role('ACCOUNTING')
  or public.current_user_has_role('WAREHOUSE')
  or public.current_user_has_role('PRINTER_PRODUCTION')
);

create policy product_packaging_mutate_owner_admin
on public.product_packaging
for all
to authenticated
using (public.current_user_has_role('OWNER_ADMIN'))
with check (public.current_user_has_role('OWNER_ADMIN'));

-- Supplier-product linkage is procurement-sensitive and is not exposed to SALES/PRODUCTION.
create policy supplier_products_select_procurement_roles
on public.supplier_products
for select
to authenticated
using (
  public.current_user_has_role('OWNER_ADMIN')
  or public.current_user_has_role('ACCOUNTING')
  or public.current_user_has_role('WAREHOUSE')
);

create policy supplier_products_mutate_owner_admin
on public.supplier_products
for all
to authenticated
using (public.current_user_has_role('OWNER_ADMIN'))
with check (public.current_user_has_role('OWNER_ADMIN'));

-- Cost history is explicitly restricted from SALES, WAREHOUSE, and PRODUCTION.
create policy purchase_cost_history_select_financial_roles
on public.purchase_cost_history
for select
to authenticated
using (
  public.current_user_has_role('OWNER_ADMIN')
  or public.current_user_has_role('ACCOUNTING')
);

create policy purchase_cost_history_mutate_owner_admin
on public.purchase_cost_history
for all
to authenticated
using (public.current_user_has_role('OWNER_ADMIN'))
with check (public.current_user_has_role('OWNER_ADMIN'));

-- Pricing rules are readable by SALES as permitted selling-price inputs,
-- and by ACCOUNTING for pricing/cost reporting. Configuration remains OWNER-only.
create policy pricing_rules_select_authorized_roles
on public.pricing_rules
for select
to authenticated
using (
  public.current_user_has_role('OWNER_ADMIN')
  or public.current_user_has_role('SALES')
  or public.current_user_has_role('ACCOUNTING')
);

create policy pricing_rules_mutate_owner_admin
on public.pricing_rules
for all
to authenticated
using (public.current_user_has_role('OWNER_ADMIN'))
with check (public.current_user_has_role('OWNER_ADMIN'));

create policy price_tiers_select_authorized_roles
on public.price_tiers
for select
to authenticated
using (
  public.current_user_has_role('OWNER_ADMIN')
  or public.current_user_has_role('SALES')
  or public.current_user_has_role('ACCOUNTING')
);

create policy price_tiers_mutate_owner_admin
on public.price_tiers
for all
to authenticated
using (public.current_user_has_role('OWNER_ADMIN'))
with check (public.current_user_has_role('OWNER_ADMIN'));

commit;
