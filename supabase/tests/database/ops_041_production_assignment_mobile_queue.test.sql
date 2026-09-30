begin;
create extension if not exists pgtap with schema extensions;
select plan(27);

select is(has_function_privilege('authenticated','public.production_assignee_directory()','EXECUTE'),true,'assignee directory RPC available');
select is(has_function_privilege('authenticated','public.assign_print_job(uuid,uuid,text)','EXECUTE'),true,'assignment RPC available');
select is(has_function_privilege('authenticated','public.production_mobile_work_queue()','EXECUTE'),true,'mobile queue RPC available');

insert into auth.users(id,email,raw_user_meta_data) values
('f3100000-0000-0000-0000-000000000001','ops-041-owner@example.test','{"display_name":"OPS-041 Owner"}'),
('f3100000-0000-0000-0000-000000000002','ops-041-printer-a@example.test','{"display_name":"Printer A"}'),
('f3100000-0000-0000-0000-000000000003','ops-041-printer-b@example.test','{"display_name":"Printer B"}'),
('f3100000-0000-0000-0000-000000000004','ops-041-inactive@example.test','{"display_name":"Inactive Printer"}'),
('f3100000-0000-0000-0000-000000000005','ops-041-sales@example.test','{"display_name":"Sales User"}');

insert into public.user_roles(user_id,role_id)
select x.user_id,r.id
from (values
('f3100000-0000-0000-0000-000000000001'::uuid,'OWNER_ADMIN'::text),
('f3100000-0000-0000-0000-000000000002'::uuid,'PRINTER_PRODUCTION'::text),
('f3100000-0000-0000-0000-000000000003'::uuid,'PRINTER_PRODUCTION'::text),
('f3100000-0000-0000-0000-000000000004'::uuid,'PRINTER_PRODUCTION'::text),
('f3100000-0000-0000-0000-000000000005'::uuid,'SALES'::text)
)x(user_id,role_code)
join public.roles r on r.code=x.role_code;

update public.users set is_active=false where id='f3100000-0000-0000-0000-000000000004';

insert into public.customers(id,customer_code,display_name)
values('f3200000-0000-0000-0000-000000000001','OPS041-CUSTOMER','OPS-041 Customer');
insert into public.products(id,name,product_type)
values('f3300000-0000-0000-0000-000000000001','OPS-041 Cup','CUP');
insert into public.product_variants(id,product_id,sku_code,variant_name,base_inventory_unit)
values('f3400000-0000-0000-0000-000000000001','f3300000-0000-0000-0000-000000000001','OPS041-SKU','OPS-041 Variant','piece');

insert into public.sales_orders(
  id,order_number,customer_id,order_status,print_status,requested_due_date,created_by_user_id
) values(
  'f3500000-0000-0000-0000-000000000001','SO-OPS041-001','f3200000-0000-0000-0000-000000000001',
  'DRAFT','NOT_REQUIRED',current_date+3,'f3100000-0000-0000-0000-000000000001'
);
insert into public.sales_order_items(
  id,sales_order_id,product_variant_id,sale_unit,sale_quantity,units_per_sale_unit,unit_price_per_sale_unit,
  print_mode,print_color_count,print_specification,artwork_reference,requested_due_date
) values
('f3600000-0000-0000-0000-000000000001','f3500000-0000-0000-0000-000000000001','f3400000-0000-0000-0000-000000000001','piece',10,1,10,'PRINTED',2,'Front two colors','ART-041-A',current_date+2),
('f3600000-0000-0000-0000-000000000002','f3500000-0000-0000-0000-000000000001','f3400000-0000-0000-0000-000000000001','piece',5,1,10,'PRINTED',1,'Back one color','ART-041-B',current_date+3);
update public.sales_orders set order_status='CONFIRMED' where id='f3500000-0000-0000-0000-000000000001';

set local role authenticated;
set local request.jwt.claim.sub='f3100000-0000-0000-0000-000000000001';

select results_eq(
  $$select display_name from public.production_assignee_directory()$$,
  $$select * from (values('Printer A'::text),('Printer B'::text)) as expected(display_name) order by display_name$$,
  'owner directory includes only active PRINTER_PRODUCTION users'
);

select lives_ok(
  $$select public.create_print_job_from_requirement('PJ-OPS041-001','f3600000-0000-0000-0000-000000000001','mobile queue job')$$,
  'create first WAITING job'
);
select lives_ok(
  $$select public.create_print_job_from_requirement('PJ-OPS041-002','f3600000-0000-0000-0000-000000000002','assignment validation job')$$,
  'create second WAITING job'
);

select throws_ok(
  $$update public.print_jobs
    set assignee_user_id='f3100000-0000-0000-0000-000000000002'
    where job_number='PJ-OPS041-002'$$,
  'P0001','Print-job assignment changes must use assign_print_job',
  'direct WAITING assignment cannot bypass assignment history RPC'
);


select throws_ok(
  $$select public.set_print_job_status((select id from public.print_jobs where job_number='PJ-OPS041-001'),'ACCEPTED',null)$$,
  'P0001','Print job must be assigned before it can be ACCEPTED',
  'unassigned print job cannot be accepted'
);

select throws_ok(
  $$select public.assign_print_job((select id from public.print_jobs where job_number='PJ-OPS041-002'),'f3100000-0000-0000-0000-000000000005',null)$$,
  'P0001','Print-job assignee must be an active PRINTER_PRODUCTION user',
  'SALES user cannot be assigned production work'
);
select throws_ok(
  $$select public.assign_print_job((select id from public.print_jobs where job_number='PJ-OPS041-002'),'f3100000-0000-0000-0000-000000000004',null)$$,
  'P0001','Print-job assignee must be an active PRINTER_PRODUCTION user',
  'inactive production user cannot be assigned'
);

select lives_ok(
  $$select public.assign_print_job((select id from public.print_jobs where job_number='PJ-OPS041-001'),'f3100000-0000-0000-0000-000000000002','assign Printer A')$$,
  'owner assigns WAITING job to Printer A'
);
select is(
  (select assignee_user_id from public.print_jobs where job_number='PJ-OPS041-001'),
  'f3100000-0000-0000-0000-000000000002'::uuid,
  'assignment persists on print job'
);
select results_eq(
  $$select event_type,assignee_user_id,actor_user_id from public.print_job_events
    where print_job_id=(select id from public.print_jobs where job_number='PJ-OPS041-001')
      and event_type='ASSIGNMENT_CHANGED'$$,
  $$select * from (values(
    'ASSIGNMENT_CHANGED'::text,
    'f3100000-0000-0000-0000-000000000002'::uuid,
    'f3100000-0000-0000-0000-000000000001'::uuid
  )) as expected(event_type,assignee_user_id,actor_user_id)$$,
  'assignment event records assignee and authenticated owner actor'
);

select lives_ok(
  $$select public.assign_print_job((select id from public.print_jobs where job_number='PJ-OPS041-002'),'f3100000-0000-0000-0000-000000000003','assign Printer B')$$,
  'owner assigns second WAITING job to Printer B'
);
select lives_ok(
  $$select public.assign_print_job((select id from public.print_jobs where job_number='PJ-OPS041-002'),null,'unassign before acceptance')$$,
  'owner may unassign a WAITING job'
);
select is(
  (select assignee_user_id from public.print_jobs where job_number='PJ-OPS041-002'),
  null::uuid,
  'unassignment clears assignee'
);
select is(
  (select count(*) from public.print_job_events
   where print_job_id=(select id from public.print_jobs where job_number='PJ-OPS041-002')
     and event_type='ASSIGNMENT_CHANGED'),
  2::bigint,
  'assignment history records assign and unassign'
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub='f3100000-0000-0000-0000-000000000002';

select is((select count(*) from public.production_mobile_work_queue()),1::bigint,'Printer A sees only its assigned job');
select results_eq(
  $$select job_number,order_number,customer_name,sku_code,quantity_base_units,print_color_count,print_specification,artwork_reference,status
    from public.production_mobile_work_queue()$$,
  $$select * from (values(
    'PJ-OPS041-001'::text,'SO-OPS041-001'::text,'OPS-041 Customer'::text,'OPS041-SKU'::text,
    10::numeric,2::integer,'Front two colors'::text,'ART-041-A'::text,'WAITING'::text
  )) as expected(job_number,order_number,customer_name,sku_code,quantity_base_units,print_color_count,print_specification,artwork_reference,status)$$,
  'mobile queue contains only non-financial production execution fields'
);

select lives_ok(
  $$select public.set_print_job_status(
    (select print_job_id from public.production_mobile_work_queue() where job_number='PJ-OPS041-001'),
    'ACCEPTED','accepted on mobile'
  )$$,
  'assigned printer accepts its job'
);
select lives_ok(
  $$select public.set_print_job_status(
    (select print_job_id from public.production_mobile_work_queue() where job_number='PJ-OPS041-001'),
    'IN_PROGRESS','started on mobile'
  )$$,
  'assigned printer starts its job'
);
select results_eq(
  $$select status,(accepted_at is not null),(started_at is not null) from public.production_mobile_work_queue()$$,
  $$select * from (values('IN_PROGRESS'::text,true,true)) as expected(status,has_accepted_at,has_started_at)$$,
  'mobile queue reflects workflow timestamps and current state'
);

select throws_ok(
  $$update public.print_jobs
    set assignee_user_id='f3100000-0000-0000-0000-000000000003'
    where job_number='PJ-OPS041-001'$$,
  'P0001',
  'PRINTER_PRODUCTION may update only production/QC execution fields on assigned print jobs',
  'production user cannot self-reassign'
);
select throws_ok(
  $$select public.production_assignee_directory()$$,
  '42501','Production assignee directory requires OWNER_ADMIN role',
  'production user cannot enumerate assignment directory'
);
select throws_ok(
  $$select public.assign_print_job(
    (select print_job_id from public.production_mobile_work_queue() where job_number='PJ-OPS041-001'),
    'f3100000-0000-0000-0000-000000000003',null
  )$$,
  '42501','Print-job assignment requires OWNER_ADMIN role',
  'production user cannot invoke assignment RPC'
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub='f3100000-0000-0000-0000-000000000003';
select is((select count(*) from public.production_mobile_work_queue()),0::bigint,'Printer B does not see Printer A job');
reset role;

set local role authenticated;
set local request.jwt.claim.sub='f3100000-0000-0000-0000-000000000001';
select throws_ok(
  $$select public.assign_print_job(
    (select id from public.print_jobs where job_number='PJ-OPS041-001'),
    'f3100000-0000-0000-0000-000000000003','late reassignment'
  )$$,
  'P0001','Print-job assignment is locked unless job is WAITING',
  'assignment locks after acceptance/start'
);

reset role;
select * from finish();
rollback;
