begin;
create extension if not exists pgtap with schema extensions;
select plan(24);

select is(has_function_privilege('authenticated','public.create_print_job_evidence_attachment(uuid,text,text,text,bigint)','EXECUTE'),true,'evidence metadata RPC available');
select is(has_function_privilege('authenticated','public.submit_print_job_qc(uuid,text,uuid,text)','EXECUTE'),true,'QC submission RPC available');

insert into auth.users(id,email,raw_user_meta_data) values
('f4100000-0000-0000-0000-000000000001','ops-042-owner@example.test','{"display_name":"OPS-042 Owner"}'),
('f4100000-0000-0000-0000-000000000002','ops-042-printer@example.test','{"display_name":"OPS-042 Printer"}'),
('f4100000-0000-0000-0000-000000000003','ops-042-other@example.test','{"display_name":"Other Printer"}');
insert into public.user_roles(user_id,role_id)
select x.user_id,r.id from (values
('f4100000-0000-0000-0000-000000000001'::uuid,'OWNER_ADMIN'::text),
('f4100000-0000-0000-0000-000000000002'::uuid,'PRINTER_PRODUCTION'::text),
('f4100000-0000-0000-0000-000000000003'::uuid,'PRINTER_PRODUCTION'::text)
)x(user_id,role_code) join public.roles r on r.code=x.role_code;

insert into public.customers(id,customer_code,display_name)
values('f4200000-0000-0000-0000-000000000001','OPS042-CUSTOMER','OPS-042 Customer');
insert into public.products(id,name,product_type)
values('f4300000-0000-0000-0000-000000000001','OPS-042 Cup','CUP');
insert into public.product_variants(id,product_id,sku_code,variant_name,base_inventory_unit)
values('f4400000-0000-0000-0000-000000000001','f4300000-0000-0000-0000-000000000001','OPS042-SKU','OPS-042 Variant','piece');

insert into public.sales_orders(
 id,order_number,customer_id,order_status,print_status,requested_due_date,created_by_user_id
) values(
 'f4500000-0000-0000-0000-000000000001','SO-OPS042-001','f4200000-0000-0000-0000-000000000001',
 'DRAFT','NOT_REQUIRED',current_date+2,'f4100000-0000-0000-0000-000000000001'
);
insert into public.sales_order_items(
 id,sales_order_id,product_variant_id,sale_unit,sale_quantity,units_per_sale_unit,unit_price_per_sale_unit,
 print_mode,print_color_count,print_specification,artwork_reference,requested_due_date
) values(
 'f4600000-0000-0000-0000-000000000001','f4500000-0000-0000-0000-000000000001',
 'f4400000-0000-0000-0000-000000000001','piece',12,1,10,'PRINTED',2,'QC two colors','ART-042',current_date+2
);
update public.sales_orders set order_status='CONFIRMED'
where id='f4500000-0000-0000-0000-000000000001';

set local role authenticated;
set local request.jwt.claim.sub='f4100000-0000-0000-0000-000000000001';

select lives_ok(
 $$select public.create_print_job_from_requirement('PJ-OPS042-001','f4600000-0000-0000-0000-000000000001','QC flow')$$,
 'owner materializes print job'
);
select lives_ok(
 $$select public.assign_print_job((select id from public.print_jobs where job_number='PJ-OPS042-001'),'f4100000-0000-0000-0000-000000000002','assign QC printer')$$,
 'owner assigns production user'
);

select set_config(
 'ops.test_print_job_id',
 (select id::text from public.print_jobs where job_number='PJ-OPS042-001'),
 false
);


reset role;
set local role authenticated;
set local request.jwt.claim.sub='f4100000-0000-0000-0000-000000000002';

select lives_ok(
 $$select public.set_print_job_status((select id from public.print_jobs where job_number='PJ-OPS042-001'),'ACCEPTED','accepted')$$,
 'assigned printer accepts job'
);
select lives_ok(
 $$select public.set_print_job_status((select id from public.print_jobs where job_number='PJ-OPS042-001'),'IN_PROGRESS','started')$$,
 'assigned printer starts job'
);
select lives_ok(
 $$select public.set_print_job_status((select id from public.print_jobs where job_number='PJ-OPS042-001'),'WAITING_QC','ready QC')$$,
 'assigned printer sends job to QC'
);

select throws_ok(
 $$select public.submit_print_job_qc(
   (select id from public.print_jobs where job_number='PJ-OPS042-001'),'PASSED',
   'f4900000-0000-0000-0000-000000000099'::uuid,null
 )$$,
 'P0001','QC requires a valid production evidence attachment for this print job',
 'QC cannot pass without linked production evidence'
);

select lives_ok(
 $$select public.create_print_job_evidence_attachment(
   (select id from public.print_jobs where job_number='PJ-OPS042-001'),
   'print-jobs/'||(select id::text from public.print_jobs where job_number='PJ-OPS042-001')||'/fail.jpg',
   'fail.jpg','image/jpeg',100
 )$$,
 'assigned printer creates failed-QC evidence metadata'
);

select is(
 (select uploaded_by_user_id from public.attachments where original_file_name='fail.jpg'),
 'f4100000-0000-0000-0000-000000000002'::uuid,
 'evidence metadata binds uploader to authenticated printer'
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub='f4100000-0000-0000-0000-000000000003';

select throws_ok(
 $$select public.create_print_job_evidence_attachment(
   current_setting('ops.test_print_job_id')::uuid,
   'print-jobs/'||current_setting('ops.test_print_job_id')||'/other.jpg',
   'other.jpg','image/jpeg',50
 )$$,
 'P0001',
 'Print job '||current_setting('ops.test_print_job_id')||' does not exist or is not visible',
 'unassigned production user cannot add QC evidence'
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub='f4100000-0000-0000-0000-000000000002';

select lives_ok(
 $$select public.submit_print_job_qc(
   (select id from public.print_jobs where job_number='PJ-OPS042-001'),'FAILED',
   (select id from public.attachments where original_file_name='fail.jpg'),'print alignment failed'
 )$$,
 'failed QC returns job for rework'
);

select results_eq(
 $$select status,qc_state,(qc_completed_at is not null),(completed_at is null),
          completion_evidence_reference
   from public.print_jobs where job_number='PJ-OPS042-001'$$,
 $$select * from (values(
   'IN_PROGRESS'::text,'FAILED'::text,true,true,
   (select id::text from public.attachments where original_file_name='fail.jpg')
 )) as expected(status,qc_state,qc_done,not_completed,evidence_reference)$$,
 'failed QC stores state/evidence and reopens production'
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub='f4100000-0000-0000-0000-000000000001';

select is(
 (select print_status from public.sales_orders where order_number='SO-OPS042-001'),
 'IN_PROGRESS',
 'failed QC returns aggregate order print state to IN_PROGRESS'
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub='f4100000-0000-0000-0000-000000000002';

select results_eq(
 $$select event_type,from_status,to_status,qc_state,evidence_reference,actor_user_id
   from public.print_job_events
   where print_job_id=(select id from public.print_jobs where job_number='PJ-OPS042-001')
     and event_type='QC_FAILED_REWORK'$$,
 $$select * from (values(
   'QC_FAILED_REWORK'::text,'WAITING_QC'::text,'IN_PROGRESS'::text,'FAILED'::text,
   (select id::text from public.attachments where original_file_name='fail.jpg'),
   'f4100000-0000-0000-0000-000000000002'::uuid
 )) as expected(event_type,from_status,to_status,qc_state,evidence_reference,actor_user_id)$$,
 'failed-QC event captures evidence and actor'
);

select lives_ok(
 $$select public.set_print_job_status((select id from public.print_jobs where job_number='PJ-OPS042-001'),'WAITING_QC','reworked')$$,
 'reworked job may return to WAITING_QC'
);

select lives_ok(
 $$select public.create_print_job_evidence_attachment(
   (select id from public.print_jobs where job_number='PJ-OPS042-001'),
   'print-jobs/'||(select id::text from public.print_jobs where job_number='PJ-OPS042-001')||'/pass.jpg',
   'pass.jpg','image/jpeg',125
 )$$,
 'assigned printer creates passing evidence metadata'
);

select lives_ok(
 $$select public.submit_print_job_qc(
   (select id from public.print_jobs where job_number='PJ-OPS042-001'),'PASSED',
   (select id from public.attachments where original_file_name='pass.jpg'),'QC passed'
 )$$,
 'evidence-backed QC pass completes print job'
);

select results_eq(
 $$select status,qc_state,(qc_completed_at is not null),(completed_at is not null),
          completion_evidence_reference
   from public.print_jobs where job_number='PJ-OPS042-001'$$,
 $$select * from (values(
   'COMPLETED'::text,'PASSED'::text,true,true,
   (select id::text from public.attachments where original_file_name='pass.jpg')
 )) as expected(status,qc_state,qc_done,completed,evidence_reference)$$,
 'passed QC records completion timestamps and final evidence'
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub='f4100000-0000-0000-0000-000000000001';

select is(
 (select print_status from public.sales_orders where order_number='SO-OPS042-001'),
 'COMPLETED',
 'completed required print job synchronizes sales-order print status'
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub='f4100000-0000-0000-0000-000000000002';

select results_eq(
 $$select event_type,from_status,to_status,qc_state,evidence_reference,actor_user_id
   from public.print_job_events
   where print_job_id=(select id from public.print_jobs where job_number='PJ-OPS042-001')
     and event_type='QC_PASSED_COMPLETED'$$,
 $$select * from (values(
   'QC_PASSED_COMPLETED'::text,'WAITING_QC'::text,'COMPLETED'::text,'PASSED'::text,
   (select id::text from public.attachments where original_file_name='pass.jpg'),
   'f4100000-0000-0000-0000-000000000002'::uuid
 )) as expected(event_type,from_status,to_status,qc_state,evidence_reference,actor_user_id)$$,
 'passed-QC event captures final evidence and actor'
);

select is((select count(*) from public.production_mobile_work_queue()),0::bigint,'completed job leaves active mobile work queue');

select throws_ok(
 $$update public.print_jobs set qc_state='FAILED' where job_number='PJ-OPS042-001'$$,
 'P0001','QC and completion fields must use submit_print_job_qc',
 'direct QC mutation remains blocked'
);

select throws_ok(
 $$select public.create_print_job_evidence_attachment(
   (select id from public.print_jobs where job_number='PJ-OPS042-001'),
   'print-jobs/'||(select id::text from public.print_jobs where job_number='PJ-OPS042-001')||'/late.jpg',
   'late.jpg','image/jpeg',10
 )$$,
 'P0001','Production evidence may be added only while job is IN_PROGRESS or WAITING_QC',
 'completed job cannot accept late production evidence'
);

reset role;
select * from finish();
rollback;
