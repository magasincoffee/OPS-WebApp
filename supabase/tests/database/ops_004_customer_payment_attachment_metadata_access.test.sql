begin;

create extension if not exists pgtap with schema extensions;

select plan(8);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'public'
      and tablename = 'attachments'
      and policyname = 'attachments_select_customer_payment_accounting'
      and cmd = 'SELECT'
  $$,
  array[1::bigint],
  'OPS-004 installs customer-payment attachment metadata SELECT policy'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'public'
      and tablename = 'attachments'
      and policyname = 'attachments_insert_customer_payment_accounting_evidence'
      and cmd = 'INSERT'
  $$,
  array[1::bigint],
  'OPS-004 installs customer-payment attachment metadata INSERT policy'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'public'
      and tablename = 'attachments'
      and policyname = 'attachments_select_customer_payment_accounting'
      and qual like '%ACCOUNTING%'
      and qual like '%CUSTOMER_PAYMENT%'
      and qual like '%PAYMENT_EVIDENCE%'
      and qual like '%ops-attachments%'
  $$,
  array[1::bigint],
  'customer-payment attachment SELECT policy is limited to accounting payment evidence'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'public'
      and tablename = 'attachments'
      and policyname = 'attachments_insert_customer_payment_accounting_evidence'
      and with_check like '%ACCOUNTING%'
      and with_check like '%CUSTOMER_PAYMENT%'
      and with_check like '%PAYMENT_EVIDENCE%'
      and with_check like '%ops-attachments%'
      and with_check like '%uploaded_by_user_id%'
  $$,
  array[1::bigint],
  'customer-payment attachment INSERT policy requires self-attributed accounting evidence'
);

insert into auth.users (id, email)
values
  ('96000000-0000-0000-0000-000000000001', 'ops-payment-attachment-owner@example.test'),
  ('96000000-0000-0000-0000-000000000002', 'ops-payment-attachment-accounting@example.test'),
  ('96000000-0000-0000-0000-000000000003', 'ops-payment-attachment-sales@example.test');

insert into public.user_roles (user_id, role_id, assigned_by)
select x.user_id, r.id, '96000000-0000-0000-0000-000000000001'::uuid
from (
  values
    ('96000000-0000-0000-0000-000000000001'::uuid, 'OWNER_ADMIN'::text),
    ('96000000-0000-0000-0000-000000000002'::uuid, 'ACCOUNTING'::text),
    ('96000000-0000-0000-0000-000000000003'::uuid, 'SALES'::text)
) as x(user_id, role_code)
join public.roles r on r.code = x.role_code;

insert into public.customers (id, customer_code, display_name)
values (
  '96100000-0000-0000-0000-000000000001',
  'PAYMENT-ATTACHMENT-CUSTOMER',
  'Payment Attachment Customer'
);

insert into public.customer_payments (
  id,
  customer_id,
  amount,
  payment_method,
  created_by_user_id
)
values (
  '96200000-0000-0000-0000-000000000001',
  '96100000-0000-0000-0000-000000000001',
  500000,
  'BANK_TRANSFER',
  '96000000-0000-0000-0000-000000000002'
);

insert into public.attachments (
  id,
  linked_entity_type,
  linked_entity_id,
  attachment_kind,
  storage_bucket,
  storage_path,
  original_file_name,
  uploaded_by_user_id
)
values
  (
    '96300000-0000-0000-0000-000000000001',
    'CUSTOMER_PAYMENT',
    '96200000-0000-0000-0000-000000000001',
    'PAYMENT_EVIDENCE',
    'ops-attachments',
    'customer-payments/96200000-0000-0000-0000-000000000001/evidence-1.pdf',
    'evidence-1.pdf',
    '96000000-0000-0000-0000-000000000001'
  ),
  (
    '96300000-0000-0000-0000-000000000002',
    'CUSTOMER_PAYMENT',
    '96200000-0000-0000-0000-000000000001',
    'DOCUMENT',
    'ops-attachments',
    'customer-payments/96200000-0000-0000-0000-000000000001/document.pdf',
    'document.pdf',
    '96000000-0000-0000-0000-000000000001'
  );

set local role authenticated;
set local request.jwt.claim.sub = '96000000-0000-0000-0000-000000000002';

select is(
  (select count(*) from public.attachments),
  1::bigint,
  'ACCOUNTING sees only payment-evidence metadata linked to customer payments'
);

insert into public.attachments (
  id,
  linked_entity_type,
  linked_entity_id,
  attachment_kind,
  storage_bucket,
  storage_path,
  original_file_name,
  uploaded_by_user_id
)
values (
  '96300000-0000-0000-0000-000000000003',
  'CUSTOMER_PAYMENT',
  '96200000-0000-0000-0000-000000000001',
  'PAYMENT_EVIDENCE',
  'ops-attachments',
  'customer-payments/96200000-0000-0000-0000-000000000001/evidence-2.jpg',
  'evidence-2.jpg',
  '96000000-0000-0000-0000-000000000002'
);

select is(
  (select count(*) from public.attachments),
  2::bigint,
  'ACCOUNTING can add and then read self-attributed customer-payment evidence metadata'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '96000000-0000-0000-0000-000000000003';

select is(
  (select count(*) from public.attachments),
  0::bigint,
  'SALES receives no direct customer-payment evidence metadata access'
);

reset role;

select is(
  (
    select count(*)
    from public.attachments
    where linked_entity_type = 'CUSTOMER_PAYMENT'
      and linked_entity_id = '96200000-0000-0000-0000-000000000001'
  ),
  3::bigint,
  'privileged view confirms restricted customer-payment attachment rows remain present'
);

select * from finish();
rollback;
