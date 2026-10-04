begin;
create extension if not exists pgtap with schema extensions;
select plan(29);

select results_eq(
  $$select count(*)::bigint from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname='sales_order_print_requirements' and c.reloptions @> array['security_invoker=true']$$,
  array[1::bigint],
  'print-requirements view uses security_invoker'
);
select is(has_table_privilege('authenticated','public.sales_order_print_requirements','SELECT'),true,'authenticated can select print requirements subject to underlying RLS');

insert into auth.users(id,email)
values ('f0100000-0000-0000-0000-000000000001','ops-032-sales@example.test');
insert into public.user_roles(user_id,role_id)
select 'f0100000-0000-0000-0000-000000000001'::uuid,r.id from public.roles r where r.code='SALES';

insert into public.customers(id,customer_code,display_name)
values ('f0200000-0000-0000-0000-000000000001','OPS032-CUSTOMER','OPS-032 Customer');
insert into public.products(id,name,product_type)
values ('f0300000-0000-0000-0000-000000000001','OPS-032 Cup','CUP');
insert into public.product_variants(id,product_id,sku_code,variant_name,base_inventory_unit)
values ('f0400000-0000-0000-0000-000000000001','f0300000-0000-0000-0000-000000000001','OPS032-SKU','OPS-032 Variant','piece');
insert into public.pricing_rules(id,name,product_variant_id,print_mode,currency_code,priority,effective_from,is_active)
values ('f0500000-0000-0000-0000-000000000001','OPS-032 Fixed','f0400000-0000-0000-0000-000000000001','ANY','VND',10,current_date,true);
insert into public.price_tiers(id,pricing_rule_id,min_quantity_base_units,fixed_selling_price_per_base_unit)
values ('f0600000-0000-0000-0000-000000000001','f0500000-0000-0000-0000-000000000001',1,2.5);

set local role authenticated;
set local request.jwt.claim.sub='f0100000-0000-0000-0000-000000000001';

select lives_ok(
  $$select public.create_sales_order_draft('SO-OPS032-PLAIN','f0200000-0000-0000-0000-000000000001',null,'VND','plain')$$,
  'create plain draft'
);
select lives_ok(
  $$select public.add_sales_order_item_priced((select id from public.sales_orders where order_number='SO-OPS032-PLAIN'),'f0400000-0000-0000-0000-000000000001',null,10,0,'PLAIN',null,null,null,null,'plain line')$$,
  'add plain line'
);
select lives_ok(
  $$select public.set_sales_order_status((select id from public.sales_orders where order_number='SO-OPS032-PLAIN'),'CONFIRMED')$$,
  'confirm plain order'
);
select is(
  (select print_status from public.sales_orders where order_number='SO-OPS032-PLAIN'),
  'NOT_REQUIRED',
  'plain-only confirmation canonicalizes print status to NOT_REQUIRED'
);
select is(
  (select count(*) from public.sales_order_print_requirements where order_number='SO-OPS032-PLAIN'),
  0::bigint,
  'plain-only order bypasses production requirement projection'
);

select lives_ok(
  $$select public.create_sales_order_draft('SO-OPS032-NODUE','f0200000-0000-0000-0000-000000000001',null,'VND','printed missing due')$$,
  'create printed draft without due date'
);
select lives_ok(
  $$select public.add_sales_order_item_priced((select id from public.sales_orders where order_number='SO-OPS032-NODUE'),'f0400000-0000-0000-0000-000000000001',null,10,0,'PRINTED',2,'two colors','ART-032',null,'printed line')$$,
  'add printed line without due date'
);
select throws_ok(
  $$select public.set_sales_order_status((select id from public.sales_orders where order_number='SO-OPS032-NODUE'),'CONFIRMED')$$,
  'P0001',
  'Printed sales-order items require a requested due date on the line or sales order',
  'printed order cannot confirm without a production due date'
);

select lives_ok(
  $$select public.create_sales_order_draft('SO-OPS032-PRINTED','f0200000-0000-0000-0000-000000000001',current_date+5,'VND','printed')$$,
  'create printed draft with due date'
);
select lives_ok(
  $$select public.add_sales_order_item_priced((select id from public.sales_orders where order_number='SO-OPS032-PRINTED'),'f0400000-0000-0000-0000-000000000001',null,20,0,'PRINTED',2,'two colors','ART-032',null,'printed line')$$,
  'add printed line using parent due date'
);
select lives_ok(
  $$select public.set_sales_order_status((select id from public.sales_orders where order_number='SO-OPS032-PRINTED'),'CONFIRMED')$$,
  'confirm printed order'
);
select is(
  (select print_status from public.sales_orders where order_number='SO-OPS032-PRINTED'),
  'WAITING',
  'printed confirmation canonicalizes print status to WAITING'
);
select results_eq(
  $$select quantity_base_units,print_color_count,due_date,print_status from public.sales_order_print_requirements where order_number='SO-OPS032-PRINTED'$$,
  $$select * from (values(20::numeric,2::integer,current_date+5,'WAITING'::text)) as expected(quantity_base_units,print_color_count,due_date,print_status)$$,
  'confirmed printed line enters production requirement projection with parent due-date fallback'
);
select is(
  (select count(*) from public.print_jobs where sales_order_id=(select id from public.sales_orders where order_number='SO-OPS032-PRINTED')),
  0::bigint,
  'OPS-032 confirmation does not materialize print jobs before OPS-040'
);

select lives_ok(
  $$select public.create_sales_order_draft('SO-OPS032-DRAFTPRINT','f0200000-0000-0000-0000-000000000001',current_date+3,'VND','draft printed')$$,
  'create DRAFT printed-order source'
);
select lives_ok(
  $$select public.add_sales_order_item_priced((select id from public.sales_orders where order_number='SO-OPS032-DRAFTPRINT'),'f0400000-0000-0000-0000-000000000001',null,5,0,'PRINTED',1,'one color',null,null,null)$$,
  'add DRAFT printed line'
);

reset role;

select throws_ok(
  $$insert into public.print_jobs(job_number,sales_order_id,sales_order_item_id,customer_id,product_variant_id,product_type_snapshot,quantity_base_units,print_color_count,print_specification,due_date)
    select 'PJ-OPS032-DRAFT',so.id,soi.id,so.customer_id,soi.product_variant_id,'CUP',soi.base_quantity,soi.print_color_count,soi.print_specification,current_date+3
    from public.sales_orders so join public.sales_order_items soi on soi.sales_order_id=so.id
    where so.order_number='SO-OPS032-DRAFTPRINT'$$,
  'P0001',
  'Print job source sales order must be CONFIRMED',
  'DRAFT printed order cannot generate a print job'
);

select throws_ok(
  $$insert into public.print_jobs(job_number,sales_order_id,sales_order_item_id,customer_id,product_variant_id,product_type_snapshot,quantity_base_units,print_color_count,print_specification,due_date)
    select 'PJ-OPS032-PLAIN',so.id,soi.id,so.customer_id,soi.product_variant_id,'CUP',soi.base_quantity,1,'invalid plain job',current_date+1
    from public.sales_orders so join public.sales_order_items soi on soi.sales_order_id=so.id
    where so.order_number='SO-OPS032-PLAIN'$$,
  'P0001',
  'Plain/no-print sales-order item cannot generate a print job',
  'plain/no-print item can never generate a print job'
);

select lives_ok(
  $$insert into public.print_jobs(job_number,sales_order_id,sales_order_item_id,customer_id,product_variant_id,product_type_snapshot,quantity_base_units,print_color_count,print_specification,artwork_reference,due_date)
    select 'PJ-OPS032-CONFIRMED',so.id,soi.id,so.customer_id,soi.product_variant_id,'CUP',soi.base_quantity,soi.print_color_count,soi.print_specification,soi.artwork_reference,current_date+5
    from public.sales_orders so join public.sales_order_items soi on soi.sales_order_id=so.id
    where so.order_number='SO-OPS032-PRINTED'$$,
  'confirmed printed source remains eligible for OPS-040 job materialization'
);

set local role authenticated;
set local request.jwt.claim.sub='f0100000-0000-0000-0000-000000000001';

select lives_ok(
  $$select public.create_sales_order_draft('SO-OPS032-MIXED','f0200000-0000-0000-0000-000000000001',current_date+4,'VND','mixed')$$,
  'create mixed draft'
);
select lives_ok(
  $$select public.add_sales_order_item_priced((select id from public.sales_orders where order_number='SO-OPS032-MIXED'),'f0400000-0000-0000-0000-000000000001',null,3,0,'PLAIN',null,null,null,null,'plain branch line')$$,
  'add mixed plain line'
);
select lives_ok(
  $$select public.add_sales_order_item_priced((select id from public.sales_orders where order_number='SO-OPS032-MIXED'),'f0400000-0000-0000-0000-000000000001',null,7,0,'PRINTED',1,'one color',null,null,'printed branch line')$$,
  'add mixed printed line'
);
select lives_ok(
  $$select public.set_sales_order_status((select id from public.sales_orders where order_number='SO-OPS032-MIXED'),'CONFIRMED')$$,
  'confirm mixed order'
);
select is(
  (select print_status from public.sales_orders where order_number='SO-OPS032-MIXED'),
  'WAITING',
  'mixed order enters print lifecycle because at least one line is PRINTED'
);
select is(
  (select count(*) from public.sales_order_print_requirements where order_number='SO-OPS032-MIXED'),
  1::bigint,
  'mixed order projects only its PRINTED line to production'
);
select results_eq(
  $$select quantity_base_units,print_color_count from public.sales_order_print_requirements where order_number='SO-OPS032-MIXED'$$,
  $$select * from (values(7::numeric,1::integer)) as expected(quantity_base_units,print_color_count)$$,
  'mixed order plain line is excluded from production requirements'
);
select is(
  (select count(*) from public.print_jobs where sales_order_id=(select id from public.sales_orders where order_number='SO-OPS032-MIXED')),
  0::bigint,
  'mixed confirmation also defers job materialization to OPS-040'
);

reset role;
select * from finish();
rollback;
