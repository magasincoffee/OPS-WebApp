begin;
create extension if not exists pgtap with schema extensions;
select plan(39);

select is(has_function_privilege('authenticated','public.delivery_work_queue()','EXECUTE'),true,'delivery work queue RPC available');
select is(has_function_privilege('authenticated','public.delivery_tracking(uuid)','EXECUTE'),true,'delivery tracking RPC available');
select is(has_function_privilege('authenticated','public.delivery_manifest(uuid)','EXECUTE'),true,'delivery manifest RPC available');
select is(has_function_privilege('authenticated','public.create_delivery(text,uuid,text,text,text,text,text,text,text)','EXECUTE'),true,'create delivery RPC available');
select is(has_function_privilege('authenticated','public.update_delivery_details(uuid,text,text,text,text,text,text,text)','EXECUTE'),true,'update delivery RPC available');
select is(has_function_privilege('authenticated','public.set_delivery_status(uuid,text,date)','EXECUTE'),true,'delivery status RPC available');
select results_eq(
  $$select count(*)::bigint from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname='delivery_order_status' and c.reloptions @> array['security_invoker=true']$$,
  array[1::bigint],
  'delivery order status view uses security_invoker'
);

insert into auth.users(id,email) values
('f1100000-0000-0000-0000-000000000001','ops-033-warehouse@example.test'),
('f1100000-0000-0000-0000-000000000002','ops-033-sales@example.test'),
('f1100000-0000-0000-0000-000000000003','ops-033-accounting@example.test');
insert into public.user_roles(user_id,role_id)
select x.user_id,r.id from (values
('f1100000-0000-0000-0000-000000000001'::uuid,'WAREHOUSE'::text),
('f1100000-0000-0000-0000-000000000002'::uuid,'SALES'::text),
('f1100000-0000-0000-0000-000000000003'::uuid,'ACCOUNTING'::text)
)x(user_id,role_code) join public.roles r on r.code=x.role_code;

insert into public.customers(id,customer_code,display_name)
values('f1200000-0000-0000-0000-000000000001','OPS033-CUSTOMER','OPS-033 Customer');
insert into public.products(id,name,product_type)
values('f1300000-0000-0000-0000-000000000001','OPS-033 Cup','CUP');
insert into public.product_variants(id,product_id,sku_code,variant_name,base_inventory_unit)
values('f1400000-0000-0000-0000-000000000001','f1300000-0000-0000-0000-000000000001','OPS033-SKU','OPS-033 Variant','piece');

insert into public.sales_orders(id,order_number,customer_id,order_status,print_status,warehouse_status,delivery_status,requested_due_date,created_by_user_id)
values('f1500000-0000-0000-0000-000000000001','SO-OPS033-PLAIN','f1200000-0000-0000-0000-000000000001','DRAFT','NOT_REQUIRED','NOT_RESERVED','NOT_READY',current_date+3,'f1100000-0000-0000-0000-000000000002');
insert into public.sales_order_items(id,sales_order_id,product_variant_id,sale_unit,sale_quantity,units_per_sale_unit,unit_price_per_sale_unit,print_mode)
values('f1600000-0000-0000-0000-000000000001','f1500000-0000-0000-0000-000000000001','f1400000-0000-0000-0000-000000000001','piece',10,1,10,'PLAIN');
update public.sales_orders set order_status='CONFIRMED' where id='f1500000-0000-0000-0000-000000000001';

set local role authenticated;
set local request.jwt.claim.sub='f1100000-0000-0000-0000-000000000001';

select results_eq(
  $$select order_number,customer_name,warehouse_status,print_status,ready_eligible,line_count from public.delivery_work_queue() where sales_order_id='f1500000-0000-0000-0000-000000000001'$$,
  $$select * from (values('SO-OPS033-PLAIN'::text,'OPS-033 Customer'::text,'NOT_RESERVED'::text,'NOT_REQUIRED'::text,false,1::integer)) as expected(order_number,customer_name,warehouse_status,print_status,ready_eligible,line_count)$$,
  'warehouse sees non-financial confirmed-order delivery work queue'
);

select lives_ok(
  $$select public.create_delivery('DLV-OPS033-001','f1500000-0000-0000-0000-000000000001','Nguyen Van A','0900000000','Can Tho','1 carton',null,null,'test delivery')$$,
  'warehouse creates NOT_READY full-order delivery'
);
select results_eq(
  $$select d.status,d.created_by_user_id,count(di.id)::bigint,sum(di.quantity_base_units) from public.deliveries d join public.delivery_items di on di.delivery_id=d.id where d.delivery_number='DLV-OPS033-001' group by d.status,d.created_by_user_id$$,
  $$select * from (values('NOT_READY'::text,'f1100000-0000-0000-0000-000000000001'::uuid,1::bigint,10::numeric)) as expected(status,created_by_user_id,count,sum)$$,
  'delivery creation binds actor and copies full order manifest'
);
select is((select delivery_status from public.sales_orders where id='f1500000-0000-0000-0000-000000000001'),'NOT_READY','order delivery status syncs on create');
select throws_ok(
  $$select public.set_delivery_status((select id from public.deliveries where delivery_number='DLV-OPS033-001'),'READY_TO_SHIP',null)$$,
  'P0001','Delivery readiness requires warehouse status ISSUED',
  'delivery cannot be ready before inventory is fully issued'
);

select public.adjust_inventory('f1400000-0000-0000-0000-000000000001',20,'OPS-033 fixture stock');
select lives_ok(
  $$select public.reserve_sales_order_item('f1600000-0000-0000-0000-000000000001',10)$$,
  'warehouse reserves delivery source order'
);
select lives_ok(
  $$select public.issue_inventory_reservation((select id from public.inventory_reservations where sales_order_item_id='f1600000-0000-0000-0000-000000000001'),10)$$,
  'warehouse issues delivery source order'
);
select is((select warehouse_status from public.sales_orders where id='f1500000-0000-0000-0000-000000000001'),'ISSUED','inventory issue makes order delivery-ready at warehouse dimension');

select lives_ok(
  $$select public.set_delivery_status((select id from public.deliveries where delivery_number='DLV-OPS033-001'),'READY_TO_SHIP',null)$$,
  'issued plain order becomes READY_TO_SHIP'
);
select is((select delivery_status from public.sales_orders where id='f1500000-0000-0000-0000-000000000001'),'READY_TO_SHIP','order delivery status syncs to READY_TO_SHIP');
select throws_ok(
  $$update public.delivery_items set quantity_base_units=9 where delivery_id=(select id from public.deliveries where delivery_number='DLV-OPS033-001')$$,
  'P0001','Delivery manifest is editable only while delivery is NOT_READY',
  'manifest is immutable after readiness'
);
select throws_ok(
  $$select public.set_delivery_status((select id from public.deliveries where delivery_number='DLV-OPS033-001'),'DISPATCHED',current_date)$$,
  'P0001','Dispatch requires a carrier/chành xe note or delivery reference',
  'dispatch requires transport traceability'
);
select lives_ok(
  $$select public.update_delivery_details((select id from public.deliveries where delivery_number='DLV-OPS033-001'),'Nguyen Van A','0900000000','Can Tho','1 carton','Chanh xe Mien Tay','REF-033','ready')$$,
  'warehouse can update operational delivery details before dispatch'
);
select lives_ok(
  $$select public.set_delivery_status((select id from public.deliveries where delivery_number='DLV-OPS033-001'),'DISPATCHED',current_date)$$,
  'ready delivery dispatches'
);
select is((select delivery_status from public.sales_orders where id='f1500000-0000-0000-0000-000000000001'),'DISPATCHED','order delivery status syncs to DISPATCHED');
select throws_ok(
  $$select public.update_delivery_details((select id from public.deliveries where delivery_number='DLV-OPS033-001'),'Changed',null,null,'changed','changed','changed',null)$$,
  'P0001','Delivery details are editable only before dispatch',
  'delivery details are locked after dispatch'
);
select lives_ok(
  $$select public.set_delivery_status((select id from public.deliveries where delivery_number='DLV-OPS033-001'),'COMPLETED',null)$$,
  'dispatched delivery completes'
);
select results_eq(
  $$select d.status,(d.completed_at is not null),so.delivery_status from public.deliveries d join public.sales_orders so on so.id=d.sales_order_id where d.delivery_number='DLV-OPS033-001'$$,
  $$select * from (values('COMPLETED'::text,true,'COMPLETED'::text)) as expected(status,has_completed_at,delivery_status)$$,
  'delivery completion records timestamp and synchronizes order'
);
select throws_ok(
  $$select public.create_delivery('DLV-OPS033-DUP','f1500000-0000-0000-0000-000000000001','Duplicate',null,null,'1 carton','carrier','ref',null)$$,
  'P0001','Sales order already has an active delivery',
  'completed active delivery prevents duplicate V1 delivery'
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub='f1100000-0000-0000-0000-000000000002';
select cmp_ok((select count(*) from public.deliveries where delivery_number='DLV-OPS033-001'),'>=',1::bigint,'SALES can read delivery tracking');
select throws_ok(
  $$select public.create_delivery('DLV-OPS033-SALES','f1500000-0000-0000-0000-000000000001','Sales',null,null,null,null,null,null)$$,
  '42501','Create delivery requires OWNER_ADMIN or WAREHOUSE role',
  'SALES cannot create delivery'
);
reset role;

insert into public.sales_orders(id,order_number,customer_id,order_status,print_status,warehouse_status,delivery_status,requested_due_date,created_by_user_id)
values('f1500000-0000-0000-0000-000000000002','SO-OPS033-PRINTED','f1200000-0000-0000-0000-000000000001','DRAFT','NOT_REQUIRED','NOT_RESERVED','NOT_READY',current_date+4,'f1100000-0000-0000-0000-000000000002');
insert into public.sales_order_items(id,sales_order_id,product_variant_id,sale_unit,sale_quantity,units_per_sale_unit,unit_price_per_sale_unit,print_mode,print_color_count,requested_due_date)
values('f1600000-0000-0000-0000-000000000002','f1500000-0000-0000-0000-000000000002','f1400000-0000-0000-0000-000000000001','piece',5,1,10,'PRINTED',1,current_date+4);
update public.sales_orders set order_status='CONFIRMED' where id='f1500000-0000-0000-0000-000000000002';

set local role authenticated;
set local request.jwt.claim.sub='f1100000-0000-0000-0000-000000000001';
select lives_ok($$select public.reserve_sales_order_item('f1600000-0000-0000-0000-000000000002',5)$$,'reserve printed delivery source');
select lives_ok($$select public.issue_inventory_reservation((select id from public.inventory_reservations where sales_order_item_id='f1600000-0000-0000-0000-000000000002'),5)$$,'issue printed delivery source');
select lives_ok(
  $$select public.create_delivery('DLV-OPS033-PRINTED','f1500000-0000-0000-0000-000000000002','Printed Customer',null,'Can Tho','1 carton','carrier','REF-PRINT',null)$$,
  'create printed-order delivery'
);
select is((select print_status from public.sales_orders where id='f1500000-0000-0000-0000-000000000002'),'WAITING','printed source remains WAITING before production completion');
select throws_ok(
  $$select public.set_delivery_status((select id from public.deliveries where delivery_number='DLV-OPS033-PRINTED'),'READY_TO_SHIP',null)$$,
  'P0001','Delivery readiness requires print status NOT_REQUIRED or COMPLETED',
  'printed order cannot become ready before print completion'
);

reset role;

insert into public.sales_orders(id,order_number,customer_id,order_status,print_status,warehouse_status,delivery_status,requested_due_date,created_by_user_id)
values('f1500000-0000-0000-0000-000000000003','SO-OPS033-CANCEL','f1200000-0000-0000-0000-000000000001','DRAFT','NOT_REQUIRED','NOT_RESERVED','NOT_READY',current_date+5,'f1100000-0000-0000-0000-000000000002');
insert into public.sales_order_items(id,sales_order_id,product_variant_id,sale_unit,sale_quantity,units_per_sale_unit,unit_price_per_sale_unit,print_mode)
values('f1600000-0000-0000-0000-000000000003','f1500000-0000-0000-0000-000000000003','f1400000-0000-0000-0000-000000000001','piece',1,1,10,'PLAIN');
update public.sales_orders set order_status='CONFIRMED' where id='f1500000-0000-0000-0000-000000000003';

set local role authenticated;
set local request.jwt.claim.sub='f1100000-0000-0000-0000-000000000001';

select lives_ok(
  $select public.create_delivery('DLV-OPS033-CANCEL','f1500000-0000-0000-0000-000000000003','Cancel Customer',null,null,null,null,null,null)$,
  'create cancellable delivery'
);
select lives_ok(
  $$select public.set_delivery_status((select id from public.deliveries where delivery_number='DLV-OPS033-CANCEL'),'CANCELLED',null)$$,
  'NOT_READY delivery may be cancelled'
);
select is((select delivery_status from public.sales_orders where order_number='SO-OPS033-CANCEL'),'NOT_READY','cancellation resets order delivery status');
select lives_ok(
  $select public.create_delivery('DLV-OPS033-REPLACEMENT','f1500000-0000-0000-0000-000000000003','Replacement',null,null,null,null,null,null)$,
  'cancelled delivery permits replacement delivery'
);
select results_eq(
  $select delivery_number,order_number,status from public.delivery_tracking((select id from public.deliveries where delivery_number='DLV-OPS033-REPLACEMENT'))$,
  $select * from (values('DLV-OPS033-REPLACEMENT'::text,'SO-OPS033-CANCEL'::text,'NOT_READY'::text)) as expected(delivery_number,order_number,status)$,
  'delivery tracking exposes operational linkage without financial fields'
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub='f1100000-0000-0000-0000-000000000003';
select is((select count(*) from public.deliveries),0::bigint,'ACCOUNTING has no direct delivery-table access');
reset role;

select * from finish();
rollback;
