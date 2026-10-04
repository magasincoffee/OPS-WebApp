begin;

create extension if not exists pgtap with schema extensions;

select plan(11);

select results_eq(
  $$
    select count(*)::bigint
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'deliveries'
      and t.tgname = 'deliveries_capture_activity'
      and not t.tgisinternal
  $$,
  array[1::bigint],
  'OPS-004 installs one automatic delivery activity trigger'
);

select results_eq(
  $$
    select p.prosecdef
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'capture_delivery_activity'
      and p.pronargs = 0
  $$,
  array[true],
  'delivery activity capture executes as SECURITY DEFINER'
);

select results_eq(
  $$
    select has_function_privilege(
      'authenticated',
      'public.capture_delivery_activity()',
      'EXECUTE'
    )
  $$,
  array[false],
  'authenticated users cannot directly execute the delivery audit trigger function'
);

insert into auth.users (id, email)
values (
  '97700000-0000-0000-0000-000000000001',
  'ops-delivery-activity-warehouse@example.test'
);

insert into public.user_roles (user_id, role_id)
select
  '97700000-0000-0000-0000-000000000001'::uuid,
  r.id
from public.roles r
where r.code = 'WAREHOUSE';

insert into public.customers (
  id,
  customer_code,
  display_name
)
values (
  '97800000-0000-0000-0000-000000000001',
  'DELIVERY-ACTIVITY-CUSTOMER',
  'Delivery Activity Customer'
);

insert into public.sales_orders (
  id,
  order_number,
  customer_id,
  order_status,
  created_by_user_id,
  notes
)
values (
  '97900000-0000-0000-0000-000000000001',
  'SO-DELIVERY-ACTIVITY-001',
  '97800000-0000-0000-0000-000000000001',
  'CONFIRMED',
  '97700000-0000-0000-0000-000000000001',
  'OPS-004 delivery activity parent order'
);

set local role authenticated;
set local request.jwt.claim.sub = '97700000-0000-0000-0000-000000000001';

insert into public.deliveries (
  id,
  delivery_number,
  sales_order_id,
  status,
  consignee_name,
  consignee_phone,
  consignee_address,
  created_by_user_id,
  notes
)
values (
  '98000000-0000-0000-0000-000000000001',
  'DELIVERY-ACTIVITY-001',
  '97900000-0000-0000-0000-000000000001',
  'NOT_READY',
  'Delivery Activity Consignee',
  '0900000000',
  'OPS-004 delivery activity test address',
  '97700000-0000-0000-0000-000000000001',
  'OPS-004 delivery activity test'
);

update public.deliveries
set
  parcel_info = '1 carton',
  notes = 'OPS-004 delivery activity test updated'
where id = '98000000-0000-0000-0000-000000000001';

reset role;
set local request.jwt.claim.sub = '';

delete from public.deliveries
where id = '98000000-0000-0000-0000-000000000001';

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_type = 'DELIVERY'
      and linked_entity_id = '98000000-0000-0000-0000-000000000001'
  ),
  3::bigint,
  'create/update/delete each append one delivery activity record'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '98000000-0000-0000-0000-000000000001'
      and action_type = 'DELIVERY_CREATED'
      and before_data is null
      and after_data ->> 'delivery_number' = 'DELIVERY-ACTIVITY-001'
      and after_data ->> 'status' = 'NOT_READY'
  ),
  1::bigint,
  'delivery creation captures the post-change snapshot'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '98000000-0000-0000-0000-000000000001'
      and action_type = 'DELIVERY_UPDATED'
      and before_data ->> 'status' = 'NOT_READY'
      and after_data ->> 'status' = 'NOT_READY'
      and before_data ->> 'parcel_info' is null
      and after_data ->> 'parcel_info' = '1 carton'
      and before_data ->> 'notes' = 'OPS-004 delivery activity test'
      and after_data ->> 'notes' = 'OPS-004 delivery activity test updated'
  ),
  1::bigint,
  'delivery update captures before and after snapshots'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '98000000-0000-0000-0000-000000000001'
      and action_type = 'DELIVERY_DELETED'
      and before_data ->> 'delivery_number' = 'DELIVERY-ACTIVITY-001'
      and after_data is null
  ),
  1::bigint,
  'delivery deletion captures the pre-delete snapshot'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '98000000-0000-0000-0000-000000000001'
      and actor_user_id = '97700000-0000-0000-0000-000000000001'
  ),
  2::bigint,
  'authenticated delivery create/update activity binds actor identity to auth.uid()'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '98000000-0000-0000-0000-000000000001'
      and event_source = 'USER'
  ),
  2::bigint,
  'authenticated delivery mutations are marked as USER events'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '98000000-0000-0000-0000-000000000001'
      and action_type = 'DELIVERY_DELETED'
      and actor_user_id is null
      and event_source = 'SYSTEM'
  ),
  1::bigint,
  'trusted delivery deletion without an auth subject is marked as a SYSTEM event'
);

select results_eq(
  $$
    select count(*)::bigint
    from public.activity_logs
    where linked_entity_id = '98000000-0000-0000-0000-000000000001'
      and metadata ->> 'table_name' = 'deliveries'
      and metadata ->> 'schema_name' = 'public'
  $$,
  array[3::bigint],
  'delivery activity metadata records its database source'
);

select * from finish();
rollback;
