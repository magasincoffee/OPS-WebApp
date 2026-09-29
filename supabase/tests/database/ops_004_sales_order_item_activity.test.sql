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
      and c.relname = 'sales_order_items'
      and t.tgname = 'sales_order_items_capture_activity'
      and not t.tgisinternal
  $$,
  array[1::bigint],
  'OPS-004 installs one automatic sales-order-item activity trigger'
);

select results_eq(
  $$
    select p.prosecdef
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'capture_sales_order_item_activity'
      and p.pronargs = 0
  $$,
  array[true],
  'sales-order-item activity capture executes as SECURITY DEFINER'
);

select results_eq(
  $$
    select has_function_privilege(
      'authenticated',
      'public.capture_sales_order_item_activity()',
      'EXECUTE'
    )
  $$,
  array[false],
  'authenticated users cannot directly execute the sales-order-item audit trigger function'
);

insert into auth.users (id, email)
values (
  '99000000-0000-0000-0000-000000000001',
  'ops-sales-order-item-activity@example.test'
);

insert into public.user_roles (user_id, role_id)
select
  '99000000-0000-0000-0000-000000000001'::uuid,
  r.id
from public.roles r
where r.code = 'SALES';

insert into public.customers (id, customer_code, display_name)
values (
  '99100000-0000-0000-0000-000000000001',
  'SO-ITEM-ACTIVITY-CUSTOMER',
  'Sales Order Item Activity Customer'
);

insert into public.product_categories (id, category_code, name)
values (
  '99200000-0000-0000-0000-000000000001',
  'SOI-ACTIVITY',
  'Sales Order Item Activity Category'
);

insert into public.products (id, category_id, name)
values (
  '99300000-0000-0000-0000-000000000001',
  '99200000-0000-0000-0000-000000000001',
  'Sales Order Item Activity Product'
);

insert into public.product_variants (id, product_id, sku_code, variant_name)
values (
  '99400000-0000-0000-0000-000000000001',
  '99300000-0000-0000-0000-000000000001',
  'SOI-ACTIVITY-SKU-001',
  'Sales Order Item Activity Variant'
);

insert into public.sales_orders (
  id,
  order_number,
  customer_id,
  created_by_user_id,
  salesperson_user_id
)
values (
  '99500000-0000-0000-0000-000000000001',
  'SO-ITEM-ACTIVITY-001',
  '99100000-0000-0000-0000-000000000001',
  '99000000-0000-0000-0000-000000000001',
  '99000000-0000-0000-0000-000000000001'
);

set local role authenticated;
set local request.jwt.claim.sub = '99000000-0000-0000-0000-000000000001';

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
  '99600000-0000-0000-0000-000000000001',
  '99500000-0000-0000-0000-000000000001',
  '99400000-0000-0000-0000-000000000001',
  'carton',
  2,
  1000,
  1500000
);

update public.sales_order_items
set sale_quantity = 3
where id = '99600000-0000-0000-0000-000000000001';

delete from public.sales_order_items
where id = '99600000-0000-0000-0000-000000000001';

reset role;

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_type = 'SALES_ORDER_ITEM'
      and linked_entity_id = '99600000-0000-0000-0000-000000000001'
  ),
  3::bigint,
  'create/update/delete each append one sales-order-item activity record'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '99600000-0000-0000-0000-000000000001'
      and action_type = 'SALES_ORDER_ITEM_CREATED'
      and before_data is null
      and after_data ->> 'sale_quantity' = '2.000000'
  ),
  1::bigint,
  'sales-order-item creation captures the post-change snapshot'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '99600000-0000-0000-0000-000000000001'
      and action_type = 'SALES_ORDER_ITEM_UPDATED'
      and before_data ->> 'sale_quantity' = '2.000000'
      and after_data ->> 'sale_quantity' = '3.000000'
  ),
  1::bigint,
  'sales-order-item update captures before and after quantity snapshots'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '99600000-0000-0000-0000-000000000001'
      and action_type = 'SALES_ORDER_ITEM_DELETED'
      and before_data ->> 'sale_unit' = 'carton'
      and after_data is null
  ),
  1::bigint,
  'sales-order-item deletion captures the pre-delete snapshot'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '99600000-0000-0000-0000-000000000001'
      and actor_user_id = '99000000-0000-0000-0000-000000000001'
  ),
  3::bigint,
  'all sales-order-item activity rows bind actor identity to auth.uid()'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '99600000-0000-0000-0000-000000000001'
      and event_source = 'USER'
  ),
  3::bigint,
  'authenticated sales-order-item mutations are marked as USER events'
);

select results_eq(
  $$
    select count(*)::bigint
    from public.activity_logs
    where linked_entity_id = '99600000-0000-0000-0000-000000000001'
      and metadata ->> 'table_name' = 'sales_order_items'
      and metadata ->> 'schema_name' = 'public'
      and metadata ->> 'sales_order_id' = '99500000-0000-0000-0000-000000000001'
  $$,
  array[3::bigint],
  'sales-order-item activity metadata records its database source and parent sales order'
);

select * from finish();
rollback;
