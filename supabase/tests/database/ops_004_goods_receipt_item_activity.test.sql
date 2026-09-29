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
      and c.relname = 'goods_receipt_items'
      and t.tgname = 'goods_receipt_items_capture_activity'
      and not t.tgisinternal
  $$,
  array[1::bigint],
  'OPS-004 installs one automatic goods-receipt-item activity trigger'
);

select results_eq(
  $$
    select p.prosecdef
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'capture_goods_receipt_item_activity'
      and p.pronargs = 0
  $$,
  array[true],
  'goods-receipt-item activity capture executes as SECURITY DEFINER'
);

select results_eq(
  $$
    select has_function_privilege(
      'authenticated',
      'public.capture_goods_receipt_item_activity()',
      'EXECUTE'
    )
  $$,
  array[false],
  'authenticated users cannot directly execute the goods-receipt-item audit trigger function'
);

insert into auth.users (id, email)
values (
  '99100000-0000-0000-0000-000000000001',
  'ops-goods-receipt-item-activity-owner@example.test'
);

insert into public.user_roles (user_id, role_id)
select
  '99100000-0000-0000-0000-000000000001'::uuid,
  r.id
from public.roles r
where r.code = 'OWNER_ADMIN';

insert into public.suppliers (
  id,
  supplier_code,
  supplier_name
)
values (
  '99200000-0000-0000-0000-000000000001',
  'GRI-ACTIVITY-SUPPLIER',
  'Goods Receipt Item Activity Supplier'
);

insert into public.product_categories (id, category_code, name)
values (
  '99300000-0000-0000-0000-000000000001',
  'GRI-ACTIVITY',
  'Goods Receipt Item Activity Category'
);

insert into public.products (id, category_id, name)
values (
  '99400000-0000-0000-0000-000000000001',
  '99300000-0000-0000-0000-000000000001',
  'Goods Receipt Item Activity Product'
);

insert into public.product_variants (id, product_id, sku_code, variant_name)
values (
  '99500000-0000-0000-0000-000000000001',
  '99400000-0000-0000-0000-000000000001',
  'GRI-ACTIVITY-SKU-001',
  'Goods Receipt Item Activity Variant'
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
  '99600000-0000-0000-0000-000000000001',
  'GRI-ACTIVITY-PO-001',
  '99200000-0000-0000-0000-000000000001',
  'ORDERED',
  '99100000-0000-0000-0000-000000000001',
  'OPS-004 goods-receipt-item activity test purchase order'
);

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
  '99700000-0000-0000-0000-000000000001',
  '99600000-0000-0000-0000-000000000001',
  '99500000-0000-0000-0000-000000000001',
  'carton',
  5,
  1000,
  1200000,
  'OPS-004 goods-receipt-item activity test purchase-order item'
);

insert into public.goods_receipts (
  id,
  goods_receipt_number,
  purchase_order_id,
  received_by_user_id,
  notes
)
values (
  '99800000-0000-0000-0000-000000000001',
  'GRI-ACTIVITY-GR-001',
  '99600000-0000-0000-0000-000000000001',
  '99100000-0000-0000-0000-000000000001',
  'OPS-004 goods-receipt-item activity test parent receipt'
);

set local role authenticated;
set local request.jwt.claim.sub = '99100000-0000-0000-0000-000000000001';

insert into public.goods_receipt_items (
  id,
  goods_receipt_id,
  purchase_order_item_id,
  package_quantity,
  units_per_purchase_unit,
  notes
)
values (
  '99900000-0000-0000-0000-000000000001',
  '99800000-0000-0000-0000-000000000001',
  '99700000-0000-0000-0000-000000000001',
  2,
  1000,
  'Initial goods-receipt-item note'
);

update public.goods_receipt_items
set package_quantity = 3,
    notes = 'Updated goods-receipt-item note'
where id = '99900000-0000-0000-0000-000000000001';

delete from public.goods_receipt_items
where id = '99900000-0000-0000-0000-000000000001';

reset role;

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_type = 'GOODS_RECEIPT_ITEM'
      and linked_entity_id = '99900000-0000-0000-0000-000000000001'
  ),
  3::bigint,
  'create/update/delete each append one goods-receipt-item activity record'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '99900000-0000-0000-0000-000000000001'
      and action_type = 'GOODS_RECEIPT_ITEM_CREATED'
      and before_data is null
      and (after_data ->> 'package_quantity')::numeric = 2
      and (after_data ->> 'base_quantity')::numeric = 2000
  ),
  1::bigint,
  'goods-receipt-item creation captures the post-change snapshot'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '99900000-0000-0000-0000-000000000001'
      and action_type = 'GOODS_RECEIPT_ITEM_UPDATED'
      and (before_data ->> 'package_quantity')::numeric = 2
      and (after_data ->> 'package_quantity')::numeric = 3
      and before_data ->> 'notes' = 'Initial goods-receipt-item note'
      and after_data ->> 'notes' = 'Updated goods-receipt-item note'
  ),
  1::bigint,
  'goods-receipt-item update captures before and after snapshots'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '99900000-0000-0000-0000-000000000001'
      and action_type = 'GOODS_RECEIPT_ITEM_DELETED'
      and (before_data ->> 'base_quantity')::numeric = 3000
      and after_data is null
  ),
  1::bigint,
  'goods-receipt-item deletion captures the pre-delete snapshot'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '99900000-0000-0000-0000-000000000001'
      and actor_user_id = '99100000-0000-0000-0000-000000000001'
  ),
  3::bigint,
  'all goods-receipt-item activity rows bind actor identity to auth.uid()'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '99900000-0000-0000-0000-000000000001'
      and event_source = 'USER'
  ),
  3::bigint,
  'authenticated goods-receipt-item mutations are marked as USER events'
);

select results_eq(
  $$
    select count(*)::bigint
    from public.activity_logs
    where linked_entity_id = '99900000-0000-0000-0000-000000000001'
      and metadata ->> 'table_name' = 'goods_receipt_items'
      and metadata ->> 'schema_name' = 'public'
  $$,
  array[3::bigint],
  'goods-receipt-item activity metadata records its database source'
);

select results_eq(
  $$
    select count(*)::bigint
    from public.activity_logs
    where linked_entity_id = '99900000-0000-0000-0000-000000000001'
      and metadata ->> 'goods_receipt_id' = '99800000-0000-0000-0000-000000000001'
      and metadata ->> 'purchase_order_item_id' = '99700000-0000-0000-0000-000000000001'
  $$,
  array[3::bigint],
  'goods-receipt-item activity metadata preserves parent receipt and purchase-order-item linkage'
);

select * from finish();
rollback;
