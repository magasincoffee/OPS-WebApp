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
      and c.relname = 'product_packaging'
      and t.tgname = 'product_packaging_capture_activity'
      and not t.tgisinternal
  $$,
  array[1::bigint],
  'OPS-004 installs one automatic product-packaging activity trigger'
);

select results_eq(
  $$
    select p.prosecdef
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'capture_product_packaging_activity'
      and p.pronargs = 0
  $$,
  array[true],
  'product-packaging activity capture executes as SECURITY DEFINER'
);

select results_eq(
  $$
    select has_function_privilege(
      'authenticated',
      'public.capture_product_packaging_activity()',
      'EXECUTE'
    )
  $$,
  array[false],
  'authenticated users cannot directly execute the product-packaging audit trigger function'
);

insert into auth.users (id, email)
values (
  '99100000-0000-0000-0000-000000000001',
  'ops-product-packaging-activity@example.test'
);

insert into public.user_roles (user_id, role_id)
select
  '99100000-0000-0000-0000-000000000001'::uuid,
  r.id
from public.roles r
where r.code = 'OWNER_ADMIN';

set local role authenticated;
set local request.jwt.claim.sub = '99100000-0000-0000-0000-000000000001';

insert into public.product_categories (
  id,
  category_code,
  name
)
values (
  '99200000-0000-0000-0000-000000000001',
  'PACKAGING-ACTIVITY-CATEGORY',
  'Packaging Activity Category'
);

insert into public.products (
  id,
  category_id,
  name,
  product_type
)
values (
  '99300000-0000-0000-0000-000000000001',
  '99200000-0000-0000-0000-000000000001',
  'Packaging Activity Product',
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
  '99400000-0000-0000-0000-000000000001',
  '99300000-0000-0000-0000-000000000001',
  'PACK-ACT-VAR-001',
  'Packaging Activity Variant',
  'piece'
);

insert into public.product_packaging (
  id,
  product_variant_id,
  package_code,
  package_name,
  units_per_package,
  is_purchase_default,
  is_sale_default,
  effective_from
)
values (
  '99500000-0000-0000-0000-000000000001',
  '99400000-0000-0000-0000-000000000001',
  'CARTON',
  'Carton 1000',
  1000,
  true,
  true,
  date '2026-09-29'
);

update public.product_packaging
set
  package_name = 'Carton 500',
  units_per_package = 500
where id = '99500000-0000-0000-0000-000000000001';

delete from public.product_packaging
where id = '99500000-0000-0000-0000-000000000001';

reset role;

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_type = 'PRODUCT_PACKAGING'
      and linked_entity_id = '99500000-0000-0000-0000-000000000001'
  ),
  3::bigint,
  'create/update/delete each append one product-packaging activity record'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '99500000-0000-0000-0000-000000000001'
      and action_type = 'PRODUCT_PACKAGING_CREATED'
      and before_data is null
      and after_data ->> 'package_code' = 'CARTON'
      and after_data ->> 'package_name' = 'Carton 1000'
      and after_data ->> 'units_per_package' = '1000.000000'
  ),
  1::bigint,
  'product-packaging creation captures the post-change snapshot'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '99500000-0000-0000-0000-000000000001'
      and action_type = 'PRODUCT_PACKAGING_UPDATED'
      and before_data ->> 'package_name' = 'Carton 1000'
      and after_data ->> 'package_name' = 'Carton 500'
      and before_data ->> 'units_per_package' = '1000.000000'
      and after_data ->> 'units_per_package' = '500.000000'
  ),
  1::bigint,
  'product-packaging update captures before and after snapshots'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '99500000-0000-0000-0000-000000000001'
      and action_type = 'PRODUCT_PACKAGING_DELETED'
      and before_data ->> 'package_name' = 'Carton 500'
      and after_data is null
  ),
  1::bigint,
  'product-packaging deletion captures the pre-delete snapshot'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '99500000-0000-0000-0000-000000000001'
      and actor_user_id = '99100000-0000-0000-0000-000000000001'
  ),
  3::bigint,
  'all product-packaging activity rows bind actor identity to auth.uid()'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '99500000-0000-0000-0000-000000000001'
      and event_source = 'USER'
  ),
  3::bigint,
  'authenticated product-packaging mutations are marked as USER events'
);

select results_eq(
  $$
    select count(*)::bigint
    from public.activity_logs
    where linked_entity_id = '99500000-0000-0000-0000-000000000001'
      and metadata ->> 'table_name' = 'product_packaging'
      and metadata ->> 'schema_name' = 'public'
      and metadata ->> 'product_variant_id' = '99400000-0000-0000-0000-000000000001'
      and metadata ->> 'package_code' = 'CARTON'
  $$,
  array[3::bigint],
  'product-packaging activity metadata records its database source and variant linkage'
);

select * from finish();
rollback;
