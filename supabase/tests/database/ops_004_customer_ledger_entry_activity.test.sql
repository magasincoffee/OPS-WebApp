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
      and c.relname = 'customer_ledger_entries'
      and t.tgname = 'customer_ledger_entries_capture_activity'
      and not t.tgisinternal
  $$,
  array[1::bigint],
  'OPS-004 installs one automatic customer-ledger-entry activity trigger'
);

select results_eq(
  $$
    select p.prosecdef
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'capture_customer_ledger_entry_activity'
      and p.pronargs = 0
  $$,
  array[true],
  'customer-ledger-entry activity capture executes as SECURITY DEFINER'
);

select results_eq(
  $$
    select has_function_privilege(
      'authenticated',
      'public.capture_customer_ledger_entry_activity()',
      'EXECUTE'
    )
  $$,
  array[false],
  'authenticated users cannot directly execute the customer-ledger-entry audit trigger function'
);

insert into auth.users (id, email)
values (
  '9c100000-0000-0000-0000-000000000001',
  'ops-customer-ledger-activity-owner@example.test'
);

insert into public.user_roles (user_id, role_id)
select
  '9c100000-0000-0000-0000-000000000001'::uuid,
  r.id
from public.roles r
where r.code = 'OWNER_ADMIN';

insert into public.customers (id, customer_code, display_name)
values (
  '9c200000-0000-0000-0000-000000000001',
  'CL-ACTIVITY-001',
  'Customer Ledger Activity Customer'
);

insert into public.customer_payments (
  id,
  customer_id,
  amount,
  payment_method,
  reference,
  created_by_user_id
)
values (
  '9c300000-0000-0000-0000-000000000001',
  '9c200000-0000-0000-0000-000000000001',
  150000,
  'BANK_TRANSFER',
  'CL-ACTIVITY-PAYMENT-001',
  '9c100000-0000-0000-0000-000000000001'
);

set local role authenticated;
set local request.jwt.claim.sub = '9c100000-0000-0000-0000-000000000001';

insert into public.customer_ledger_entries (
  id,
  customer_id,
  customer_payment_id,
  entry_type,
  amount,
  note,
  created_by_user_id
)
values (
  '9c400000-0000-0000-0000-000000000001',
  '9c200000-0000-0000-0000-000000000001',
  '9c300000-0000-0000-0000-000000000001',
  'PAYMENT_CREDIT',
  150000,
  'Customer ledger activity test credit',
  '9c100000-0000-0000-0000-000000000001'
);

reset role;

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_type = 'CUSTOMER_LEDGER_ENTRY'
      and linked_entity_id = '9c400000-0000-0000-0000-000000000001'
  ),
  1::bigint,
  'customer-ledger-entry insertion appends one activity record'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '9c400000-0000-0000-0000-000000000001'
      and action_type = 'CUSTOMER_LEDGER_ENTRY_CREATED'
      and before_data is null
      and after_data ->> 'entry_type' = 'PAYMENT_CREDIT'
      and (after_data ->> 'amount')::numeric = 150000
      and after_data ->> 'note' = 'Customer ledger activity test credit'
  ),
  1::bigint,
  'customer-ledger-entry creation captures the complete post-insert business snapshot'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '9c400000-0000-0000-0000-000000000001'
      and actor_user_id = '9c100000-0000-0000-0000-000000000001'
      and event_source = 'USER'
  ),
  1::bigint,
  'customer-ledger-entry activity binds authenticated actor identity and USER source'
);

select results_eq(
  $$
    select count(*)::bigint
    from public.activity_logs
    where linked_entity_id = '9c400000-0000-0000-0000-000000000001'
      and metadata ->> 'table_name' = 'customer_ledger_entries'
      and metadata ->> 'schema_name' = 'public'
      and metadata ->> 'operation' = 'INSERT'
      and metadata ->> 'entry_type' = 'PAYMENT_CREDIT'
      and metadata ->> 'customer_id' = '9c200000-0000-0000-0000-000000000001'
      and metadata ->> 'customer_payment_id' = '9c300000-0000-0000-0000-000000000001'
  $$,
  array[1::bigint],
  'customer-ledger-entry activity metadata preserves database source and payment linkage'
);

select results_eq(
  $$
    select count(*)::bigint
    from public.activity_logs
    where linked_entity_id = '9c400000-0000-0000-0000-000000000001'
      and metadata -> 'sales_order_id' = 'null'::jsonb
  $$,
  array[1::bigint],
  'customer-ledger-entry activity metadata explicitly preserves absent optional sales-order linkage'
);

select * from finish();
rollback;
