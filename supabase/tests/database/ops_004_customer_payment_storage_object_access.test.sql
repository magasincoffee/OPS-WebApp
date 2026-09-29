begin;

create extension if not exists pgtap with schema extensions;

select plan(10);

select is(
  (
    select public
    from storage.buckets
    where id = 'ops-attachments'
  ),
  false,
  'OPS-004 keeps ops-attachments as a private Storage bucket'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'ops_customer_payment_attachments_select'
      and cmd = 'SELECT'
  $$,
  array[1::bigint],
  'OPS-004 installs customer-payment Storage SELECT policy'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'ops_customer_payment_attachments_insert'
      and cmd = 'INSERT'
  $$,
  array[1::bigint],
  'OPS-004 installs customer-payment Storage INSERT policy'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'ops_customer_payment_attachments_select'
      and qual like '%CUSTOMER_PAYMENT%'
      and qual like '%PAYMENT_EVIDENCE%'
      and qual like '%ACCOUNTING%'
      and qual like '%OWNER_ADMIN%'
  $$,
  array[1::bigint],
  'customer-payment Storage SELECT policy is limited to payment evidence for authorized finance roles'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'ops_customer_payment_attachments_insert'
      and with_check like '%CUSTOMER_PAYMENT%'
      and with_check like '%PAYMENT_EVIDENCE%'
      and with_check like '%ACCOUNTING%'
      and with_check like '%uploaded_by_user_id%'
  $$,
  array[1::bigint],
  'customer-payment Storage INSERT policy requires self-attributed accounting evidence'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname in (
        'ops_customer_payment_attachments_select',
        'ops_customer_payment_attachments_insert'
      )
      and cmd in ('UPDATE', 'DELETE')
  $$,
  array[0::bigint],
  'bounded customer-payment Storage unit does not grant authenticated update/delete or upsert capability'
);

insert into auth.users (id, email)
values
  ('97000000-0000-0000-0000-000000000001', 'ops-payment-storage-owner@example.test'),
  ('97000000-0000-0000-0000-000000000002', 'ops-payment-storage-accounting@example.test'),
  ('97000000-0000-0000-0000-000000000003', 'ops-payment-storage-sales@example.test');

insert into public.user_roles (user_id, role_id, assigned_by)
select x.user_id, r.id, '97000000-0000-0000-0000-000000000001'::uuid
from (
  values
    ('97000000-0000-0000-0000-000000000001'::uuid, 'OWNER_ADMIN'::text),
    ('97000000-0000-0000-0000-000000000002'::uuid, 'ACCOUNTING'::text),
    ('97000000-0000-0000-0000-000000000003'::uuid, 'SALES'::text)
) as x(user_id, role_code)
join public.roles r on r.code = x.role_code;

insert into public.customers (id, customer_code, display_name)
values (
  '97100000-0000-0000-0000-000000000001',
  'PAYMENT-STORAGE-CUSTOMER',
  'Payment Storage Customer'
);

insert into public.customer_payments (
  id,
  customer_id,
  amount,
  payment_method,
  created_by_user_id
)
values (
  '97200000-0000-0000-0000-000000000001',
  '97100000-0000-0000-0000-000000000001',
  500000,
  'BANK_TRANSFER',
  '97000000-0000-0000-0000-000000000002'
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
    '97300000-0000-0000-0000-000000000001',
    'CUSTOMER_PAYMENT',
    '97200000-0000-0000-0000-000000000001',
    'PAYMENT_EVIDENCE',
    'ops-attachments',
    'customer-payments/97200000-0000-0000-0000-000000000001/evidence-1.pdf',
    'evidence-1.pdf',
    '97000000-0000-0000-0000-000000000001'
  ),
  (
    '97300000-0000-0000-0000-000000000002',
    'CUSTOMER_PAYMENT',
    '97200000-0000-0000-0000-000000000001',
    'DOCUMENT',
    'ops-attachments',
    'customer-payments/97200000-0000-0000-0000-000000000001/document.pdf',
    'document.pdf',
    '97000000-0000-0000-0000-000000000001'
  ),
  (
    '97300000-0000-0000-0000-000000000003',
    'CUSTOMER_PAYMENT',
    '97200000-0000-0000-0000-000000000001',
    'PAYMENT_EVIDENCE',
    'ops-attachments',
    'customer-payments/97200000-0000-0000-0000-000000000001/evidence-2.jpg',
    'evidence-2.jpg',
    '97000000-0000-0000-0000-000000000002'
  );

insert into storage.objects (bucket_id, name, owner_id)
values
  (
    'ops-attachments',
    'customer-payments/97200000-0000-0000-0000-000000000001/evidence-1.pdf',
    '97000000-0000-0000-0000-000000000001'
  ),
  (
    'ops-attachments',
    'customer-payments/97200000-0000-0000-0000-000000000001/document.pdf',
    '97000000-0000-0000-0000-000000000001'
  );

set local role authenticated;
set local request.jwt.claim.sub = '97000000-0000-0000-0000-000000000002';

select is(
  (
    select count(*)
    from storage.objects
    where bucket_id = 'ops-attachments'
  ),
  1::bigint,
  'ACCOUNTING sees only customer-payment evidence binary objects'
);

select lives_ok(
  $$
    insert into storage.objects (bucket_id, name, owner_id)
    values (
      'ops-attachments',
      'customer-payments/97200000-0000-0000-0000-000000000001/evidence-2.jpg',
      '97000000-0000-0000-0000-000000000002'
    )
    returning id
  $$,
  'ACCOUNTING can upload a pre-authorized self-attributed payment-evidence object'
);

select is(
  (
    select count(*)
    from storage.objects
    where bucket_id = 'ops-attachments'
      and name = 'customer-payments/97200000-0000-0000-0000-000000000001/evidence-2.jpg'
  ),
  1::bigint,
  'new payment-evidence object is readable after upload under the same RLS policy'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '97000000-0000-0000-0000-000000000003';

select is(
  (
    select count(*)
    from storage.objects
    where bucket_id = 'ops-attachments'
  ),
  0::bigint,
  'SALES receives no direct customer-payment evidence binary-object access'
);

reset role;

select * from finish();
rollback;
