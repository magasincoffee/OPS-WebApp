begin;
create extension if not exists pgtap with schema extensions;
select plan(29);

select is(has_function_privilege('authenticated','public.create_operational_task(text,text,uuid,uuid,timestamptz,text,text)','EXECUTE'),true,'task creation RPC available');
select is(has_function_privilege('authenticated','public.manage_operational_task(uuid,uuid,timestamptz,text,text)','EXECUTE'),true,'task management RPC available');
select is(has_function_privilege('authenticated','public.update_operational_task_execution(uuid,text,text)','EXECUTE'),true,'task execution RPC available');
select is(has_function_privilege('authenticated','public.cancel_operational_task(uuid,text)','EXECUTE'),true,'task cancellation RPC available');
select is(has_function_privilege('authenticated','public.task_assignee_directory()','EXECUTE'),true,'task assignee directory available');

insert into auth.users(id,email,raw_user_meta_data) values
('fa100000-0000-0000-0000-000000000001','ops-061-owner@example.test','{"display_name":"OPS-061 Owner"}'),
('fa100000-0000-0000-0000-000000000002','ops-061-warehouse@example.test','{"display_name":"OPS-061 Warehouse"}'),
('fa100000-0000-0000-0000-000000000003','ops-061-accounting@example.test','{"display_name":"OPS-061 Accounting"}'),
('fa100000-0000-0000-0000-000000000004','ops-061-sales@example.test','{"display_name":"OPS-061 Sales"}'),
('fa100000-0000-0000-0000-000000000005','ops-061-production@example.test','{"display_name":"OPS-061 Production"}'),
('fa100000-0000-0000-0000-000000000006','ops-061-no-role@example.test','{"display_name":"OPS-061 No Role"}');

insert into public.user_roles(user_id,role_id)
select x.user_id,r.id from (values
('fa100000-0000-0000-0000-000000000001'::uuid,'OWNER_ADMIN'::text),
('fa100000-0000-0000-0000-000000000002'::uuid,'WAREHOUSE'::text),
('fa100000-0000-0000-0000-000000000003'::uuid,'ACCOUNTING'::text),
('fa100000-0000-0000-0000-000000000004'::uuid,'SALES'::text),
('fa100000-0000-0000-0000-000000000005'::uuid,'PRINTER_PRODUCTION'::text)
)x(user_id,role_code) join public.roles r on r.code=x.role_code;

set local role authenticated;
set local request.jwt.claim.sub='fa100000-0000-0000-0000-000000000001';

select is((select count(*) from public.task_assignee_directory()),4::bigint,'owner directory contains active non-owner operational assignees');

select lives_ok(
 'select public.create_operational_task(
   ''WAREHOUSE_PREPARATION'',''SALES_ORDER'',''fa200000-0000-0000-0000-000000000001'',
   ''fa100000-0000-0000-0000-000000000002'',
   timezone(''utc'',now())-interval ''1 day'',''HIGH'',''Prepare order for issue''
 )',
 'owner creates assigned warehouse task'
);

select set_config(
  'ops.test_task_id',
  (select task_id::text from public.operational_task_queue where task_type='WAREHOUSE_PREPARATION'),
  true
);

select results_eq(
 $$select task_type,linked_entity_type,assignee_user_id,status,priority,created_by_user_id,is_overdue
   from public.operational_task_queue
   where task_type='WAREHOUSE_PREPARATION'$$,
 $$select * from (values(
   'WAREHOUSE_PREPARATION'::text,'SALES_ORDER'::text,
   'fa100000-0000-0000-0000-000000000002'::uuid,
   'OPEN'::text,'HIGH'::text,'fa100000-0000-0000-0000-000000000001'::uuid,true
 )) as expected(task_type,linked_entity_type,assignee_user_id,status,priority,created_by_user_id,is_overdue)$$,
 'created task stores assignment, source, creator and overdue state'
);

select throws_ok(
 $$select public.create_operational_task(
   'ORDER_OPERATION',null,null,'fa100000-0000-0000-0000-000000000006',
   null,'NORMAL','invalid assignee'
 )$$,
 'P0001','Task assignee must be an active operational user',
 'owner cannot assign task to user without operational role'
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub='fa100000-0000-0000-0000-000000000003';

select is((select count(*) from public.operational_task_queue),0::bigint,'unassigned accounting user cannot see warehouse task');

select throws_ok(
 $select public.update_operational_task_execution(
   current_setting('ops.test_task_id')::uuid,'IN_PROGRESS','should not work'
 )$,
 'P0001',
 'Operational task '||current_setting('ops.test_task_id')||' does not exist or is not visible',
 'non-assignee cannot execute another user task'
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub='fa100000-0000-0000-0000-000000000002';

select is((select count(*) from public.operational_task_queue where task_type='WAREHOUSE_PREPARATION'),1::bigint,'warehouse assignee sees own task');

select lives_ok(
 $$select public.update_operational_task_execution(
   (select task_id from public.operational_task_queue where task_type='WAREHOUSE_PREPARATION'),
   'IN_PROGRESS','Picking stock'
 )$$,
 'assignee starts task'
);

select results_eq(
 $$select status,notes,(completed_at is null)
   from public.operational_task_queue where task_type='WAREHOUSE_PREPARATION'$$,
 $$select * from (values('IN_PROGRESS'::text,'Picking stock'::text,true)) as expected(status,notes,incomplete)$$,
 'execution update stores status/note without completion timestamp'
);

select throws_ok(
 $$update public.tasks
   set assignee_user_id='fa100000-0000-0000-0000-000000000003'
   where task_type='WAREHOUSE_PREPARATION'$$,
 'P0001','Task assignees may update only execution fields on their assigned tasks',
 'assignee cannot rewrite assignment'
);

select throws_ok(
 $$select public.update_operational_task_execution(
   (select task_id from public.operational_task_queue where task_type='WAREHOUSE_PREPARATION'),
   'CANCELLED','cancel myself'
 )$$,
 'P0001','Invalid operational task execution status',
 'assignee execution RPC cannot cancel task'
);

select lives_ok(
 $$select public.update_operational_task_execution(
   (select task_id from public.operational_task_queue where task_type='WAREHOUSE_PREPARATION'),
   'BLOCKED','Waiting for stock'
 )$$,
 'assignee blocks task'
);

select lives_ok(
 $$select public.update_operational_task_execution(
   (select task_id from public.operational_task_queue where task_type='WAREHOUSE_PREPARATION'),
   'IN_PROGRESS','Stock arrived'
 )$$,
 'blocked task returns to in progress'
);

select lives_ok(
 $$select public.update_operational_task_execution(
   (select task_id from public.operational_task_queue where task_type='WAREHOUSE_PREPARATION'),
   'DONE','Prepared'
 )$$,
 'assignee completes task'
);

select results_eq(
 $$select status,(completed_at is not null),is_overdue
   from public.operational_task_queue where task_type='WAREHOUSE_PREPARATION'$$,
 $$select * from (values('DONE'::text,true,false)) as expected(status,completed,is_overdue)$$,
 'DONE task receives completion timestamp and is no longer overdue'
);

select throws_ok(
 $$select public.update_operational_task_execution(
   (select task_id from public.operational_task_queue where task_type='WAREHOUSE_PREPARATION'),
   'IN_PROGRESS','reopen'
 )$$,
 'P0001','Closed operational tasks are locked for assignees',
 'assignee cannot reopen completed task'
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub='fa100000-0000-0000-0000-000000000001';

select lives_ok(
 $$select public.update_operational_task_execution(
   (select task_id from public.operational_task_queue where task_type='WAREHOUSE_PREPARATION'),
   'OPEN','Owner reopened'
 )$$,
 'owner may reopen completed task'
);

select results_eq(
 $$select status,(completed_at is null)
   from public.operational_task_queue where task_type='WAREHOUSE_PREPARATION'$$,
 $$select * from (values('OPEN'::text,true)) as expected(status,completion_cleared)$$,
 'owner reopen clears completion timestamp'
);

select lives_ok(
 $$select public.manage_operational_task(
   (select task_id from public.operational_task_queue where task_type='WAREHOUSE_PREPARATION'),
   'fa100000-0000-0000-0000-000000000003',
   timezone('utc',now())+interval '2 days','URGENT','Accounting follow-up reassignment'
 )$$,
 'owner reassigns open task and management fields'
);

select results_eq(
 $$select assignee_user_id,priority,is_overdue
   from public.operational_task_queue where task_type='WAREHOUSE_PREPARATION'$$,
 $$select * from (values(
   'fa100000-0000-0000-0000-000000000003'::uuid,'URGENT'::text,false
 )) as expected(assignee_user_id,priority,is_overdue)$$,
 'owner management persists reassignment, priority and due date'
);

select lives_ok(
 $$select public.cancel_operational_task(
   (select task_id from public.operational_task_queue where task_type='WAREHOUSE_PREPARATION'),
   'No longer required'
 )$$,
 'owner cancels open task'
);

select results_eq(
 $$select status,(completed_at is null),(notes like '%Cancelled: No longer required%')
   from public.operational_task_queue where task_type='WAREHOUSE_PREPARATION'$$,
 $$select * from (values('CANCELLED'::text,true,true)) as expected(status,no_completed_at,cancel_note)$$,
 'cancel preserves non-completion semantics and records note'
);

select is(
 (select count(*) from public.activity_logs al
  join public.tasks t on t.id=al.linked_entity_id
  where al.linked_entity_type='TASK' and t.task_type='WAREHOUSE_PREPARATION'),
 8::bigint,
 'create and seven workflow updates are captured by existing task activity audit'
);

select is(
 (select count(*) from public.activity_logs al
  join public.tasks t on t.id=al.linked_entity_id
  where al.linked_entity_type='TASK'
    and t.task_type='WAREHOUSE_PREPARATION'
    and al.actor_user_id='fa100000-0000-0000-0000-000000000002'),
 4::bigint,
 'assignee execution updates retain authenticated actor identity'
);

reset role;
select * from finish();
rollback;
