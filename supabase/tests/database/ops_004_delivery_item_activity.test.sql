begin;

create extension if not exists pgtap with schema extensions;

select plan(12);

select results_eq(
  $$
    select count(*)::bigint
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'delivery_items'
      and t.tgname = 'delivery_items_capture_activity'
      and not t.tgisinternal
  $$,
  array[1::bigint],
  'OPS-004 installs one automatic delivery-item activity trigger'
);

select results_eq(
  $$
    select p.prosecdef
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'capture_delivery_item_activity'
      and p.pronargs = 0
  $$,
  array[true],
  'delivery-item activity capture executes as SECURITY DEFINER'
);

select results_eq(
  $$
    select has_function_privilege(
      'authenticated',
      'public.capture_delivery_item_activity()',
      'EXECUTE'
    )
  $$,
  array[false],
  'authenticated users cannot directly execute the delivery-item audit trigger function'
);

insert into auth.users (id, email)
values (
  'a0100000-0000-0000-0000-000000000001',
  'ops-delivery-item-activity-owner@example.test'
);

insert into public.user_roles (user_id, role_id)
select
  'a0100000-0000-0000-0000-000000000001'::uuid,
  r.id
from public.roles r
where r.code = 'OWNER_ADMIN';

insert into public.customers (
  id,
  customer_code,
  display_name
)
values (
  'a0200000-0000-0000-0000-000000000001',
  'DELIVERY-ITEM-ACTIVITY-CUSTOMER',
  'Delivery Item Activity Customer'
);

insert into public.product_categories (id, category_code, name)
values (
  'a0300000-0000-0000-0000-000000000001',
  'DELIVERY-ITEM-ACTIVITY',
  'Delivery Item Activity Category'
);

insert into public.products (id, category_id, name)
values (
  'a0400000-0000-0000-0000-000000000001',
  'a0300000-0000-0000-0000-000000000001',
  'Delivery Item Activity Product'
);

insert into public.product_variants (
  id,
  product_id,
  sku_code,
  variant_name
)
values (
  'a0500000-0000-0000-0000-000000000001',
  'a0400000-0000-0000-0000-000000000001',
  'DELIVERY-ITEM-ACTIVITY-SKU-001',
  'Delivery Item Activity Variant'
);

insert into public.sales_orders (
  id,
  order_number,
  customer_id,
  order_status,
  created_by_user_id,
  notes
)
values (
  'a0600000-0000-0000-0000-000000000001',
  'SO-DELIVERY-ITEM-ACTIVITY-001',
  'a0200000-0000-0000-0000-000000000001',
  'CONFIRMED',
  'a0100000-0000-0000-0000-000000000001',
  'OPS-004 delivery-item activity parent order'
);

insert into public.sales_order_items (
  id,
  sales_order_id,
  product_variant_id,
  sale_unit,
  sale_quantity,
  units_per_sale_unit,
  unit_price_per_sale_unit,
  print_mode,
  notes
)
values (
  'a0700000-0000-0000-0000-000000000001',
  'a0600000-0000-0000-0000-000000000001',
  'a0500000-0000-0000-0000-000000000001',
  'carton',
  1,
  1000,
  1200000,
  'PLAIN',
  'OPS-004 delivery-item activity source sales-order item'
);

insert into public.deliveries (
  id,
  delivery_number,
  sales_order_id,
  status,
  consignee_name,
  created_by_user_id,
  notes
)
values (
  'a0800000-0000-0000-0000-000000000001',
  'DELIVERY-ITEM-ACTIVITY-001',
  'a0600000-0000-0000-0000-000000000001',
  'NOT_READY',
  'Delivery Item Activity Consignee',
  'a0100000-0000-0000-0000-000000000001',
  'OPS-004 delivery-item activity parent delivery'
);

set local role authenticated;
set local request.jwt.claim.sub = 'a0100000-0000-0000-0000-000000000001';

insert into public.delivery_items (
  id,
  delivery_id,
  sales_order_item_id,
  product_variant_id,
  quantity_base_units,
  notes
)
values (
  'a0900000-0000-0000-0000-000000000001',
  'a0800000-0000-0000-0000-000000000001',
  'a0700000-0000-0000-0000-000000000001',
  'a0500000-0000-0000-0000-000000000001',
  500,
  'Initial delivery-item note'
);

update public.delivery_items
set
  quantity_base_units = 600,
  notes = 'Updated delivery-item note'
where id = 'a0900000-0000-0000-0000-000000000001';

reset role;
set local request.jwt.claim.sub = '';

delete from public.delivery_items
where id = 'a0900000-0000-0000-0000-000000000001';

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_type = 'DELIVERY_ITEM'
      and linked_entity_id = 'a0900000-0000-0000-0000-000000000001'
  ),
  3::bigint,
  'create/update/delete each append one delivery-item activity record'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = 'a0900000-0000-0000-0000-000000000001'
      and action_type = 'DELIVERY_ITEM_CREATED'
      and before_data is null
      and (after_data ->> 'quantity_base_units')::numeric = 500
      and after_data ->> 'notes' = 'Initial delivery-item note'
  ),
  1::bigint,
  'delivery-item creation captures the post-change snapshot'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = 'a0900000-0000-0000-0000-000000000001'
      and action_type = 'DELIVERY_ITEM_UPDATED'
      and (before_data ->> 'quantity_base_units')::numeric = 500
      and (after_data ->> 'quantity_base_units')::numeric = 600
      and before_data ->> 'notes' = 'Initial delivery-item note'
      and after_data ->> 'notes' = 'Updated delivery-item note'
  ),
  1::bigint,
  'delivery-item update captures before and after snapshots'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = 'a0900000-0000-0000-0000-000000000001'
      and action_type = 'DELIVERY_ITEM_DELETED'
      and (before_data ->> 'quantity_base_units')::numeric = 600
      and after_data is null
  ),
  1::bigint,
  'delivery-item deletion captures the pre-delete snapshot'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = 'a0900000-0000-0000-0000-000000000001'
      and actor_user_id = 'a0100000-0000-0000-0000-000000000001'
  ),
  2::bigint,
  'authenticated delivery-item create/update activity binds actor identity to auth.uid()'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = 'a0900000-0000-0000-0000-000000000001'
      and event_source = 'USER'
  ),
  2::bigint,
  'authenticated delivery-item mutations are marked as USER events'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = 'a0900000-0000-0000-0000-000000000001'
      and action_type = 'DELIVERY_ITEM_DELETED'
      and actor_user_id is null
      and event_source = 'SYSTEM'
  ),
  1::bigint,
  'trusted delivery-item deletion without an auth subject is marked as a SYSTEM event'
);

select results_eq(
  $$
    select count(*)::bigint
    from public.activity_logs
    where linked_entity_id = 'a0900000-0000-0000-0000-000000000001'
      and metadata ->> 'table_name' = 'delivery_items'
      and metadata ->> 'schema_name' = 'public'
  $$,
  array[3::bigint],
  'delivery-item activity metadata records its database source'
);

select results_eq(
  $$
    select count(*)::bigint
    from public.activity_logs
    where linked_entity_id = 'a0900000-0000-0000-0000-000000000001'
      and metadata ->> 'delivery_id' = 'a0800000-0000-0000-0000-000000000001'
      and metadata ->> 'sales_order_item_id' = 'a0700000-0000-0000-0000-000000000001'
      and metadata ->> 'product_variant_id' = 'a0500000-0000-0000-000000000001'
  $$,
  array[3::bigint],
  'delivery-item activity metadata preserves delivery, sales-order-item, and product linkage'
);

select * from finish();
rollback;
