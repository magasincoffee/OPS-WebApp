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
      and c.relname = 'purchase_order_items'
      and t.tgname = 'purchase_order_items_capture_activity'
      and not t.tgisinternal
  $$,
  array[1::bigint],
  'OPS-004 installs one automatic purchase-order-item activity trigger'
);

select results_eq(
  $$
    select p.prosecdef
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'capture_purchase_order_item_activity'
      and p.pronargs = 0
  $$,
  array[true],
  'purchase-order-item activity capture executes as SECURITY DEFINER'
);

select results_eq(
  $$
    select has_function_privilege(
      'authenticated',
      'public.capture_purchase_order_item_activity()',
      'EXECUTE'
    )
  $$,
  array[false],
  'authenticated users cannot directly execute the purchase-order-item audit trigger function'
);

insert into auth.users (id, email)
values (
  '98400000-0000-0000-0000-000000000001',
  'ops-purchase-order-item-activity-owner@example.test'
);

insert into public.user_roles (user_id, role_id)
select
  '98400000-0000-0000-0000-000000000001'::uuid,
  r.id
from public.roles r
where r.code = 'OWNER_ADMIN';

insert into public.suppliers (
  id,
  supplier_code,
  supplier_name
)
values (
  '98500000-0000-0000-0000-000000000001',
  'PO-ITEM-ACTIVITY-SUPPLIER',
  'Purchase Order Item Activity Supplier'
);

insert into public.product_categories (id, category_code, name)
values (
  '98600000-0000-0000-0000-000000000001',
  'POI-ACTIVITY',
  'Purchase Order Item Activity Category'
);

insert into public.products (id, category_id, name)
values (
  '98700000-0000-0000-0000-000000000001',
  '98600000-0000-0000-0000-000000000001',
  'Purchase Order Item Activity Product'
);

insert into public.product_variants (id, product_id, sku_code, variant_name)
values (
  '98800000-0000-0000-0000-000000000001',
  '98700000-0000-0000-0000-000000000001',
  'POI-ACTIVITY-SKU-001',
  'Purchase Order Item Activity Variant'
);

insert into public.purchase_orders (
  id,
  po_number,
  supplier_id,
  status,
  responsible_user_id,
  notes
)
values (
  '98900000-0000-0000-0000-000000000001',
  'PO-ITEM-ACTIVITY-001',
  '98500000-0000-0000-0000-000000000001',
  'ORDERED',
  '98400000-0000-0000-0000-000000000001',
  'OPS-004 purchase-order-item activity test parent'
);

set local role authenticated;
set local request.jwt.claim.sub = '98400000-0000-0000-0000-000000000001';

insert into public.purchase_order_items (
  id,
  purchase_order_id,
  product_variant_id,
  purchase_unit,
  package_quantity,
  units_per_purchase_unit,
  unit_cost_per_purchase_unit,
  notes
)
values (
  '98910000-0000-0000-0000-000000000001',
  '98900000-0000-0000-0000-000000000001',
  '98800000-0000-0000-0000-000000000001',
  'carton',
  2,
  1000,
  1200000,
  'Initial purchase-order-item note'
);

update public.purchase_order_items
set package_quantity = 3,
    notes = 'Updated purchase-order-item note'
where id = '98910000-0000-0000-0000-000000000001';

delete from public.purchase_order_items
where id = '98910000-0000-0000-0000-000000000001';

reset role;

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_type = 'PURCHASE_ORDER_ITEM'
      and linked_entity_id = '98910000-0000-0000-0000-000000000001'
  ),
  3::bigint,
  'create/update/delete each append one purchase-order-item activity record'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '98910000-0000-0000-0000-000000000001'
      and action_type = 'PURCHASE_ORDER_ITEM_CREATED'
      and before_data is null
      and (after_data ->> 'package_quantity')::numeric = 2
      and after_data ->> 'purchase_unit' = 'carton'
  ),
  1::bigint,
  'purchase-order-item creation captures the post-change snapshot'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '98910000-0000-0000-0000-000000000001'
      and action_type = 'PURCHASE_ORDER_ITEM_UPDATED'
      and (before_data ->> 'package_quantity')::numeric = 2
      and (after_data ->> 'package_quantity')::numeric = 3
      and before_data ->> 'notes' = 'Initial purchase-order-item note'
      and after_data ->> 'notes' = 'Updated purchase-order-item note'
  ),
  1::bigint,
  'purchase-order-item update captures before and after snapshots'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '98910000-0000-0000-0000-000000000001'
      and action_type = 'PURCHASE_ORDER_ITEM_DELETED'
      and before_data ->> 'purchase_unit' = 'carton'
      and after_data is null
  ),
  1::bigint,
  'purchase-order-item deletion captures the pre-delete snapshot'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '98910000-0000-0000-0000-000000000001'
      and actor_user_id = '98400000-0000-0000-0000-000000000001'
  ),
  3::bigint,
  'all purchase-order-item activity rows bind actor identity to auth.uid()'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '98910000-0000-0000-0000-000000000001'
      and event_source = 'USER'
  ),
  3::bigint,
  'authenticated purchase-order-item mutations are marked as USER events'
);

select results_eq(
  $$
    select count(*)::bigint
    from public.activity_logs
    where linked_entity_id = '98910000-0000-0000-0000-000000000001'
      and metadata ->> 'table_name' = 'purchase_order_items'
      and metadata ->> 'schema_name' = 'public'
  $$,
  array[3::bigint],
  'purchase-order-item activity metadata records its database source'
);

select results_eq(
  $$
    select count(*)::bigint
    from public.activity_logs
    where linked_entity_id = '98910000-0000-0000-0000-000000000001'
      and metadata ->> 'purchase_order_id' = '98900000-0000-0000-0000-000000000001'
      and metadata ->> 'product_variant_id' = '98800000-0000-0000-0000-000000000001'
  $$,
  array[3::bigint],
  'purchase-order-item activity metadata preserves parent order and product-variant linkage'
);

select * from finish();
rollback;
