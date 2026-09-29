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
      and c.relname = 'customers'
      and t.tgname = 'customers_capture_activity'
      and not t.tgisinternal
  $$,
  array[1::bigint],
  'OPS-004 installs one automatic customer activity trigger'
);

select results_eq(
  $$
    select p.prosecdef
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'capture_customer_activity'
      and p.pronargs = 0
  $$,
  array[true],
  'customer activity capture executes as SECURITY DEFINER'
);

select results_eq(
  $$
    select has_function_privilege(
      'authenticated',
      'public.capture_customer_activity()',
      'EXECUTE'
    )
  $$,
  array[false],
  'authenticated users cannot directly execute the customer audit trigger function'
);

insert into auth.users (id, email)
values (
  '98000000-0000-0000-0000-000000000001',
  'ops-customer-activity@example.test'
);

insert into public.user_roles (user_id, role_id)
select
  '98000000-0000-0000-0000-000000000001'::uuid,
  r.id
from public.roles r
where r.code = 'SALES';

set local role authenticated;
set local request.jwt.claim.sub = '98000000-0000-0000-0000-000000000001';

insert into public.customers (
  id,
  customer_code,
  display_name,
  brand_name
)
values (
  '98100000-0000-0000-0000-000000000001',
  'CUSTOMER-ACTIVITY-001',
  'Customer Activity Initial',
  'Activity Brand'
);

update public.customers
set display_name = 'Customer Activity Updated'
where id = '98100000-0000-0000-0000-000000000001';

delete from public.customers
where id = '98100000-0000-0000-0000-000000000001';

reset role;

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_type = 'CUSTOMER'
      and linked_entity_id = '98100000-0000-0000-0000-000000000001'
  ),
  3::bigint,
  'create/update/delete each append one customer activity record'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '98100000-0000-0000-0000-000000000001'
      and action_type = 'CUSTOMER_CREATED'
      and before_data is null
      and after_data ->> 'customer_code' = 'CUSTOMER-ACTIVITY-001'
      and after_data ->> 'display_name' = 'Customer Activity Initial'
  ),
  1::bigint,
  'customer creation captures the post-change snapshot'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '98100000-0000-0000-0000-000000000001'
      and action_type = 'CUSTOMER_UPDATED'
      and before_data ->> 'display_name' = 'Customer Activity Initial'
      and after_data ->> 'display_name' = 'Customer Activity Updated'
  ),
  1::bigint,
  'customer update captures before and after snapshots'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '98100000-0000-0000-0000-000000000001'
      and action_type = 'CUSTOMER_DELETED'
      and before_data ->> 'customer_code' = 'CUSTOMER-ACTIVITY-001'
      and before_data ->> 'display_name' = 'Customer Activity Updated'
      and after_data is null
  ),
  1::bigint,
  'customer deletion captures the pre-delete snapshot'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '98100000-0000-0000-0000-000000000001'
      and actor_user_id = '98000000-0000-0000-0000-000000000001'
  ),
  3::bigint,
  'all customer activity rows bind actor identity to auth.uid()'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '98100000-0000-0000-0000-000000000001'
      and event_source = 'USER'
  ),
  3::bigint,
  'authenticated customer mutations are marked as USER events'
);

select results_eq(
  $$
    select count(*)::bigint
    from public.activity_logs
    where linked_entity_id = '98100000-0000-0000-0000-000000000001'
      and metadata ->> 'table_name' = 'customers'
      and metadata ->> 'schema_name' = 'public'
  $$,
  array[3::bigint],
  'customer activity metadata records its database source'
);

select * from finish();
rollback;
