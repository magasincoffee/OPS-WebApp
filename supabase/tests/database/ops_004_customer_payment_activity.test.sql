begin;

create extension if not exists pgtap with schema extensions;

select plan(8);

select results_eq(
  $$
    select count(*)::bigint
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'customer_payments'
      and t.tgname = 'customer_payments_capture_activity'
      and not t.tgisinternal
  $$,
  array[1::bigint],
  'OPS-004 installs one automatic customer-payment activity trigger'
);

select results_eq(
  $$
    select p.prosecdef
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'capture_customer_payment_activity'
      and p.pronargs = 0
  $$,
  array[true],
  'customer-payment activity capture executes as SECURITY DEFINER'
);

select results_eq(
  $$
    select has_function_privilege(
      'authenticated',
      'public.capture_customer_payment_activity()',
      'EXECUTE'
    )
  $$,
  array[false],
  'authenticated users cannot directly execute the customer-payment audit trigger function'
);

insert into auth.users (id, email)
values (
  '94000000-0000-0000-0000-000000000001',
  'ops-payment-activity@example.test'
);

insert into public.user_roles (user_id, role_id)
select
  '94000000-0000-0000-0000-000000000001'::uuid,
  r.id
from public.roles r
where r.code = 'ACCOUNTING';

insert into public.customers (id, customer_code, display_name)
values (
  '95000000-0000-0000-0000-000000000001',
  'PAYMENT-ACTIVITY-CUSTOMER',
  'Payment Activity Customer'
);

set local role authenticated;
set local request.jwt.claim.sub = '94000000-0000-0000-0000-000000000001';

insert into public.customer_payments (
  id,
  customer_id,
  amount,
  payment_date,
  payment_method,
  reference,
  created_by_user_id
)
values (
  '96000000-0000-0000-0000-000000000001',
  '95000000-0000-0000-0000-000000000001',
  1250000,
  current_date,
  'BANK_TRANSFER',
  'PAY-ACTIVITY-001',
  '94000000-0000-0000-0000-000000000001'
);

update public.customer_payments
set
  status = 'VOIDED',
  voided_at = timezone('utc', now()),
  voided_by_user_id = '94000000-0000-0000-0000-000000000001',
  note = 'Voided for OPS-004 activity test'
where id = '96000000-0000-0000-0000-000000000001';

reset role;

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_type = 'CUSTOMER_PAYMENT'
      and linked_entity_id = '96000000-0000-0000-0000-000000000001'
  ),
  2::bigint,
  'create and update each append one customer-payment activity record'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '96000000-0000-0000-0000-000000000001'
      and action_type = 'CUSTOMER_PAYMENT_CREATED'
      and before_data is null
      and after_data ->> 'status' = 'POSTED'
      and after_data ->> 'reference' = 'PAY-ACTIVITY-001'
  ),
  1::bigint,
  'customer-payment creation captures the post-change snapshot'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '96000000-0000-0000-0000-000000000001'
      and action_type = 'CUSTOMER_PAYMENT_UPDATED'
      and before_data ->> 'status' = 'POSTED'
      and after_data ->> 'status' = 'VOIDED'
      and after_data ->> 'voided_by_user_id' = '94000000-0000-0000-0000-000000000001'
  ),
  1::bigint,
  'customer-payment void captures before and after status snapshots'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '96000000-0000-0000-0000-000000000001'
      and actor_user_id = '94000000-0000-0000-0000-000000000001'
      and event_source = 'USER'
  ),
  2::bigint,
  'customer-payment activity binds authenticated actor identity and USER source'
);

select results_eq(
  $$
    select count(*)::bigint
    from public.activity_logs
    where linked_entity_id = '96000000-0000-0000-0000-000000000001'
      and metadata ->> 'table_name' = 'customer_payments'
      and metadata ->> 'schema_name' = 'public'
  $$,
  array[2::bigint],
  'customer-payment activity metadata records its database source'
);

select * from finish();
rollback;
