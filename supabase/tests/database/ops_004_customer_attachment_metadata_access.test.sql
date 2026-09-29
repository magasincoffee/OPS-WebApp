begin;

create extension if not exists pgtap with schema extensions;

select plan(10);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'public'
      and tablename = 'attachments'
      and policyname = 'attachments_select_customer_business_roles'
      and cmd = 'SELECT'
  $$,
  array[1::bigint],
  'OPS-004 installs customer attachment metadata SELECT policy'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'public'
      and tablename = 'attachments'
      and policyname = 'attachments_insert_customer_sales_documents'
      and cmd = 'INSERT'
  $$,
  array[1::bigint],
  'OPS-004 installs customer attachment metadata INSERT policy'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'public'
      and tablename = 'attachments'
      and policyname = 'attachments_select_customer_business_roles'
      and qual like '%SALES%'
      and qual like '%ACCOUNTING%'
      and qual like '%CUSTOMER%'
      and qual like '%GENERAL%'
      and qual like '%DOCUMENT%'
      and qual like '%ops-attachments%'
  $$,
  array[1::bigint],
  'customer attachment SELECT policy is limited to business-role customer documents'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'public'
      and tablename = 'attachments'
      and policyname = 'attachments_insert_customer_sales_documents'
      and with_check like '%SALES%'
      and with_check like '%CUSTOMER%'
      and with_check like '%GENERAL%'
      and with_check like '%DOCUMENT%'
      and with_check like '%ops-attachments%'
      and with_check like '%uploaded_by_user_id%'
  $$,
  array[1::bigint],
  'customer attachment INSERT policy requires self-attributed SALES documents'
);

insert into auth.users (id, email)
values
  ('9c000000-0000-0000-0000-000000000001', 'ops-customer-attachment-owner@example.test'),
  ('9c000000-0000-0000-0000-000000000002', 'ops-customer-attachment-sales@example.test'),
  ('9c000000-0000-0000-0000-000000000003', 'ops-customer-attachment-accounting@example.test'),
  ('9c000000-0000-0000-0000-000000000004', 'ops-customer-attachment-warehouse@example.test'),
  ('9c000000-0000-0000-0000-000000000005', 'ops-customer-attachment-production@example.test');

insert into public.user_roles (user_id, role_id, assigned_by)
select x.user_id, r.id, '9c000000-0000-0000-0000-000000000001'::uuid
from (
  values
    ('9c000000-0000-0000-0000-000000000001'::uuid, 'OWNER_ADMIN'::text),
    ('9c000000-0000-0000-0000-000000000002'::uuid, 'SALES'::text),
    ('9c000000-0000-0000-0000-000000000003'::uuid, 'ACCOUNTING'::text),
    ('9c000000-0000-0000-0000-000000000004'::uuid, 'WAREHOUSE'::text),
    ('9c000000-0000-0000-0000-000000000005'::uuid, 'PRINTER_PRODUCTION'::text)
) as x(user_id, role_code)
join public.roles r on r.code = x.role_code;

insert into public.customers (
  id,
  customer_code,
  display_name
)
values (
  '9c100000-0000-0000-0000-000000000001',
  'CUSTOMER-ATTACHMENT-001',
  'Customer Attachment Test'
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
    '9c200000-0000-0000-0000-000000000001',
    'CUSTOMER',
    '9c100000-0000-0000-0000-000000000001',
    'GENERAL',
    'ops-attachments',
    'customers/9c100000-0000-0000-0000-000000000001/general-note.txt',
    'general-note.txt',
    '9c000000-0000-0000-0000-000000000001'
  ),
  (
    '9c200000-0000-0000-0000-000000000002',
    'CUSTOMER',
    '9c100000-0000-0000-0000-000000000001',
    'DOCUMENT',
    'ops-attachments',
    'customers/9c100000-0000-0000-0000-000000000001/customer-document.pdf',
    'customer-document.pdf',
    '9c000000-0000-0000-0000-000000000001'
  ),
  (
    '9c200000-0000-0000-0000-000000000003',
    'CUSTOMER',
    '9c100000-0000-0000-0000-000000000001',
    'ARTWORK',
    'ops-attachments',
    'customers/9c100000-0000-0000-0000-000000000001/hidden-artwork.png',
    'hidden-artwork.png',
    '9c000000-0000-0000-0000-000000000001'
  );

set local role authenticated;
set local request.jwt.claim.sub = '9c000000-0000-0000-0000-000000000002';

select is(
  (select count(*) from public.attachments),
  2::bigint,
  'SALES sees only GENERAL/DOCUMENT customer attachment metadata'
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
  '9c200000-0000-0000-0000-000000000004',
  'CUSTOMER',
  '9c100000-0000-0000-0000-000000000001',
  'DOCUMENT',
  'ops-attachments',
  'customers/9c100000-0000-0000-0000-000000000001/sales-document.pdf',
  'sales-document.pdf',
  '9c000000-0000-0000-0000-000000000002'
);

select is(
  (select count(*) from public.attachments),
  3::bigint,
  'SALES can add and read self-attributed customer document metadata'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '9c000000-0000-0000-0000-000000000003';

select is(
  (select count(*) from public.attachments),
  3::bigint,
  'ACCOUNTING can read customer GENERAL/DOCUMENT metadata'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '9c000000-0000-0000-0000-000000000004';

select is(
  (select count(*) from public.attachments),
  0::bigint,
  'WAREHOUSE receives no customer attachment metadata access'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '9c000000-0000-0000-0000-000000000005';

select is(
  (select count(*) from public.attachments),
  0::bigint,
  'PRINTER_PRODUCTION receives no customer attachment metadata access'
);

reset role;

select is(
  (
    select count(*)
    from public.attachments
    where linked_entity_type = 'CUSTOMER'
      and linked_entity_id = '9c100000-0000-0000-0000-000000000001'
  ),
  4::bigint,
  'privileged view confirms restricted customer attachment rows remain present'
);

select * from finish();
rollback;
