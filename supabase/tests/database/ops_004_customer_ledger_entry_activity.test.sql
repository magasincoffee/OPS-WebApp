begin;

create extension if not exists pgtap with schema extensions;

select plan(8);

select results_eq(
  $$
    select count(*)::bigint
    from pg_trigger t
    join pg_class c on c.oid=t.tgrelid
    join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public'
      and c.relname='customer_ledger_entries'
      and t.tgname='customer_ledger_entries_capture_activity'
      and not t.tgisinternal
  $$,
  array[1::bigint],
  'OPS-004 installs one automatic customer-ledger-entry activity trigger'
);

select results_eq(
  $$
    select p.prosecdef
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public'
      and p.proname='capture_customer_ledger_entry_activity'
      and p.pronargs=0
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

insert into auth.users(id,email)
values('9c100000-0000-0000-0000-000000000001','ops-customer-ledger-activity-owner@example.test');

insert into public.user_roles(user_id,role_id)
select '9c100000-0000-0000-0000-000000000001'::uuid,r.id
from public.roles r
where r.code='OWNER_ADMIN';

insert into public.customers(id,customer_code,display_name)
values('9c200000-0000-0000-0000-000000000001','CL-ACTIVITY-001','Customer Ledger Activity Customer');

set local role authenticated;
set local request.jwt.claim.sub='9c100000-0000-0000-0000-000000000001';

insert into public.customer_payments(
  id,customer_id,amount,payment_method,reference,created_by_user_id
)
values(
  '9c300000-0000-0000-0000-000000000001',
  '9c200000-0000-0000-0000-000000000001',
  150000,'BANK_TRANSFER','CL-ACTIVITY-PAYMENT-001',
  '9c100000-0000-0000-0000-000000000001'
);

reset role;

select is(
  (
    select count(*)
    from public.activity_logs al
    join public.customer_ledger_entries cle on cle.id=al.linked_entity_id
    where al.linked_entity_type='CUSTOMER_LEDGER_ENTRY'
      and cle.customer_payment_id='9c300000-0000-0000-0000-000000000001'
  ),
  1::bigint,
  'automatic source-backed payment credit appends one customer-ledger-entry activity record'
);

select is(
  (
    select count(*)
    from public.activity_logs al
    join public.customer_ledger_entries cle on cle.id=al.linked_entity_id
    where cle.customer_payment_id='9c300000-0000-0000-0000-000000000001'
      and al.action_type='CUSTOMER_LEDGER_ENTRY_CREATED'
      and al.before_data is null
      and al.after_data->>'entry_type'='PAYMENT_CREDIT'
      and (al.after_data->>'amount')::numeric=150000
      and al.after_data->>'note'='Customer payment credit'
  ),
  1::bigint,
  'automatic customer-ledger credit captures the complete post-insert business snapshot'
);

select is(
  (
    select count(*)
    from public.activity_logs al
    join public.customer_ledger_entries cle on cle.id=al.linked_entity_id
    where cle.customer_payment_id='9c300000-0000-0000-0000-000000000001'
      and al.actor_user_id='9c100000-0000-0000-0000-000000000001'
      and al.event_source='USER'
  ),
  1::bigint,
  'automatic customer-ledger activity binds authenticated actor identity and USER source'
);

select results_eq(
  $$
    select count(*)::bigint
    from public.activity_logs al
    join public.customer_ledger_entries cle on cle.id=al.linked_entity_id
    where cle.customer_payment_id='9c300000-0000-0000-0000-000000000001'
      and al.metadata->>'table_name'='customer_ledger_entries'
      and al.metadata->>'schema_name'='public'
      and al.metadata->>'operation'='INSERT'
      and al.metadata->>'entry_type'='PAYMENT_CREDIT'
      and al.metadata->>'customer_id'='9c200000-0000-0000-0000-000000000001'
      and al.metadata->>'customer_payment_id'='9c300000-0000-0000-0000-000000000001'
  $$,
  array[1::bigint],
  'customer-ledger activity metadata preserves database source and payment linkage'
);

select results_eq(
  $$
    select count(*)::bigint
    from public.activity_logs al
    join public.customer_ledger_entries cle on cle.id=al.linked_entity_id
    where cle.customer_payment_id='9c300000-0000-0000-0000-000000000001'
      and al.metadata->'sales_order_id'='null'::jsonb
  $$,
  array[1::bigint],
  'customer-ledger activity metadata explicitly preserves absent optional sales-order linkage'
);

select * from finish();
rollback;
