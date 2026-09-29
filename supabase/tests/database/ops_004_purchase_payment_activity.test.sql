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
      and c.relname = 'purchase_payments'
      and t.tgname = 'purchase_payments_capture_activity'
      and not t.tgisinternal
  $$,
  array[1::bigint],
  'OPS-004 installs one automatic purchase-payment activity trigger'
);

select results_eq(
  $$
    select p.prosecdef
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'capture_purchase_payment_activity'
      and p.pronargs = 0
  $$,
  array[true],
  'purchase-payment activity capture executes as SECURITY DEFINER'
);

select results_eq(
  $$
    select has_function_privilege(
      'authenticated',
      'public.capture_purchase_payment_activity()',
      'EXECUTE'
    )
  $$,
  array[false],
  'authenticated users cannot directly execute the purchase-payment audit trigger function'
);

insert into auth.users (id, email)
values (
  '98000000-0000-0000-0000-000000000001',
  'ops-purchase-payment-activity-owner@example.test'
);

insert into public.user_roles (user_id, role_id)
select
  '98000000-0000-0000-0000-000000000001'::uuid,
  r.id
from public.roles r
where r.code = 'OWNER_ADMIN';

insert into public.suppliers (
  id,
  supplier_code,
  supplier_name
)
values (
  '98100000-0000-0000-0000-000000000001',
  'PURCHASE-PAYMENT-ACTIVITY-SUPPLIER',
  'Purchase Payment Activity Supplier'
);

insert into public.purchase_orders (
  id,
  po_number,
  supplier_id,
  status,
  freight_amount,
  responsible_user_id,
  notes
)
values (
  '98200000-0000-0000-0000-000000000001',
  'PO-PAYMENT-ACTIVITY-001',
  '98100000-0000-0000-0000-000000000001',
  'ORDERED',
  0,
  '98000000-0000-0000-0000-000000000001',
  'OPS-004 purchase-payment activity test parent'
);

set local role authenticated;
set local request.jwt.claim.sub = '98000000-0000-0000-0000-000000000001';

insert into public.purchase_payments (
  id,
  purchase_order_id,
  amount,
  payment_method,
  reference,
  created_by_user_id,
  notes
)
values (
  '98300000-0000-0000-0000-000000000001',
  '98200000-0000-0000-0000-000000000001',
  1500000,
  'BANK_TRANSFER',
  'PAY-REF-001',
  '98000000-0000-0000-0000-000000000001',
  'Initial payment note'
);

update public.purchase_payments
set notes = 'Updated payment note'
where id = '98300000-0000-0000-0000-000000000001';

delete from public.purchase_payments
where id = '98300000-0000-0000-0000-000000000001';

reset role;

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_type = 'PURCHASE_PAYMENT'
      and linked_entity_id = '98300000-0000-0000-0000-000000000001'
  ),
  3::bigint,
  'create/update/delete each append one purchase-payment activity record'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '98300000-0000-0000-0000-000000000001'
      and action_type = 'PURCHASE_PAYMENT_CREATED'
      and before_data is null
      and after_data ->> 'reference' = 'PAY-REF-001'
      and (after_data ->> 'amount')::numeric = 1500000
  ),
  1::bigint,
  'purchase-payment creation captures the post-change snapshot'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '98300000-0000-0000-0000-000000000001'
      and action_type = 'PURCHASE_PAYMENT_UPDATED'
      and before_data ->> 'notes' = 'Initial payment note'
      and after_data ->> 'notes' = 'Updated payment note'
  ),
  1::bigint,
  'purchase-payment update captures before and after snapshots'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '98300000-0000-0000-0000-000000000001'
      and action_type = 'PURCHASE_PAYMENT_DELETED'
      and before_data ->> 'reference' = 'PAY-REF-001'
      and after_data is null
  ),
  1::bigint,
  'purchase-payment deletion captures the pre-delete snapshot'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '98300000-0000-0000-0000-000000000001'
      and actor_user_id = '98000000-0000-0000-0000-000000000001'
  ),
  3::bigint,
  'all purchase-payment activity rows bind actor identity to auth.uid()'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '98300000-0000-0000-0000-000000000001'
      and event_source = 'USER'
  ),
  3::bigint,
  'authenticated purchase-payment mutations are marked as USER events'
);

select results_eq(
  $$
    select count(*)::bigint
    from public.activity_logs
    where linked_entity_id = '98300000-0000-0000-0000-000000000001'
      and metadata ->> 'table_name' = 'purchase_payments'
      and metadata ->> 'schema_name' = 'public'
  $$,
  array[3::bigint],
  'purchase-payment activity metadata records its database source'
);

select results_eq(
  $$
    select count(*)::bigint
    from public.activity_logs
    where linked_entity_id = '98300000-0000-0000-0000-000000000001'
      and metadata ->> 'purchase_order_id' = '98200000-0000-0000-0000-000000000001'
  $$,
  array[3::bigint],
  'purchase-payment activity metadata preserves parent purchase-order linkage'
);

select * from finish();
rollback;
