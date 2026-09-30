begin;
create extension if not exists pgtap with schema extensions;
select plan(34);

select is(has_function_privilege('authenticated','public.create_sales_order_draft(text,uuid,date,text,text)','EXECUTE'),true,'create draft RPC available');
select is(has_function_privilege('authenticated','public.convert_accepted_quotation_to_sales_order(uuid,text,date,text)','EXECUTE'),true,'convert RPC available');
select is(has_function_privilege('authenticated','public.add_sales_order_item_priced(uuid,uuid,uuid,numeric,numeric,text,integer,text,text,date,text)','EXECUTE'),true,'priced line RPC available');
select is(has_function_privilege('authenticated','public.remove_sales_order_item(uuid)','EXECUTE'),true,'remove line RPC available');
select is(has_function_privilege('authenticated','public.set_sales_order_status(uuid,text)','EXECUTE'),true,'status RPC available');
select is(has_table_privilege('authenticated','public.sales_orders','INSERT'),false,'direct sales-order insert revoked');
select is(has_table_privilege('authenticated','public.sales_order_items','INSERT'),false,'direct sales-order-item insert revoked');
select results_eq($$select count(*)::bigint from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname='sales_order_totals' and c.reloptions @> array['security_invoker=true']$$,array[1::bigint],'sales-order totals use security_invoker');

insert into auth.users(id,email) values
('e0100000-0000-0000-0000-000000000001','ops-031-sales@example.test'),
('e0100000-0000-0000-0000-000000000002','ops-031-warehouse@example.test'),
('e0100000-0000-0000-0000-000000000003','ops-031-accounting@example.test');
insert into public.user_roles(user_id,role_id)
select x.user_id,r.id from (values
('e0100000-0000-0000-0000-000000000001'::uuid,'SALES'::text),
('e0100000-0000-0000-0000-000000000002'::uuid,'WAREHOUSE'::text),
('e0100000-0000-0000-0000-000000000003'::uuid,'ACCOUNTING'::text)
)x(user_id,role_code) join public.roles r on r.code=x.role_code;

insert into public.customers(id,customer_code,display_name) values('e0200000-0000-0000-0000-000000000001','OPS031-CUSTOMER','OPS-031 Customer');
insert into public.products(id,name,product_type) values('e0300000-0000-0000-0000-000000000001','OPS-031 Cup','CUP');
insert into public.product_variants(id,product_id,sku_code,variant_name,base_inventory_unit) values('e0400000-0000-0000-0000-000000000001','e0300000-0000-0000-0000-000000000001','OPS031-SKU','OPS-031 Variant','piece');
insert into public.product_packaging(id,product_variant_id,package_code,package_name,units_per_package,is_sale_default) values('e0500000-0000-0000-0000-000000000001','e0400000-0000-0000-0000-000000000001','CARTON','Carton',1000,true);
insert into public.pricing_rules(id,name,product_variant_id,print_mode,currency_code,priority,effective_from,is_active) values('e0600000-0000-0000-0000-000000000001','OPS-031 Fixed','e0400000-0000-0000-0000-000000000001','ANY','VND',10,current_date,true);
insert into public.price_tiers(id,pricing_rule_id,min_quantity_base_units,fixed_selling_price_per_base_unit) values('e0700000-0000-0000-0000-000000000001','e0600000-0000-0000-0000-000000000001',1,2.5);

set local role authenticated;
set local request.jwt.claim.sub='e0100000-0000-0000-0000-000000000001';
select lives_ok($$select public.create_quotation('QT-OPS031-001','e0200000-0000-0000-0000-000000000001',current_date+7,'VND','Convert me')$$,'create source quotation');
select lives_ok($$select public.add_quotation_item_priced((select id from public.quotations where quotation_number='QT-OPS031-001'),'e0400000-0000-0000-0000-000000000001','e0500000-0000-0000-0000-000000000001',2,100,'PLAIN',null,null,'ART-031',current_date+5,'Quoted line')$$,'price source line');
select lives_ok($$select public.set_quotation_status((select id from public.quotations where quotation_number='QT-OPS031-001'),'SENT')$$,'send source quotation');
select lives_ok($$select public.set_quotation_status((select id from public.quotations where quotation_number='QT-OPS031-001'),'ACCEPTED')$$,'accept source quotation');
select lives_ok($$select public.convert_accepted_quotation_to_sales_order((select id from public.quotations where quotation_number='QT-OPS031-001'),'SO-OPS031-CONVERTED',current_date+5,'Converted order')$$,'convert accepted quotation');
reset role;

select results_eq(
$$select so.order_status,so.customer_id,so.created_by_user_id,so.salesperson_user_id,q.status from public.sales_orders so join public.quotations q on q.id=so.source_quotation_id where so.order_number='SO-OPS031-CONVERTED'$$,
$select * from (values('DRAFT'::text,'e0200000-0000-0000-0000-000000000001'::uuid,'e0100000-0000-0000-0000-000000000001'::uuid,'e0100000-0000-0000-0000-000000000001'::uuid,'CONVERTED'::text)) as expected(order_status,customer_id,created_by_user_id,salesperson_user_id,status)$,
'conversion preserves source and actor');
select results_eq(
$$select soi.sale_unit,soi.sale_quantity,soi.units_per_sale_unit,soi.base_quantity,soi.unit_price_per_sale_unit,soi.discount_amount,soi.line_total,soi.print_mode,soi.artwork_reference,soi.pricing_rule_id,soi.price_tier_id from public.sales_order_items soi join public.sales_orders so on so.id=soi.sales_order_id where so.order_number='SO-OPS031-CONVERTED'$$,
$select * from (values('CARTON'::text,2::numeric,1000::numeric,2000::numeric,2500::numeric,100::numeric,4900::numeric,'PLAIN'::text,'ART-031'::text,'e0600000-0000-0000-0000-000000000001'::uuid,'e0700000-0000-0000-0000-000000000001'::uuid)) as expected(sale_unit,sale_quantity,units_per_sale_unit,base_quantity,unit_price_per_sale_unit,discount_amount,line_total,print_mode,artwork_reference,pricing_rule_id,price_tier_id)$,
'conversion copies line snapshots without re-entry');
select results_eq(
$$select sot.subtotal_amount,sot.discount_amount,sot.total_amount,sot.currency_code from public.sales_order_totals sot join public.sales_orders so on so.id=sot.sales_order_id where so.order_number='SO-OPS031-CONVERTED'$$,
$select * from (values(5000::numeric,100::numeric,4900::numeric,'VND'::text)) as expected(subtotal_amount,discount_amount,total_amount,currency_code)$,'converted totals derive correctly');

set local role authenticated;
set local request.jwt.claim.sub='e0100000-0000-0000-0000-000000000001';
select throws_ok($$select public.convert_accepted_quotation_to_sales_order((select id from public.quotations where quotation_number='QT-OPS031-001'),'SO-OPS031-DUP',null,null)$$,'P0001','Only ACCEPTED quotations may be converted to sales orders','converted quotation cannot convert twice');
select lives_ok($$select public.create_sales_order_draft('SO-OPS031-DIRECT','e0200000-0000-0000-0000-000000000001',current_date+7,'VND','Direct order')$$,'create direct draft');
select lives_ok($$select public.add_sales_order_item_priced((select id from public.sales_orders where order_number='SO-OPS031-DIRECT'),'e0400000-0000-0000-0000-000000000001',null,10,0,'PLAIN',null,null,null,current_date+7,'Direct line')$$,'add direct priced line');
select lives_ok($$select public.set_sales_order_status((select id from public.sales_orders where order_number='SO-OPS031-DIRECT'),'CONFIRMED')$$,'confirm draft with lines');
reset role;

select results_eq($$select count(*)::bigint from public.sales_orders where order_number='SO-OPS031-DIRECT' and order_status='CONFIRMED' and confirmed_at is not null and warehouse_status='NOT_RESERVED' and payment_status='UNPAID' and delivery_status='NOT_READY'$$,array[1::bigint],'confirmation preserves independent dimensions');

insert into public.inventory_movements(product_variant_id,movement_type,quantity_delta_base_units,reason) values('e0400000-0000-0000-0000-000000000001','ADJUSTMENT_IN',100,'OPS-031 fixture stock');

set local role authenticated;
set local request.jwt.claim.sub='e0100000-0000-0000-0000-000000000002';
select results_eq($$select count(*)::bigint from public.inventory_reservation_work_queue() where order_number='SO-OPS031-DIRECT' and outstanding_quantity=10 and available_quantity=100$$,array[1::bigint],'confirmed order enters reservation queue');
select lives_ok($$select public.reserve_sales_order_item((select sales_order_item_id from public.inventory_reservation_work_queue() where order_number='SO-OPS031-DIRECT'),10)$$,'warehouse reserves confirmed order');
reset role;

select is((select warehouse_status from public.sales_orders where order_number='SO-OPS031-DIRECT'),'RESERVED','reservation syncs warehouse status');

set local role authenticated;
set local request.jwt.claim.sub='e0100000-0000-0000-0000-000000000001';
select throws_ok($$select public.set_sales_order_status((select id from public.sales_orders where order_number='SO-OPS031-DIRECT'),'CANCELLED')$$,'P0001','Cannot cancel sales order after inventory or downstream operational activity exists','cannot cancel after inventory activity');
select throws_ok($$select public.add_sales_order_item_priced((select id from public.sales_orders where order_number='SO-OPS031-DIRECT'),'e0400000-0000-0000-0000-000000000001',null,1,0,'PLAIN',null,null,null,null,null)$$,'P0001','Sales-order items are editable only while the order is DRAFT','confirmed lines locked');
select throws_ok($$select public.set_sales_order_status((select id from public.sales_orders where order_number='SO-OPS031-DIRECT'),'COMPLETED')$$,'P0001','Completed sales order requires warehouse status ISSUED','completion gated by downstream dimensions');
select lives_ok($$select public.create_sales_order_draft('SO-OPS031-CANCEL','e0200000-0000-0000-0000-000000000001',null,'VND',null)$$,'create cancellable draft');
select lives_ok($$select public.set_sales_order_status((select id from public.sales_orders where order_number='SO-OPS031-CANCEL'),'CANCELLED')$$,'cancel clean draft');
reset role;

select results_eq($$select count(*)::bigint from public.sales_orders where order_number='SO-OPS031-CANCEL' and order_status='CANCELLED' and cancelled_at is not null$$,array[1::bigint],'cancellation timestamp recorded');

set local role authenticated;
set local request.jwt.claim.sub='e0100000-0000-0000-0000-000000000002';
select is((select count(*) from public.sales_orders),0::bigint,'WAREHOUSE cannot read sales-order financial table');
select is((select count(*) from public.sales_order_totals),0::bigint,'WAREHOUSE cannot bypass RLS through totals');
set local request.jwt.claim.sub='e0100000-0000-0000-0000-000000000003';
select cmp_ok((select count(*) from public.sales_orders),'>=',3::bigint,'ACCOUNTING can read sales orders');
select cmp_ok((select count(*) from public.sales_order_totals),'>=',3::bigint,'ACCOUNTING can read sales-order totals');
reset role;

select * from finish();
rollback;
