begin;

create extension if not exists pgtap with schema extensions;

select plan(13);

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
      and policyname = 'ops_customer_attachments_select'
      and cmd = 'SELECT'
  $$,
  array[1::bigint],
  'OPS-004 installs customer Storage SELECT policy'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'ops_customer_attachments_insert'
      and cmd = 'INSERT'
  $$,
  array[1::bigint],
  'OPS-004 installs customer Storage INSERT policy'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'ops_customer_attachments_select'
      and qual like '%CUSTOMER%'
      and qual like '%GENERAL%'
      and qual like '%DOCUMENT%'
      and qual like '%OWNER_ADMIN%'
      and qual like '%SALES%'
      and qual like '%ACCOUNTING%'
  $$,
  array[1::bigint],
  'customer Storage SELECT policy is limited to authorized customer GENERAL/DOCUMENT objects'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'ops_customer_attachments_insert'
      and with_check like '%CUSTOMER%'
      and with_check like '%GENERAL%'
      and with_check like '%DOCUMENT%'
      and with_check like '%OWNER_ADMIN%'
      and with_check like '%SALES%'
      and with_check like '%uploaded_by_user_id%'
      and with_check not like '%ACCOUNTING%'
      and with_check not like '%WAREHOUSE%'
      and with_check not like '%PRINTER_PRODUCTION%'
  $$,
  array[1::bigint],
  'customer Storage INSERT policy allows OWNER_ADMIN or self-attributed SALES uploads only'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname in (
        'ops_customer_attachments_select',
        'ops_customer_attachments_insert'
      )
      and cmd in ('UPDATE', 'DELETE')
  $$,
  array[0::bigint],
  'bounded customer Storage unit does not grant authenticated update/delete or upsert capability'
);

insert into auth.users (id, email)
values
  ('9e000000-0000-0000-0000-000000000001', 'ops-customer-storage-owner@example.test'),
  ('9e000000-0000-0000-0000-000000000002', 'ops-customer-storage-sales@example.test'),
  ('9e000000-0000-0000-0000-000000000003', 'ops-customer-storage-accounting@example.test'),
  ('9e000000-0000-0000-0000-000000000004', 'ops-customer-storage-warehouse@example.test'),
  ('9e000000-0000-0000-0000-000000000005', 'ops-customer-storage-production@example.test');

insert into public.user_roles (user_id, role_id, assigned_by)
select x.user_id, r.id, '9e000000-0000-0000-0000-000000000001'::uuid
from (
  values
    ('9e000000-0000-0000-0000-000000000001'::uuid, 'OWNER_ADMIN'::text),
    ('9e000000-0000-0000-0000-000000000002'::uuid, 'SALES'::text),
    ('9e000000-0000-0000-0000-000000000003'::uuid, 'ACCOUNTING'::text),
    ('9e000000-0000-0000-0000-000000000004'::uuid, 'WAREHOUSE'::text),
    ('9e000000-0000-0000-0000-000000000005'::uuid, 'PRINTER_PRODUCTION'::text)
) as x(user_id, role_code)
join public.roles r on r.code = x.role_code;

insert into public.customers (
  id,
  customer_code,
  display_name
)
values (
  '9e100000-0000-0000-0000-000000000001',
  'CUSTOMER-STORAGE-001',
  'Customer Storage Test'
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
    '9e200000-0000-0000-0000-000000000001',
    'CUSTOMER',
    '9e100000-0000-0000-0000-000000000001',
    'GENERAL',
    'ops-attachments',
    'customers/9e100000-0000-0000-0000-000000000001/general-owner.txt',
    'general-owner.txt',
    '9e000000-0000-0000-0000-000000000001'
  ),
  (
    '9e200000-0000-0000-0000-000000000002',
    'CUSTOMER',
    '9e100000-0000-0000-0000-000000000001',
    'DOCUMENT',
    'ops-attachments',
    'customers/9e100000-0000-0000-0000-000000000001/document-owner.pdf',
    'document-owner.pdf',
    '9e000000-0000-0000-0000-000000000001'
  ),
  (
    '9e200000-0000-0000-0000-000000000003',
    'CUSTOMER',
    '9e100000-0000-0000-0000-000000000001',
    'ARTWORK',
    'ops-attachments',
    'customers/9e100000-0000-0000-0000-000000000001/hidden-artwork.png',
    'hidden-artwork.png',
    '9e000000-0000-0000-0000-000000000001'
  ),
  (
    '9e200000-0000-0000-0000-000000000004',
    'CUSTOMER',
    '9e100000-0000-0000-0000-000000000001',
    'DOCUMENT',
    'ops-attachments',
    'customers/9e100000-0000-0000-0000-000000000001/document-sales.pdf',
    'document-sales.pdf',
    '9e000000-0000-0000-0000-000000000002'
  );

insert into storage.objects (bucket_id, name, owner_id)
values
  (
    'ops-attachments',
    'customers/9e100000-0000-0000-0000-000000000001/general-owner.txt',
    '9e000000-0000-0000-0000-000000000001'
  ),
  (
    'ops-attachments',
    'customers/9e100000-0000-0000-0000-000000000001/document-owner.pdf',
    '9e000000-0000-0000-0000-000000000001'
  ),
  (
    'ops-attachments',
    'customers/9e100000-0000-0000-0000-000000000001/hidden-artwork.png',
    '9e000000-0000-0000-0000-000000000001'
  );

set local role authenticated;
set local request.jwt.claim.sub = '9e000000-0000-0000-0000-000000000002';

select is(
  (
    select count(*)
    from storage.objects
    where bucket_id = 'ops-attachments'
  ),
  2::bigint,
  'SALES sees only authorized customer GENERAL/DOCUMENT binary objects'
);

select lives_ok(
  $$
    insert into storage.objects (bucket_id, name, owner_id)
    values (
      'ops-attachments',
      'customers/9e100000-0000-0000-0000-000000000001/document-sales.pdf',
      '9e000000-0000-0000-0000-000000000002'
    )
    returning id
  $$,
  'SALES can upload a pre-authorized self-attributed customer document object'
);

select is(
  (
    select count(*)
    from storage.objects
    where bucket_id = 'ops-attachments'
      and name = 'customers/9e100000-0000-0000-0000-000000000001/document-sales.pdf'
  ),
  1::bigint,
  'new customer document object is readable after SALES upload'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '9e000000-0000-0000-0000-000000000003';

select is(
  (
    select count(*)
    from storage.objects
    where bucket_id = 'ops-attachments'
  ),
  3::bigint,
  'ACCOUNTING can read authorized customer GENERAL/DOCUMENT binary objects'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '9e000000-0000-0000-0000-000000000004';

select is(
  (
    select count(*)
    from storage.objects
    where bucket_id = 'ops-attachments'
  ),
  0::bigint,
  'WAREHOUSE receives no direct customer binary-object access'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '9e000000-0000-0000-0000-000000000005';

select is(
  (
    select count(*)
    from storage.objects
    where bucket_id = 'ops-attachments'
  ),
  0::bigint,
  'PRINTER_PRODUCTION receives no direct customer binary-object access'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '9e000000-0000-0000-0000-000000000001';

select is(
  (
    select count(*)
    from storage.objects
    where bucket_id = 'ops-attachments'
  ),
  3::bigint,
  'OWNER_ADMIN sees only authorized customer GENERAL/DOCUMENT objects'
);

reset role;

select * from finish();
rollback;
