begin;

create extension if not exists pgtap with schema extensions;

select plan(12);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname='public'
      and tablename='inventory_movements'
      and policyname='inventory_movements_select_warehouse_or_owner'
      and cmd='SELECT'
      and qual like '%OWNER_ADMIN%'
      and qual like '%WAREHOUSE%'
  $$,
  array[1::bigint],
  'inventory ledger read remains OWNER_ADMIN/WAREHOUSE'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname='public'
      and tablename='inventory_movements'
      and policyname='inventory_movements_insert_warehouse_or_owner'
      and cmd='INSERT'
      and with_check like '%OWNER_ADMIN%'
      and with_check like '%WAREHOUSE%'
  $$,
  array[1::bigint],
  'inventory ledger insert remains OWNER_ADMIN/WAREHOUSE'
);

select is(
  has_table_privilege('authenticated','public.inventory_movements','UPDATE'),
  false,
  'authenticated role cannot update immutable inventory movements'
);

select is(
  has_table_privilege('authenticated','public.inventory_movements','DELETE'),
  false,
  'authenticated role cannot delete immutable inventory movements'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_class c
    join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public'
      and c.relname='inventory_stock_snapshot'
      and c.relkind='v'
      and coalesce(c.reloptions,array[]::text[]) @> array['security_invoker=true']
  $$,
  array[1::bigint],
  'inventory stock snapshot remains security-invoker'
);

select is(
  has_table_privilege('authenticated','public.inventory_stock_snapshot','SELECT'),
  true,
  'authenticated receives SELECT on the RLS-backed stock snapshot'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_trigger
    where not tgisinternal
      and tgrelid='public.inventory_movements'::regclass
      and tgname='inventory_movements_guard_goods_receipt_source'
  $$,
  array[1::bigint],
  'OPS-022 installs a database guard for goods-receipt inventory posting'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_trigger
    where not tgisinternal
      and tgrelid='public.inventory_movements'::regclass
      and tgname='inventory_movements_post_goods_receipt_cost_history'
  $$,
  array[1::bigint],
  'OPS-022 installs automatic purchase-cost history posting'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_indexes
    where schemaname='public'
      and tablename='inventory_movements'
      and indexname='inventory_movements_one_goods_receipt_post_per_item'
      and indexdef like '%UNIQUE%'
  $$,
  array[1::bigint],
  'one goods-receipt inventory post per receipt line remains enforced'
);

insert into auth.users (id,email)
values (
  'a8100000-0000-0000-0000-000000000001',
  'ops-022-warehouse@example.test'
);

insert into public.user_roles (user_id,role_id)
select
  'a8100000-0000-0000-0000-000000000001'::uuid,
  r.id
from public.roles r
where r.code='WAREHOUSE';

insert into public.suppliers (id,supplier_code,supplier_name)
values (
  'a8200000-0000-0000-0000-000000000001',
  'OPS022-SUPPLIER',
  'OPS-022 Supplier'
);

insert into public.product_categories (id,category_code,name)
values (
  'a8300000-0000-0000-0000-000000000001',
  'OPS022',
  'OPS-022 Category'
);

insert into public.products (id,category_id,name)
values (
  'a8400000-0000-0000-0000-000000000001',
  'a8300000-0000-0000-0000-000000000001',
  'OPS-022 Product'
);

insert into public.product_variants (
  id,product_id,sku_code,variant_name,base_inventory_unit
)
values (
  'a8500000-0000-0000-0000-000000000001',
  'a8400000-0000-0000-0000-000000000001',
  'OPS022-SKU',
  'OPS-022 Variant',
  'piece'
);

insert into public.purchase_orders (
  id,po_number,supplier_id,status,freight_amount,currency_code,responsible_user_id
)
values (
  'a8600000-0000-0000-0000-000000000001',
  'OPS022-PO',
  'a8200000-0000-0000-0000-000000000001',
  'ORDERED',
  600,
  'VND',
  'a8100000-0000-0000-0000-000000000001'
);

insert into public.purchase_order_items (
  id,purchase_order_id,product_variant_id,purchase_unit,
  package_quantity,units_per_purchase_unit,unit_cost_per_purchase_unit
)
values (
  'a8700000-0000-0000-0000-000000000001',
  'a8600000-0000-0000-0000-000000000001',
  'a8500000-0000-0000-0000-000000000001',
  'carton',
  2,
  10,
  1000
);

insert into public.purchase_payments (
  id,purchase_order_id,amount,payment_date,payment_method,created_by_user_id
)
values (
  'a8800000-0000-0000-0000-000000000001',
  'a8600000-0000-0000-0000-000000000001',
  2600,
  current_date,
  'BANK_TRANSFER',
  'a8100000-0000-0000-0000-000000000001'
);

insert into public.goods_receipts (
  id,goods_receipt_number,purchase_order_id,received_by_user_id
)
values (
  'a8900000-0000-0000-0000-000000000001',
  'OPS022-GR',
  'a8600000-0000-0000-0000-000000000001',
  'a8100000-0000-0000-0000-000000000001'
);

insert into public.goods_receipt_items (
  id,goods_receipt_id,purchase_order_item_id,package_quantity,units_per_purchase_unit
)
values (
  'a9000000-0000-0000-0000-000000000001',
  'a8900000-0000-0000-0000-000000000001',
  'a8700000-0000-0000-0000-000000000001',
  1,
  10
);

set local role authenticated;
set local request.jwt.claim.sub='a8100000-0000-0000-0000-000000000001';

insert into public.inventory_movements (
  product_variant_id,
  movement_type,
  quantity_delta_base_units,
  goods_receipt_item_id
)
values (
  'a8500000-0000-0000-0000-000000000001',
  'GOODS_RECEIPT',
  10,
  'a9000000-0000-0000-0000-000000000001'
);

reset role;

select results_eq(
  $$
    select
      on_hand_quantity,
      reserved_quantity,
      available_quantity
    from public.inventory_stock_snapshot
    where product_variant_id='a8500000-0000-0000-0000-000000000001'
  $$,
  $$
    values (10::numeric,0::numeric,10::numeric)
  $$,
  'posting a receipt line increases on-hand and available stock from the ledger'
);

select results_eq(
  $$
    select count(*)::bigint
    from public.inventory_movements
    where goods_receipt_item_id='a9000000-0000-0000-0000-000000000001'
      and movement_type='GOODS_RECEIPT'
      and quantity_delta_base_units=10
      and created_by_user_id='a8100000-0000-0000-0000-000000000001'
      and reference='GOODS_RECEIPT:OPS022-GR'
  $$,
  array[1::bigint],
  'goods-receipt ledger entry is actor-attributed and receipt-referenced'
);

select results_eq(
  $$
    select count(*)::bigint
    from public.purchase_cost_history
    where product_variant_id='a8500000-0000-0000-0000-000000000001'
      and supplier_id='a8200000-0000-0000-0000-000000000001'
      and purchase_unit='carton'
      and units_per_purchase_unit=10
      and purchase_price_per_purchase_unit=1000
      and freight_cost_per_purchase_unit=300
      and purchase_cost_per_base_unit=100
      and landed_cost_per_base_unit=130
      and inventory_cost_basis_per_base_unit is null
      and currency_code='VND'
      and source_reference='GOODS_RECEIPT:OPS022-GR/PO:OPS022-PO'
  $$,
  array[1::bigint],
  'goods-receipt posting appends traceable purchase and landed cost without inventing an inventory-costing basis'
);

select * from finish();

rollback;
