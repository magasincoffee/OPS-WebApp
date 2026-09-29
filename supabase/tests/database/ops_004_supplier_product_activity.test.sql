begin;

create extension if not exists pgtap with schema extensions;

select plan(10);

select results_eq(
  $$
    select count(*)::bigint
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'supplier_products'
      and t.tgname = 'supplier_products_capture_activity'
      and not t.tgisinternal
  $$,
  array[1::bigint],
  'OPS-004 installs one automatic supplier-product activity trigger'
);

select results_eq(
  $$
    select p.prosecdef
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'capture_supplier_product_activity'
      and p.pronargs = 0
  $$,
  array[true],
  'supplier-product activity capture executes as SECURITY DEFINER'
);

select results_eq(
  $$
    select has_function_privilege(
      'authenticated',
      'public.capture_supplier_product_activity()',
      'EXECUTE'
    )
  $$,
  array[false],
  'authenticated users cannot directly execute the supplier-product audit trigger function'
);

insert into auth.users (id, email)
values (
  '9a100000-0000-0000-0000-000000000001',
  'ops-supplier-product-activity@example.test'
);

insert into public.user_roles (user_id, role_id)
select
  '9a100000-0000-0000-0000-000000000001'::uuid,
  r.id
from public.roles r
where r.code = 'OWNER_ADMIN';

set local role authenticated;
set local request.jwt.claim.sub = '9a100000-0000-0000-0000-000000000001';

insert into public.suppliers (
  id,
  supplier_code,
  supplier_name
)
values (
  '9a200000-0000-0000-0000-000000000001',
  'SUP-ACT-001',
  'Supplier Product Activity Supplier'
);

insert into public.product_categories (
  id,
  category_code,
  name
)
values (
  '9a300000-0000-0000-0000-000000000001',
  'SUP-PROD-ACT-CATEGORY',
  'Supplier Product Activity Category'
);

insert into public.products (
  id,
  category_id,
  name,
  product_type
)
values (
  '9a400000-0000-0000-0000-000000000001',
  '9a300000-0000-0000-0000-000000000001',
  'Supplier Product Activity Product',
  'CUP'
);

insert into public.product_variants (
  id,
  product_id,
  sku_code,
  variant_name,
  base_inventory_unit
)
values (
  '9a500000-0000-0000-0000-000000000001',
  '9a400000-0000-0000-0000-000000000001',
  'SUP-PROD-ACT-VAR-001',
  'Supplier Product Activity Variant',
  'piece'
);

insert into public.product_packaging (
  id,
  product_variant_id,
  package_code,
  package_name,
  units_per_package,
  is_purchase_default,
  effective_from
)
values (
  '9a600000-0000-0000-0000-000000000001',
  '9a500000-0000-0000-0000-000000000001',
  'CARTON',
  'Carton 1000',
  1000,
  true,
  date '2026-09-29'
);

insert into public.supplier_products (
  id,
  supplier_id,
  product_variant_id,
  packaging_id,
  supplier_sku,
  purchase_unit,
  is_preferred
)
values (
  '9a700000-0000-0000-0000-000000000001',
  '9a200000-0000-0000-0000-000000000001',
  '9a500000-0000-0000-0000-000000000001',
  '9a600000-0000-0000-0000-000000000001',
  'SUP-CUP-001',
  'carton',
  false
);

update public.supplier_products
set
  supplier_sku = 'SUP-CUP-001-REV',
  is_preferred = true
where id = '9a700000-0000-0000-0000-000000000001';

delete from public.supplier_products
where id = '9a700000-0000-0000-0000-000000000001';

reset role;

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_type = 'SUPPLIER_PRODUCT'
      and linked_entity_id = '9a700000-0000-0000-0000-000000000001'
  ),
  3::bigint,
  'create/update/delete each append one supplier-product activity record'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '9a700000-0000-0000-0000-000000000001'
      and action_type = 'SUPPLIER_PRODUCT_CREATED'
      and before_data is null
      and after_data ->> 'supplier_sku' = 'SUP-CUP-001'
      and after_data ->> 'is_preferred' = 'false'
  ),
  1::bigint,
  'supplier-product creation captures the post-change snapshot'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '9a700000-0000-0000-0000-000000000001'
      and action_type = 'SUPPLIER_PRODUCT_UPDATED'
      and before_data ->> 'supplier_sku' = 'SUP-CUP-001'
      and after_data ->> 'supplier_sku' = 'SUP-CUP-001-REV'
      and before_data ->> 'is_preferred' = 'false'
      and after_data ->> 'is_preferred' = 'true'
  ),
  1::bigint,
  'supplier-product update captures before and after snapshots'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '9a700000-0000-0000-0000-000000000001'
      and action_type = 'SUPPLIER_PRODUCT_DELETED'
      and before_data ->> 'supplier_sku' = 'SUP-CUP-001-REV'
      and after_data is null
  ),
  1::bigint,
  'supplier-product deletion captures the pre-delete snapshot'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '9a700000-0000-0000-0000-000000000001'
      and actor_user_id = '9a100000-0000-0000-0000-000000000001'
  ),
  3::bigint,
  'all supplier-product activity rows bind actor identity to auth.uid()'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '9a700000-0000-0000-0000-000000000001'
      and event_source = 'USER'
  ),
  3::bigint,
  'authenticated supplier-product mutations are marked as USER events'
);

select results_eq(
  $$
    select count(*)::bigint
    from public.activity_logs
    where linked_entity_id = '9a700000-0000-0000-0000-000000000001'
      and metadata ->> 'table_name' = 'supplier_products'
      and metadata ->> 'schema_name' = 'public'
      and metadata ->> 'supplier_id' = '9a200000-0000-0000-0000-000000000001'
      and metadata ->> 'product_variant_id' = '9a500000-0000-0000-0000-000000000001'
      and metadata ->> 'packaging_id' = '9a600000-0000-0000-0000-000000000001'
  $$,
  array[3::bigint],
  'supplier-product activity metadata records its database source and procurement linkage'
);

select * from finish();
rollback;
