begin;
create extension if not exists pgtap with schema extensions;
select plan(35);

select is(has_function_privilege('authenticated','public.print_job_requirement_queue()','EXECUTE'),true,'requirement queue RPC available');
select is(has_function_privilege('authenticated','public.print_job_tracking(uuid)','EXECUTE'),true,'tracking RPC available');
select is(has_function_privilege('authenticated','public.create_print_job_from_requirement(text,uuid,text)','EXECUTE'),true,'materialization RPC available');
select is(has_function_privilege('authenticated','public.set_print_job_status(uuid,text,text)','EXECUTE'),true,'status RPC available');

insert into auth.users(id,email) values
('f2100000-0000-0000-0000-000000000001','ops-040-owner@example.test'),
('f2100000-0000-0000-0000-000000000002','ops-040-printer@example.test');
insert into public.user_roles(user_id,role_id)
select x.user_id,r.id from (values
('f2100000-0000-0000-0000-000000000001'::uuid,'OWNER_ADMIN'::text),
('f2100000-0000-0000-0000-000000000002'::uuid,'PRINTER_PRODUCTION'::text)
)x(user_id,role_code) join public.roles r on r.code=x.role_code;

insert into public.customers(id,customer_code,display_name)
values('f2200000-0000-0000-0000-000000000001','OPS040-CUSTOMER','OPS-040 Customer');
insert into public.products(id,name,product_type)
values('f2300000-0000-0000-0000-000000000001','OPS-040 Printed Cup','CUP');
insert into public.product_variants(id,product_id,sku_code,variant_name,base_inventory_unit)
values('f2400000-0000-0000-0000-000000000001','f2300000-0000-0000-0000-000000000001','OPS040-SKU','OPS-040 Variant','piece');

insert into public.sales_orders(
 id,order_number,customer_id,order_status,print_status,warehouse_status,delivery_status,payment_status,requested_due_date,created_by_user_id
) values(
 'f2500000-0000-0000-0000-000000000001','SO-OPS040-001','f2200000-0000-0000-0000-000000000001',
 'DRAFT','NOT_REQUIRED','NOT_RESERVED','NOT_READY','UNPAID',current_date+5,'f2100000-0000-0000-0000-000000000001'
);
insert into public.sales_order_items(
 id,sales_order_id,product_variant_id,sale_unit,sale_quantity,units_per_sale_unit,unit_price_per_sale_unit,
 print_mode,print_color_count,print_specification,artwork_reference,requested_due_date
) values
('f2600000-0000-0000-0000-000000000001','f2500000-0000-0000-0000-000000000001','f2400000-0000-0000-0000-000000000001','piece',10,1,10,'PRINTED',2,'Two colors - front','ART-040-A',current_date+3),
('f2600000-0000-0000-0000-000000000002','f2500000-0000-0000-0000-000000000001','f2400000-0000-0000-0000-000000000001','piece',20,1,10,'PRINTED',1,'One color - back','ART-040-B',null),
('f2600000-0000-0000-0000-000000000003','f2500000-0000-0000-0000-000000000001','f2400000-0000-0000-0000-000000000001','piece',5,1,10,'PLAIN',null,null,null,null);
update public.sales_orders set order_status='CONFIRMED' where id='f2500000-0000-0000-0000-000000000001';

set local role authenticated;
set local request.jwt.claim.sub='f2100000-0000-0000-0000-000000000001';

select is((select count(*) from public.print_job_requirement_queue()),2::bigint,'only PRINTED lines enter requirement queue');
select results_eq(
 $$select sales_order_item_id,quantity_base_units,print_color_count,artwork_reference,due_date
   from public.print_job_requirement_queue() order by sales_order_item_id$$,
 $$select * from (values
   ('f2600000-0000-0000-0000-000000000001'::uuid,10::numeric,2::integer,'ART-040-A'::text,current_date+3),
   ('f2600000-0000-0000-0000-000000000002'::uuid,20::numeric,1::integer,'ART-040-B'::text,current_date+5)
 ) as expected(sales_order_item_id,quantity_base_units,print_color_count,artwork_reference,due_date)
 order by sales_order_item_id$$,
 'requirement queue preserves snapshots and due-date fallback'
);
select lives_ok(
 $$select public.create_print_job_from_requirement('PJ-OPS040-001','f2600000-0000-0000-0000-000000000001','first job')$$,
 'materialize first print job'
);
select results_eq(
 $$select job_number,status,qc_state,quantity_base_units,print_color_count,print_specification,artwork_reference,due_date
   from public.print_job_tracking((select id from public.print_jobs where job_number='PJ-OPS040-001'))$$,
 $$select * from (values('PJ-OPS040-001'::text,'WAITING'::text,'PENDING'::text,10::numeric,2::integer,
   'Two colors - front'::text,'ART-040-A'::text,current_date+3))
   as expected(job_number,status,qc_state,quantity_base_units,print_color_count,print_specification,artwork_reference,due_date)$$,
 'job snapshots source requirement'
);
select is((select print_status from public.sales_orders where id='f2500000-0000-0000-0000-000000000001'),'WAITING','partial coverage keeps WAITING');
select throws_ok(
 $$select public.create_print_job_from_requirement('PJ-OPS040-DUP','f2600000-0000-0000-0000-000000000001',null)$$,
 'P0001','Sales-order item already has an active print job','one active job per printed line'
);
select lives_ok(
 $$select public.create_print_job_from_requirement('PJ-OPS040-002','f2600000-0000-0000-0000-000000000002','second job')$$,
 'materialize second print job'
);
select is((select count(*) from public.print_job_requirement_queue()),0::bigint,'all requirements covered');
select is((select count(*) from public.print_job_tracking(null)),2::bigint,'owner tracking sees both jobs');

select lives_ok(
 $$select public.set_print_job_status((select id from public.print_jobs where job_number='PJ-OPS040-001'),'ACCEPTED','accepted')$$,
 'WAITING to ACCEPTED'
);
select is((select print_status from public.sales_orders where id='f2500000-0000-0000-0000-000000000001'),'IN_PROGRESS','aggregate moves IN_PROGRESS');
select lives_ok(
 $$select public.set_print_job_status((select id from public.print_jobs where job_number='PJ-OPS040-001'),'IN_PROGRESS','started')$$,
 'ACCEPTED to IN_PROGRESS'
);
select results_eq(
 $$select status,(accepted_at is not null),(started_at is not null)
   from public.print_job_tracking((select id from public.print_jobs where job_number='PJ-OPS040-001'))$$,
 $$select * from (values('IN_PROGRESS'::text,true,true)) as expected(status,has_accepted_at,has_started_at)$$,
 'execution timestamps are workflow-managed'
);
select lives_ok(
 $$select public.set_print_job_status((select id from public.print_jobs where job_number='PJ-OPS040-001'),'WAITING_QC','production finished')$$,
 'IN_PROGRESS to WAITING_QC'
);
select is((select print_status from public.sales_orders where id='f2500000-0000-0000-0000-000000000001'),'IN_PROGRESS','another WAITING job keeps aggregate IN_PROGRESS');
select lives_ok(
 $$select public.set_print_job_status((select id from public.print_jobs where job_number='PJ-OPS040-002'),'ACCEPTED','accepted second')$$,
 'second WAITING to ACCEPTED'
);
select lives_ok(
 $$select public.set_print_job_status((select id from public.print_jobs where job_number='PJ-OPS040-002'),'IN_PROGRESS','started second')$$,
 'second ACCEPTED to IN_PROGRESS'
);
select lives_ok(
 $$select public.set_print_job_status((select id from public.print_jobs where job_number='PJ-OPS040-002'),'WAITING_QC','ready for QC')$$,
 'second IN_PROGRESS to WAITING_QC'
);
select is((select print_status from public.sales_orders where id='f2500000-0000-0000-0000-000000000001'),'WAITING_QC','all jobs at QC moves aggregate WAITING_QC');
select throws_ok(
 $$select public.set_print_job_status((select id from public.print_jobs where job_number='PJ-OPS040-001'),'COMPLETED','not yet')$$,
 'P0001','Print-job completion is reserved for OPS-042 QC workflow','OPS-040 cannot bypass completion boundary'
);
select throws_ok(
 $$update public.print_jobs set qc_state='PASSED',qc_completed_at=timezone('utc',now()) where job_number='PJ-OPS040-001'$$,
 'P0001','QC and completion fields are reserved for OPS-042','direct QC mutation blocked'
);
select throws_ok(
 $$update public.print_jobs set assignee_user_id='f2100000-0000-0000-0000-000000000002' where job_number='PJ-OPS040-001'$$,
 'P0001','Print-job assignment is reserved for OPS-041','direct assignment blocked'
);
select is(
 (select count(*) from public.print_job_events where print_job_id=(select id from public.print_jobs where job_number='PJ-OPS040-001')),
 4::bigint,'event stream records creation plus transitions'
);
select is(
 (select count(*) from public.print_job_events where print_job_id=(select id from public.print_jobs where job_number='PJ-OPS040-001')
   and actor_user_id='f2100000-0000-0000-0000-000000000001'),
 4::bigint,'events capture actor'
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub='f2100000-0000-0000-0000-000000000002';
select is((select count(*) from public.print_job_tracking(null)),0::bigint,'printer sees no job before OPS-041 assignment');
select throws_ok(
 $$select public.set_print_job_status('f2700000-0000-0000-0000-000000000099'::uuid,'ACCEPTED',null)$$,
 'P0001','Print job f2700000-0000-0000-0000-000000000099 does not exist or is not visible',
 'printer cannot operate unassigned/invisible job'
);

reset role;
insert into public.sales_orders(id,order_number,customer_id,order_status,print_status,requested_due_date,created_by_user_id)
values('f2500000-0000-0000-0000-000000000002','SO-OPS040-CANCEL','f2200000-0000-0000-0000-000000000001','DRAFT','NOT_REQUIRED',current_date+2,'f2100000-0000-0000-0000-000000000001');
insert into public.sales_order_items(
 id,sales_order_id,product_variant_id,sale_unit,sale_quantity,units_per_sale_unit,unit_price_per_sale_unit,
 print_mode,print_color_count,print_specification,requested_due_date
) values(
 'f2600000-0000-0000-0000-000000000004','f2500000-0000-0000-0000-000000000002',
 'f2400000-0000-0000-0000-000000000001','piece',3,1,10,'PRINTED',1,'Cancel test',current_date+2
);
update public.sales_orders set order_status='CONFIRMED' where id='f2500000-0000-0000-0000-000000000002';

set local role authenticated;
set local request.jwt.claim.sub='f2100000-0000-0000-0000-000000000001';
select lives_ok(
 $$select public.create_print_job_from_requirement('PJ-OPS040-CANCEL','f2600000-0000-0000-0000-000000000004',null)$$,
 'create cancellable job'
);
select lives_ok(
 $$select public.set_print_job_status((select id from public.print_jobs where job_number='PJ-OPS040-CANCEL'),'CANCELLED','cancelled')$$,
 'WAITING job may cancel'
);
select is((select print_status from public.sales_orders where id='f2500000-0000-0000-0000-000000000002'),'WAITING','cancelled job reopens requirement');
select is(
 (select count(*) from public.print_job_requirement_queue() where sales_order_item_id='f2600000-0000-0000-0000-000000000004'),
 1::bigint,'cancelled line returns to requirement queue'
);
select lives_ok(
 $$select public.create_print_job_from_requirement('PJ-OPS040-REPLACEMENT','f2600000-0000-0000-0000-000000000004','replacement')$$,
 'cancelled job permits replacement'
);

reset role;
select * from finish();
rollback;
