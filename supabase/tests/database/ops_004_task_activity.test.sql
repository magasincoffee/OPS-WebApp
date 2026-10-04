begin;

create extension if not exists pgtap with schema extensions;

select plan(10);

select results_eq(
  $$select count(*)::bigint
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'tasks'
      and t.tgname = 'tasks_capture_activity'
      and not t.tgisinternal$$,
  array[1::bigint],
  'OPS-004 installs one automatic task activity trigger'
);

select results_eq(
  $$select p.prosecdef
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'capture_task_activity'
      and p.pronargs = 0$$,
  array[true],
  'task activity capture executes as SECURITY DEFINER'
);

select results_eq(
  $$select has_function_privilege(
      'authenticated',
      'public.capture_task_activity()',
      'EXECUTE'
    )$$,
  array[false],
  'authenticated users cannot directly execute the task audit trigger function'
);

insert into auth.users (id, email)
values
  ('98100000-0000-0000-0000-000000000001', 'ops-task-owner@example.test'),
  ('98100000-0000-0000-0000-000000000002', 'ops-task-sales@example.test');

insert into public.user_roles (user_id, role_id)
select '98100000-0000-0000-0000-000000000001'::uuid, id
from public.roles where code = 'OWNER_ADMIN';

insert into public.user_roles (user_id, role_id)
select '98100000-0000-0000-0000-000000000002'::uuid, id
from public.roles where code = 'SALES';

set local role authenticated;
set local request.jwt.claim.sub = '98100000-0000-0000-0000-000000000001';

insert into public.tasks (
  id,
  task_type,
  assignee_user_id,
  due_at,
  status,
  priority,
  notes,
  created_by_user_id
)
values (
  '98200000-0000-0000-0000-000000000001',
  'ORDER_FOLLOW_UP',
  '98100000-0000-0000-0000-000000000002',
  timezone('utc', now()) + interval '1 day',
  'OPEN',
  'HIGH',
  'OPS-004 task activity test',
  '98100000-0000-0000-0000-000000000001'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '98100000-0000-0000-0000-000000000002';

update public.tasks
set status = 'IN_PROGRESS',
    notes = 'OPS-004 task activity test updated'
where id = '98200000-0000-0000-0000-000000000001';

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '98100000-0000-0000-0000-000000000001';

delete from public.tasks
where id = '98200000-0000-0000-0000-000000000001';

reset role;
set local request.jwt.claim.sub = '';

select is(
  (select count(*) from public.activity_logs
   where linked_entity_type = 'TASK'
     and linked_entity_id = '98200000-0000-0000-0000-000000000001'),
  3::bigint,
  'create/update/delete each append one task activity record'
);

select is(
  (select count(*) from public.activity_logs
   where linked_entity_id = '98200000-0000-0000-0000-000000000001'
     and action_type = 'TASK_CREATED'
     and before_data is null
     and after_data ->> 'status' = 'OPEN'),
  1::bigint,
  'task creation captures the post-change snapshot'
);

select is(
  (select count(*) from public.activity_logs
   where linked_entity_id = '98200000-0000-0000-0000-000000000001'
     and action_type = 'TASK_UPDATED'
     and before_data ->> 'status' = 'OPEN'
     and after_data ->> 'status' = 'IN_PROGRESS'),
  1::bigint,
  'task update captures before and after snapshots'
);

select is(
  (select count(*) from public.activity_logs
   where linked_entity_id = '98200000-0000-0000-0000-000000000001'
     and action_type = 'TASK_DELETED'
     and before_data ->> 'status' = 'IN_PROGRESS'
     and after_data is null),
  1::bigint,
  'task deletion captures the pre-delete snapshot'
);

select is(
  (select count(*) from public.activity_logs
   where linked_entity_id = '98200000-0000-0000-0000-000000000001'
     and actor_user_id = '98100000-0000-0000-0000-000000000001'),
  2::bigint,
  'OWNER_ADMIN identity is captured for task create/delete'
);

select is(
  (select count(*) from public.activity_logs
   where linked_entity_id = '98200000-0000-0000-0000-000000000001'
     and action_type = 'TASK_UPDATED'
     and actor_user_id = '98100000-0000-0000-0000-000000000002'),
  1::bigint,
  'assignee identity is captured for task update'
);

select results_eq(
  $$select count(*)::bigint from public.activity_logs
    where linked_entity_id = '98200000-0000-0000-0000-000000000001'
      and event_source = 'USER'
      and metadata ->> 'table_name' = 'tasks'
      and metadata ->> 'schema_name' = 'public'$$,
  array[3::bigint],
  'task activity is marked USER and records its database source'
);

select * from finish();
rollback;
