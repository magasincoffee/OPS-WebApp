begin;

create extension if not exists pgtap with schema extensions;

select plan(28);

select is(has_function_privilege('authenticated','public.create_stocktake(text,text)','EXECUTE'),true,'create_stocktake RPC is executable by authenticated subject to role checks');
select is(has_function_privilege('authenticated','public.set_stocktake_count(uuid,numeric,text)','EXECUTE'),true,'set_stocktake_count RPC is executable by authenticated subject to role checks');
select is(has_function_privilege('authenticated','public.finalize_stocktake(uuid)','EXECUTE'),true,'finalize_stocktake RPC is executable by authenticated subject to role checks');
select is(has_function_privilege('authenticated','public.post_stocktake(uuid)','EXECUTE'),true,'post_stocktake RPC is executable by authenticated subject to role checks');
select is(has_function_privilege('authenticated','public.adjust_inventory(uuid,numeric,text)','EXECUTE'),true,'adjust_inventory RPC is executable by authenticated subject to role checks');
select is(has_table_privilege('authenticated','public.stocktakes','INSERT'),false,'authenticated cannot bypass stocktake workflow with direct header inserts');
select is(has_table_privilege('authenticated','public.stocktake_items','UPDATE'),false,'authenticated cannot bypass stocktake workflow with direct item updates');
select is(has_table_privilege('authenticated','public.inventory_low_stock','SELECT'),true,'authenticated can read low-stock view');

insert into auth.users (id,email)
values ('c8100000-0000-0000-0000-000000000001','ops-024-warehouse@example.test');

insert into public.user_roles (user_id,role_id)
select 'c8100000-0000-0000-0000-000000000001'::uuid,r.id
from public.roles r where r.code='WAREHOUSE';

insert into public.products (id,name)
values ('c8200000-0000-0000-0000-000000000001','OPS-024 Product');

insert into public.product_variants (
  id,product_id,sku_code,variant_name,base_inventory_unit,minimum_stock_quantity
)
values (
  'c8300000-0000-0000-0000-000000000001',
  'c8200000-0000-0000-0000-000000000001',
  'OPS024-SKU','OPS-024 Variant','piece',10
);

insert into public.inventory_movements (
  product_variant_id,movement_type,quantity_delta_base_units,reason
)
values (
  'c8300000-0000-0000-0000-000000000001',
  'ADJUSTMENT_IN',12,'OPS-024 opening fixture stock'
);

set local role authenticated;
set local request.jwt.claim.sub='c8100000-0000-0000-0000-000000000001';

select lives_ok($$select public.create_stocktake('OPS024-ST-001','Cycle count')$$,'warehouse can create stocktake');

reset role;

select results_eq(
  $$
    select sti.system_on_hand_quantity,sti.counted_on_hand_quantity
    from public.stocktake_items sti
    join public.stocktakes st on st.id=sti.stocktake_id
    where st.stocktake_number='OPS024-ST-001'
      and sti.product_variant_id='c8300000-0000-0000-0000-000000000001'
  $$,
  $$values (12::numeric,null::numeric)$$,
  'stocktake snapshots ledger-derived on-hand'
);

select results_eq(
  $$
    select count(*)::bigint from public.stocktakes
    where stocktake_number='OPS024-ST-001'
      and status='DRAFT'
      and created_by_user_id='c8100000-0000-0000-0000-000000000001'
  $$,
  array[1::bigint],
  'stocktake creation preserves actor'
);

set local role authenticated;
set local request.jwt.claim.sub='c8100000-0000-0000-0000-000000000001';

select lives_ok(
  $$select public.set_stocktake_count(
    (select sti.id from public.stocktake_items sti join public.stocktakes st on st.id=sti.stocktake_id
     where st.stocktake_number='OPS024-ST-001' and sti.product_variant_id='c8300000-0000-0000-0000-000000000001'),
    8,'Physical count')$$,
  'warehouse can capture count'
);

select lives_ok(
  $$select public.finalize_stocktake((select id from public.stocktakes where stocktake_number='OPS024-ST-001'))$$,
  'fully counted stocktake becomes COUNTED'
);

select lives_ok(
  $$select public.post_stocktake((select id from public.stocktakes where stocktake_number='OPS024-ST-001'))$$,
  'COUNTED stocktake posts variance'
);

reset role;

select results_eq(
  $$select on_hand_quantity,reserved_quantity,available_quantity from public.inventory_stock_snapshot
    where product_variant_id='c8300000-0000-0000-0000-000000000001'$$,
  $$values (8::numeric,0::numeric,8::numeric)$$,
  'stocktake reconciles ledger to physical count'
);

select results_eq(
  $$
    select count(*)::bigint
    from public.inventory_movements im
    join public.stocktake_items sti on sti.id=im.stocktake_item_id
    join public.stocktakes st on st.id=sti.stocktake_id
    where st.stocktake_number='OPS024-ST-001'
      and im.movement_type='STOCKTAKE_ADJUSTMENT'
      and im.quantity_delta_base_units=-4
      and im.created_by_user_id='c8100000-0000-0000-0000-000000000001'
      and im.reference='STOCKTAKE:OPS024-ST-001'
  $$,
  array[1::bigint],
  'stocktake variance posts once with actor and source'
);

select results_eq(
  $$
    select count(*)::bigint from public.stocktakes
    where stocktake_number='OPS024-ST-001' and status='POSTED'
      and counted_at is not null and posted_at is not null
      and posted_by_user_id='c8100000-0000-0000-0000-000000000001'
  $$,
  array[1::bigint],
  'posted stocktake records lifecycle and actor'
);

set local role authenticated;
set local request.jwt.claim.sub='c8100000-0000-0000-0000-000000000001';

select throws_ok(
  $$select public.post_stocktake((select id from public.stocktakes where stocktake_number='OPS024-ST-001'))$$,
  'P0001','Only COUNTED stocktakes may be posted','stocktake cannot post twice'
);

select lives_ok(
  $$select public.adjust_inventory('c8300000-0000-0000-0000-000000000001',3,'Found sealed carton during recount')$$,
  'positive manual adjustment works'
);
select lives_ok(
  $$select public.adjust_inventory('c8300000-0000-0000-0000-000000000001',-2,'Damaged pieces removed')$$,
  'negative manual adjustment works'
);

reset role;

select results_eq(
  $$select on_hand_quantity,reserved_quantity,available_quantity from public.inventory_stock_snapshot
    where product_variant_id='c8300000-0000-0000-0000-000000000001'$$,
  $$values (9::numeric,0::numeric,9::numeric)$$,
  'manual adjustments remain ledger-derived'
);

select results_eq(
  $$select available_quantity,minimum_stock_quantity,shortage_quantity
    from public.inventory_low_stock where product_variant_id='c8300000-0000-0000-0000-000000000001'$$,
  $$values (9::numeric,10::numeric,1::numeric)$$,
  'low-stock uses available quantity versus minimum'
);

set local role authenticated;
set local request.jwt.claim.sub='c8100000-0000-0000-0000-000000000001';

select throws_ok(
  $$select public.adjust_inventory('c8300000-0000-0000-0000-000000000001',1,'   ')$$,
  'P0001','Adjustment reason is required','manual adjustment requires reason'
);

select lives_ok($$select public.create_stocktake('OPS024-ST-STALE','Stale snapshot guard')$$,'second stocktake can be created');
select lives_ok(
  $$select public.adjust_inventory('c8300000-0000-0000-0000-000000000001',1,'Movement after stocktake snapshot')$$,
  'inventory can change after snapshot'
);
select lives_ok(
  $$select public.set_stocktake_count(
    (select sti.id from public.stocktake_items sti join public.stocktakes st on st.id=sti.stocktake_id
     where st.stocktake_number='OPS024-ST-STALE' and sti.product_variant_id='c8300000-0000-0000-0000-000000000001'),
    10,null)$$,
  'stale stocktake can capture count'
);
select lives_ok(
  $$select public.finalize_stocktake((select id from public.stocktakes where stocktake_number='OPS024-ST-STALE'))$$,
  'stale stocktake reaches COUNTED'
);
select throws_like(
  $$select public.post_stocktake((select id from public.stocktakes where stocktake_number='OPS024-ST-STALE'))$$,
  'Inventory changed after stocktake snapshot%',
  'stale stocktake is blocked at posting'
);

reset role;

select * from finish();
rollback;
