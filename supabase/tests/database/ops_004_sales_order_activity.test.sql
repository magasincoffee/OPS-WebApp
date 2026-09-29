begin;

create extension if not exists pgtap with schema extensions;

select plan(10);

select results_eq(
  $$
    select count(*)::bigint
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'sales_orders'
      and t.tgname = 'sales_orders_capture_activity'
      and not t.tgisinternal
  $$,
  array[1::bigint],
  'OPS-004 installs one automatic sales-order activity trigger'
);

select results_eq(
  $$
    select p.prosecdef
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'capture_sales_order_activity'
      and p.pronargs = 0
  $$,
  array[true],
  'sales-order activity capture executes as SECURITY DEFINER'
);

select results_eq(
  $$
    select has_function_privilege(
      'authenticated',
      'public.capture_sales_order_activity()',
      'EXECUTE'
    )
  $$,
  array[false],
  'authenticated users cannot directly execute the sales-order audit trigger function'
);

insert into auth.users (id, email)
values (
  '91000000-0000-0000-0000-000000000001',
  'ops-sales-activity@example.test'
);

insert into public.user_roles (user_id, role_id)
select
  '91000000-0000-0000-0000-000000000001'::uuid,
  r.id
from public.roles r
where r.code = 'SALES';

insert into public.customers (id, customer_code, display_name)
values (
  '92000000-0000-0000-0000-000000000001',
  'ACTIVITY-CUSTOMER',
  'Activity Capture Customer'
);

set local role authenticated;
set local request.jwt.claim.sub = '91000000-0000-0000-0000-000000000001';

insert into public.sales_orders (
  id,
  order_number,
  customer_id,
  created_by_user_id,
  salesperson_user_id
)
values (
  '93000000-0000-0000-0000-000000000001',
  'SO-ACTIVITY-001',
  '92000000-0000-0000-0000-000000000001',
  '91000000-0000-0000-0000-000000000001',
  '91000000-0000-0000-0000-000000000001'
);

update public.sales_orders
set order_status = 'CONFIRMED'
where id = '93000000-0000-0000-0000-000000000001';

delete from public.sales_orders
where id = '93000000-0000-0000-0000-000000000001';

reset role;

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_type = 'SALES_ORDER'
      and linked_entity_id = '93000000-0000-0000-0000-000000000001'
  ),
  3::bigint,
  'create/update/delete each append one sales-order activity record'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '93000000-0000-0000-0000-000000000001'
      and action_type = 'SALES_ORDER_CREATED'
      and before_data is null
      and after_data ->> 'order_number' = 'SO-ACTIVITY-001'
  ),
  1::bigint,
  'sales-order creation captures the post-change snapshot'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '93000000-0000-0000-0000-000000000001'
      and action_type = 'SALES_ORDER_UPDATED'
      and before_data ->> 'order_status' = 'DRAFT'
      and after_data ->> 'order_status' = 'CONFIRMED'
  ),
  1::bigint,
  'sales-order update captures before and after status snapshots'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '93000000-0000-0000-0000-000000000001'
      and action_type = 'SALES_ORDER_DELETED'
      and before_data ->> 'order_number' = 'SO-ACTIVITY-001'
      and after_data is null
  ),
  1::bigint,
  'sales-order deletion captures the pre-delete snapshot'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '93000000-0000-0000-0000-000000000001'
      and actor_user_id = '91000000-0000-0000-0000-000000000001'
  ),
  3::bigint,
  'all sales-order activity rows bind actor identity to auth.uid()'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '93000000-0000-0000-0000-000000000001'
      and event_source = 'USER'
  ),
  3::bigint,
  'authenticated sales-order mutations are marked as USER events'
);

select results_eq(
  $$
    select count(*)::bigint
    from public.activity_logs
    where linked_entity_id = '93000000-0000-0000-0000-000000000001'
      and metadata ->> 'table_name' = 'sales_orders'
      and metadata ->> 'schema_name' = 'public'
  $$,
  array[3::bigint],
  'sales-order activity metadata records its database source'
);

select * from finish();
rollback;
