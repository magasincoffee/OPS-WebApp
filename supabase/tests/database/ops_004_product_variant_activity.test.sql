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
      and c.relname = 'product_variants'
      and t.tgname = 'product_variants_capture_activity'
      and not t.tgisinternal
  $$,
  array[1::bigint],
  'OPS-004 installs one automatic product-variant activity trigger'
);

select results_eq(
  $$
    select p.prosecdef
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'capture_product_variant_activity'
      and p.pronargs = 0
  $$,
  array[true],
  'product-variant activity capture executes as SECURITY DEFINER'
);

select results_eq(
  $$
    select has_function_privilege(
      'authenticated',
      'public.capture_product_variant_activity()',
      'EXECUTE'
    )
  $$,
  array[false],
  'authenticated users cannot directly execute the product-variant audit trigger function'
);

insert into auth.users (id, email)
values (
  '98700000-0000-0000-0000-000000000001',
  'ops-product-variant-activity@example.test'
);

insert into public.user_roles (user_id, role_id)
select
  '98700000-0000-0000-0000-000000000001'::uuid,
  r.id
from public.roles r
where r.code = 'OWNER_ADMIN';

set local role authenticated;
set local request.jwt.claim.sub = '98700000-0000-0000-0000-000000000001';

insert into public.product_categories (
  id,
  category_code,
  name
)
values (
  '98800000-0000-0000-0000-000000000001',
  'VARIANT-ACTIVITY-CATEGORY',
  'Variant Activity Category'
);

insert into public.products (
  id,
  category_id,
  name,
  product_type
)
values (
  '98900000-0000-0000-0000-000000000001',
  '98800000-0000-0000-0000-000000000001',
  'Variant Activity Product',
  'CUP'
);

insert into public.product_variants (
  id,
  product_id,
  sku_code,
  variant_name,
  capacity_value,
  capacity_unit,
  base_inventory_unit,
  minimum_stock_quantity
)
values (
  '99000000-0000-0000-0000-000000000001',
  '98900000-0000-0000-0000-000000000001',
  'VAR-ACT-001',
  'Variant Activity Initial',
  12,
  'oz',
  'piece',
  100
);

update public.product_variants
set
  variant_name = 'Variant Activity Updated',
  minimum_stock_quantity = 250
where id = '99000000-0000-0000-0000-000000000001';

delete from public.product_variants
where id = '99000000-0000-0000-0000-000000000001';

reset role;

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_type = 'PRODUCT_VARIANT'
      and linked_entity_id = '99000000-0000-0000-0000-000000000001'
  ),
  3::bigint,
  'create/update/delete each append one product-variant activity record'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '99000000-0000-0000-0000-000000000001'
      and action_type = 'PRODUCT_VARIANT_CREATED'
      and before_data is null
      and after_data ->> 'sku_code' = 'VAR-ACT-001'
      and after_data ->> 'variant_name' = 'Variant Activity Initial'
  ),
  1::bigint,
  'product-variant creation captures the post-change snapshot'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '99000000-0000-0000-0000-000000000001'
      and action_type = 'PRODUCT_VARIANT_UPDATED'
      and before_data ->> 'variant_name' = 'Variant Activity Initial'
      and after_data ->> 'variant_name' = 'Variant Activity Updated'
      and before_data ->> 'minimum_stock_quantity' = '100.000000'
      and after_data ->> 'minimum_stock_quantity' = '250.000000'
  ),
  1::bigint,
  'product-variant update captures before and after snapshots'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '99000000-0000-0000-0000-000000000001'
      and action_type = 'PRODUCT_VARIANT_DELETED'
      and before_data ->> 'variant_name' = 'Variant Activity Updated'
      and after_data is null
  ),
  1::bigint,
  'product-variant deletion captures the pre-delete snapshot'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '99000000-0000-0000-0000-000000000001'
      and actor_user_id = '98700000-0000-0000-0000-000000000001'
  ),
  3::bigint,
  'all product-variant activity rows bind actor identity to auth.uid()'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '99000000-0000-0000-0000-000000000001'
      and event_source = 'USER'
  ),
  3::bigint,
  'authenticated product-variant mutations are marked as USER events'
);

select results_eq(
  $$
    select count(*)::bigint
    from public.activity_logs
    where linked_entity_id = '99000000-0000-0000-0000-000000000001'
      and metadata ->> 'table_name' = 'product_variants'
      and metadata ->> 'schema_name' = 'public'
      and metadata ->> 'product_id' = '98900000-0000-0000-0000-000000000001'
      and metadata ->> 'sku_code' = 'VAR-ACT-001'
  $$,
  array[3::bigint],
  'product-variant activity metadata records its database source and product linkage'
);

select * from finish();
rollback;
