begin;

create extension if not exists pgtap with schema extensions;

select plan(8);

select results_eq(
  $$
    select count(*)::bigint
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'inventory_movements'
      and t.tgname = 'inventory_movements_capture_activity'
      and not t.tgisinternal
  $$,
  array[1::bigint],
  'OPS-004 installs one automatic inventory-movement activity trigger'
);

select results_eq(
  $$
    select p.prosecdef
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'capture_inventory_movement_activity'
      and p.pronargs = 0
  $$,
  array[true],
  'inventory-movement activity capture executes as SECURITY DEFINER'
);

select results_eq(
  $$
    select has_function_privilege(
      'authenticated',
      'public.capture_inventory_movement_activity()',
      'EXECUTE'
    )
  $$,
  array[false],
  'authenticated users cannot directly execute the inventory-movement audit trigger function'
);

insert into auth.users (id, email)
values (
  '9b100000-0000-0000-0000-000000000001',
  'ops-inventory-movement-activity-owner@example.test'
);

insert into public.user_roles (user_id, role_id)
select
  '9b100000-0000-0000-0000-000000000001'::uuid,
  r.id
from public.roles r
where r.code = 'OWNER_ADMIN';

insert into public.product_categories (id, category_code, name)
values (
  '9b200000-0000-0000-0000-000000000001',
  'IM-ACTIVITY',
  'Inventory Movement Activity Category'
);

insert into public.products (id, category_id, name)
values (
  '9b300000-0000-0000-0000-000000000001',
  '9b200000-0000-0000-0000-000000000001',
  'Inventory Movement Activity Product'
);

insert into public.product_variants (id, product_id, sku_code, variant_name)
values (
  '9b400000-0000-0000-0000-000000000001',
  '9b300000-0000-0000-0000-000000000001',
  'IM-ACTIVITY-SKU-001',
  'Inventory Movement Activity Variant'
);

set local role authenticated;
set local request.jwt.claim.sub = '9b100000-0000-0000-0000-000000000001';

insert into public.inventory_movements (
  id,
  product_variant_id,
  movement_type,
  quantity_delta_base_units,
  reference,
  reason,
  created_by_user_id
)
values (
  '9b500000-0000-0000-0000-000000000001',
  '9b400000-0000-0000-0000-000000000001',
  'ADJUSTMENT_IN',
  2500,
  'IM-ACTIVITY-REF-001',
  'Initial controlled stock adjustment',
  '9b100000-0000-0000-0000-000000000001'
);

reset role;

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_type = 'INVENTORY_MOVEMENT'
      and linked_entity_id = '9b500000-0000-0000-0000-000000000001'
  ),
  1::bigint,
  'inventory movement insertion appends one activity record'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '9b500000-0000-0000-0000-000000000001'
      and action_type = 'INVENTORY_MOVEMENT_CREATED'
      and before_data is null
      and after_data ->> 'movement_type' = 'ADJUSTMENT_IN'
      and (after_data ->> 'quantity_delta_base_units')::numeric = 2500
      and after_data ->> 'reference' = 'IM-ACTIVITY-REF-001'
      and after_data ->> 'reason' = 'Initial controlled stock adjustment'
  ),
  1::bigint,
  'inventory-movement creation captures the complete post-insert business snapshot'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '9b500000-0000-0000-0000-000000000001'
      and actor_user_id = '9b100000-0000-0000-0000-000000000001'
      and event_source = 'USER'
  ),
  1::bigint,
  'inventory-movement activity binds authenticated actor identity and USER source'
);

select results_eq(
  $$
    select count(*)::bigint
    from public.activity_logs
    where linked_entity_id = '9b500000-0000-0000-0000-000000000001'
      and metadata ->> 'table_name' = 'inventory_movements'
      and metadata ->> 'schema_name' = 'public'
      and metadata ->> 'operation' = 'INSERT'
      and metadata ->> 'movement_type' = 'ADJUSTMENT_IN'
      and metadata ->> 'product_variant_id' = '9b400000-0000-0000-0000-000000000001'
  $$,
  array[1::bigint],
  'inventory-movement activity metadata preserves database source and movement linkage'
);

select results_eq(
  $$
    select count(*)::bigint
    from public.activity_logs
    where linked_entity_id = '9b500000-0000-0000-0000-000000000001'
      and metadata -> 'inventory_reservation_id' = 'null'::jsonb
      and metadata -> 'goods_receipt_item_id' = 'null'::jsonb
      and metadata -> 'sales_order_item_id' = 'null'::jsonb
  $$,
  array[1::bigint],
  'inventory-movement activity metadata explicitly preserves absent optional source links'
);

select * from finish();
rollback;
