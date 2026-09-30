begin;

create extension if not exists pgtap with schema extensions;

select plan(23);

select is(
  has_function_privilege('authenticated','public.inventory_reservation_work_queue()','EXECUTE'),
  true,
  'authenticated can execute the bounded non-financial reservation queue RPC'
);

select is(
  has_function_privilege('authenticated','public.reserve_sales_order_item(uuid,numeric)','EXECUTE'),
  true,
  'authenticated can execute reserve RPC subject to role checks'
);

select is(
  has_function_privilege('authenticated','public.release_inventory_reservation(uuid,numeric)','EXECUTE'),
  true,
  'authenticated can execute release RPC subject to role checks'
);

select is(
  has_function_privilege('authenticated','public.issue_inventory_reservation(uuid,numeric)','EXECUTE'),
  true,
  'authenticated can execute issue RPC subject to role checks'
);

select is(
  has_table_privilege('authenticated','public.inventory_reservations','INSERT'),
  false,
  'authenticated cannot forge reservation rows directly'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_indexes
    where schemaname='public'
      and tablename='inventory_reservations'
      and indexname='inventory_reservations_one_per_sales_order_item'
      and indexdef like '%UNIQUE%'
  $$,
  array[1::bigint],
  'one reservation record per sales-order item is enforced'
);

insert into auth.users (id,email)
values (
  'b8100000-0000-0000-0000-000000000001',
  'ops-023-warehouse@example.test'
);

insert into public.user_roles (user_id,role_id)
select
  'b8100000-0000-0000-0000-000000000001'::uuid,
  r.id
from public.roles r
where r.code='WAREHOUSE';

insert into public.customers (id,customer_code,display_name)
values (
  'b8200000-0000-0000-0000-000000000001',
  'OPS023-CUSTOMER',
  'OPS-023 Customer'
);

insert into public.products (id,name)
values (
  'b8300000-0000-0000-0000-000000000001',
  'OPS-023 Product'
);

insert into public.product_variants (
  id,product_id,sku_code,variant_name,base_inventory_unit
)
values (
  'b8400000-0000-0000-0000-000000000001',
  'b8300000-0000-0000-0000-000000000001',
  'OPS023-SKU',
  'OPS-023 Variant',
  'piece'
);

insert into public.sales_orders (
  id,order_number,customer_id,order_status,warehouse_status
)
values (
  'b8500000-0000-0000-0000-000000000001',
  'OPS023-SO',
  'b8200000-0000-0000-0000-000000000001',
  'CONFIRMED',
  'NOT_RESERVED'
);

insert into public.sales_order_items (
  id,sales_order_id,product_variant_id,sale_unit,sale_quantity,
  units_per_sale_unit,unit_price_per_sale_unit,print_mode
)
values (
  'b8600000-0000-0000-0000-000000000001',
  'b8500000-0000-0000-0000-000000000001',
  'b8400000-0000-0000-0000-000000000001',
  'piece',
  10,
  1,
  100,
  'PLAIN'
);

insert into public.inventory_movements (
  product_variant_id,movement_type,quantity_delta_base_units,reason
)
values (
  'b8400000-0000-0000-0000-000000000001',
  'ADJUSTMENT_IN',
  20,
  'OPS-023 fixture opening stock'
);

set local role authenticated;
set local request.jwt.claim.sub='b8100000-0000-0000-0000-000000000001';

select results_eq(
  $$
    select count(*)::bigint
    from public.inventory_reservation_work_queue()
    where sales_order_item_id='b8600000-0000-0000-0000-000000000001'
      and base_quantity=10
      and issued_quantity=0
      and reserved_balance_quantity=0
      and outstanding_quantity=10
      and available_quantity=20
  $$,
  array[1::bigint],
  'warehouse queue exposes operational quantity state without direct sales-table access'
);

select lives_ok(
  $$ select public.reserve_sales_order_item(
    'b8600000-0000-0000-0000-000000000001'::uuid,
    6::numeric
  ) $$,
  'warehouse can partially reserve a confirmed sales-order item'
);

reset role;

select results_eq(
  $$
    select on_hand_quantity,reserved_quantity,available_quantity
    from public.inventory_stock_snapshot
    where product_variant_id='b8400000-0000-0000-0000-000000000001'
  $$,
  $$ values (20::numeric,6::numeric,14::numeric) $$,
  'partial reservation reduces available stock without changing on-hand stock'
);

select results_eq(
  $$
    select count(*)::bigint
    from public.inventory_reservations
    where sales_order_item_id='b8600000-0000-0000-0000-000000000001'
      and product_variant_id='b8400000-0000-0000-0000-000000000001'
      and requested_base_quantity=10
      and created_by_user_id='b8100000-0000-0000-0000-000000000001'
  $$,
  array[1::bigint],
  'reservation source and actor are database-controlled'
);

select is(
  (select warehouse_status from public.sales_orders where id='b8500000-0000-0000-0000-000000000001'),
  'NOT_RESERVED',
  'partially allocated order remains NOT_RESERVED'
);

set local role authenticated;
set local request.jwt.claim.sub='b8100000-0000-0000-0000-000000000001';

select lives_ok(
  $$ select public.reserve_sales_order_item(
    'b8600000-0000-0000-0000-000000000001'::uuid,
    4::numeric
  ) $$,
  'warehouse can reserve the remaining order quantity'
);

reset role;

select is(
  (select warehouse_status from public.sales_orders where id='b8500000-0000-0000-0000-000000000001'),
  'RESERVED',
  'fully allocated order synchronizes warehouse status to RESERVED'
);

select results_eq(
  $$
    select on_hand_quantity,reserved_quantity,available_quantity
    from public.inventory_stock_snapshot
    where product_variant_id='b8400000-0000-0000-0000-000000000001'
  $$,
  $$ values (20::numeric,10::numeric,10::numeric) $$,
  'full reservation reconciles on-hand reserved and available quantities'
);

set local role authenticated;
set local request.jwt.claim.sub='b8100000-0000-0000-0000-000000000001';

select lives_ok(
  $$
    select public.release_inventory_reservation(
      (
        select inventory_reservation_id
        from public.inventory_reservation_work_queue()
        where sales_order_item_id='b8600000-0000-0000-0000-000000000001'
      ),
      3::numeric
    )
  $$,
  'warehouse can partially release reserved inventory'
);

reset role;

select results_eq(
  $$
    select on_hand_quantity,reserved_quantity,available_quantity
    from public.inventory_stock_snapshot
    where product_variant_id='b8400000-0000-0000-0000-000000000001'
  $$,
  $$ values (20::numeric,7::numeric,13::numeric) $$,
  'release restores available stock without changing on-hand stock'
);

set local role authenticated;
set local request.jwt.claim.sub='b8100000-0000-0000-0000-000000000001';

select lives_ok(
  $$ select public.reserve_sales_order_item(
    'b8600000-0000-0000-0000-000000000001'::uuid,
    3::numeric
  ) $$,
  'released quantity can be reserved again'
);

select lives_ok(
  $$
    select public.issue_inventory_reservation(
      (
        select inventory_reservation_id
        from public.inventory_reservation_work_queue()
        where sales_order_item_id='b8600000-0000-0000-0000-000000000001'
      ),
      10::numeric
    )
  $$,
  'warehouse can issue the fully reserved sales-order item'
);

reset role;

select results_eq(
  $$
    select on_hand_quantity,reserved_quantity,available_quantity
    from public.inventory_stock_snapshot
    where product_variant_id='b8400000-0000-0000-0000-000000000001'
  $$,
  $$ values (10::numeric,0::numeric,10::numeric) $$,
  'sales issue decreases on-hand and reserved equally while preserving available reconciliation'
);

select is(
  (select warehouse_status from public.sales_orders where id='b8500000-0000-0000-0000-000000000001'),
  'ISSUED',
  'fully issued order synchronizes warehouse status to ISSUED'
);

set local role authenticated;
set local request.jwt.claim.sub='b8100000-0000-0000-0000-000000000001';

select throws_ok(
  $$ select public.reserve_sales_order_item(
    'b8600000-0000-0000-0000-000000000001'::uuid,
    1::numeric
  ) $$,
  'P0001',
  'Reservation quantity exceeds the outstanding sales-order quantity',
  'fulfilled order line cannot be over-reserved'
);

reset role;

select throws_ok(
  $$
    update public.sales_order_items
    set sale_quantity=11
    where id='b8600000-0000-0000-0000-000000000001'
  $$,
  'P0001',
  'Cannot change SKU or quantity fields after inventory activity exists',
  'inventory-linked sales-order quantity fields are immutable'
);

select results_eq(
  $$
    select count(*)::bigint
    from public.inventory_movements
    where sales_order_item_id='b8600000-0000-0000-0000-000000000001'
      and created_by_user_id='b8100000-0000-0000-0000-000000000001'
      and movement_type in ('SALES_RESERVATION','RESERVATION_RELEASE','SALES_ISSUE')
  $$,
  array[5::bigint],
  'all reservation workflow ledger movements preserve authenticated actor attribution'
);

select * from finish();

rollback;
