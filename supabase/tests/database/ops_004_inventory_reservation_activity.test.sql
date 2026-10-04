begin;

create extension if not exists pgtap with schema extensions;

select plan(11);

select results_eq(
  $$
    select count(*)::bigint
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'inventory_reservations'
      and t.tgname = 'inventory_reservations_capture_activity'
      and not t.tgisinternal
  $$,
  array[1::bigint],
  'OPS-004 installs one automatic inventory-reservation activity trigger'
);

select results_eq(
  $$
    select p.prosecdef
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'capture_inventory_reservation_activity'
      and p.pronargs = 0
  $$,
  array[true],
  'inventory-reservation activity capture executes as SECURITY DEFINER'
);

select results_eq(
  $$
    select has_function_privilege(
      'authenticated',
      'public.capture_inventory_reservation_activity()',
      'EXECUTE'
    )
  $$,
  array[false],
  'authenticated users cannot directly execute the inventory-reservation audit trigger function'
);

insert into auth.users (id, email)
values (
  '9a100000-0000-0000-0000-000000000001',
  'ops-inventory-reservation-activity-owner@example.test'
);

insert into public.user_roles (user_id, role_id)
select
  '9a100000-0000-0000-0000-000000000001'::uuid,
  r.id
from public.roles r
where r.code = 'OWNER_ADMIN';

insert into public.customers (id, customer_code, display_name)
values (
  '9a200000-0000-0000-0000-000000000001',
  'IR-ACTIVITY-CUSTOMER',
  'Inventory Reservation Activity Customer'
);

insert into public.product_categories (id, category_code, name)
values (
  '9a300000-0000-0000-0000-000000000001',
  'IR-ACTIVITY',
  'Inventory Reservation Activity Category'
);

insert into public.products (id, category_id, name)
values (
  '9a400000-0000-0000-0000-000000000001',
  '9a300000-0000-0000-0000-000000000001',
  'Inventory Reservation Activity Product'
);

insert into public.product_variants (id, product_id, sku_code, variant_name)
values (
  '9a500000-0000-0000-0000-000000000001',
  '9a400000-0000-0000-0000-000000000001',
  'IR-ACTIVITY-SKU-001',
  'Inventory Reservation Activity Variant'
);

insert into public.sales_orders (
  id,
  order_number,
  customer_id,
  created_by_user_id,
  salesperson_user_id
)
values (
  '9a600000-0000-0000-0000-000000000001',
  'IR-ACTIVITY-SO-001',
  '9a200000-0000-0000-0000-000000000001',
  '9a100000-0000-0000-0000-000000000001',
  '9a100000-0000-0000-0000-000000000001'
);

insert into public.sales_order_items (
  id,
  sales_order_id,
  product_variant_id,
  sale_unit,
  sale_quantity,
  units_per_sale_unit,
  unit_price_per_sale_unit
)
values (
  '9a700000-0000-0000-0000-000000000001',
  '9a600000-0000-0000-0000-000000000001',
  '9a500000-0000-0000-0000-000000000001',
  'carton',
  2,
  1000,
  1500000
);

-- OPS-023 production hardening revokes direct reservation mutation from authenticated.
-- This legacy OPS-004 audit fixture temporarily restores those table privileges
-- inside its transaction so it can continue exercising CREATE/UPDATE/DELETE
-- activity capture directly; ROLLBACK below restores production privileges.
grant insert, update, delete on public.inventory_reservations to authenticated;

set local role authenticated;
set local request.jwt.claim.sub = '9a100000-0000-0000-0000-000000000001';

insert into public.inventory_reservations (
  id,
  sales_order_item_id,
  product_variant_id,
  requested_base_quantity,
  created_by_user_id,
  notes
)
values (
  '9a800000-0000-0000-0000-000000000001',
  '9a700000-0000-0000-0000-000000000001',
  '9a500000-0000-0000-0000-000000000001',
  1500,
  '9a100000-0000-0000-0000-000000000001',
  'Initial inventory reservation note'
);

update public.inventory_reservations
set requested_base_quantity = 1200,
    notes = 'Updated inventory reservation note'
where id = '9a800000-0000-0000-0000-000000000001';

delete from public.inventory_reservations
where id = '9a800000-0000-0000-0000-000000000001';

reset role;

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_type = 'INVENTORY_RESERVATION'
      and linked_entity_id = '9a800000-0000-0000-0000-000000000001'
  ),
  3::bigint,
  'create/update/delete each append one inventory-reservation activity record'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '9a800000-0000-0000-0000-000000000001'
      and action_type = 'INVENTORY_RESERVATION_CREATED'
      and before_data is null
      and (after_data ->> 'requested_base_quantity')::numeric = 1500
      and after_data ->> 'notes' = 'Initial inventory reservation note'
  ),
  1::bigint,
  'inventory-reservation creation captures the post-change snapshot'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '9a800000-0000-0000-0000-000000000001'
      and action_type = 'INVENTORY_RESERVATION_UPDATED'
      and (before_data ->> 'requested_base_quantity')::numeric = 1500
      and (after_data ->> 'requested_base_quantity')::numeric = 1200
      and before_data ->> 'notes' = 'Initial inventory reservation note'
      and after_data ->> 'notes' = 'Updated inventory reservation note'
  ),
  1::bigint,
  'inventory-reservation update captures before and after snapshots'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '9a800000-0000-0000-0000-000000000001'
      and action_type = 'INVENTORY_RESERVATION_DELETED'
      and (before_data ->> 'requested_base_quantity')::numeric = 1200
      and after_data is null
  ),
  1::bigint,
  'inventory-reservation deletion captures the pre-delete snapshot'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '9a800000-0000-0000-0000-000000000001'
      and actor_user_id = '9a100000-0000-0000-0000-000000000001'
  ),
  3::bigint,
  'all inventory-reservation activity rows bind actor identity to auth.uid()'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '9a800000-0000-0000-0000-000000000001'
      and event_source = 'USER'
  ),
  3::bigint,
  'authenticated inventory-reservation mutations are marked as USER events'
);

select results_eq(
  $$
    select count(*)::bigint
    from public.activity_logs
    where linked_entity_id = '9a800000-0000-0000-0000-000000000001'
      and metadata ->> 'table_name' = 'inventory_reservations'
      and metadata ->> 'schema_name' = 'public'
  $$,
  array[3::bigint],
  'inventory-reservation activity metadata records its database source'
);

select results_eq(
  $$
    select count(*)::bigint
    from public.activity_logs
    where linked_entity_id = '9a800000-0000-0000-0000-000000000001'
      and metadata ->> 'sales_order_item_id' = '9a700000-0000-0000-0000-000000000001'
      and metadata ->> 'product_variant_id' = '9a500000-0000-0000-0000-000000000001'
  $$,
  array[3::bigint],
  'inventory-reservation activity metadata preserves sales-order-item and product-variant linkage'
);

select * from finish();
rollback;
