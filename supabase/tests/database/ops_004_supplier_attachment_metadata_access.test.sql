begin;

create extension if not exists pgtap with schema extensions;

select plan(9);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'public'
      and tablename = 'attachments'
      and policyname = 'attachments_select_supplier_operational_roles'
      and cmd = 'SELECT'
  $$,
  array[1::bigint],
  'OPS-004 installs supplier attachment metadata SELECT policy'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'public'
      and tablename = 'attachments'
      and policyname = 'attachments_select_supplier_operational_roles'
      and qual like '%ACCOUNTING%'
      and qual like '%WAREHOUSE%'
      and qual like '%SUPPLIER%'
      and qual like '%GENERAL%'
      and qual like '%DOCUMENT%'
      and qual like '%ops-attachments%'
  $$,
  array[1::bigint],
  'supplier attachment SELECT policy is limited to authorized operational roles and document kinds'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'public'
      and tablename = 'attachments'
      and policyname like '%supplier%'
      and cmd = 'INSERT'
  $$,
  array[0::bigint],
  'bounded supplier metadata unit adds no non-owner supplier INSERT policy'
);

insert into auth.users (id, email)
values
  ('9f000000-0000-0000-0000-000000000001', 'ops-supplier-attachment-owner@example.test'),
  ('9f000000-0000-0000-0000-000000000002', 'ops-supplier-attachment-accounting@example.test'),
  ('9f000000-0000-0000-0000-000000000003', 'ops-supplier-attachment-warehouse@example.test'),
  ('9f000000-0000-0000-0000-000000000004', 'ops-supplier-attachment-sales@example.test'),
  ('9f000000-0000-0000-0000-000000000005', 'ops-supplier-attachment-production@example.test');

insert into public.user_roles (user_id, role_id, assigned_by)
select x.user_id, r.id, '9f000000-0000-0000-0000-000000000001'::uuid
from (
  values
    ('9f000000-0000-0000-0000-000000000001'::uuid, 'OWNER_ADMIN'::text),
    ('9f000000-0000-0000-0000-000000000002'::uuid, 'ACCOUNTING'::text),
    ('9f000000-0000-0000-0000-000000000003'::uuid, 'WAREHOUSE'::text),
    ('9f000000-0000-0000-0000-000000000004'::uuid, 'SALES'::text),
    ('9f000000-0000-0000-0000-000000000005'::uuid, 'PRINTER_PRODUCTION'::text)
) as x(user_id, role_code)
join public.roles r on r.code = x.role_code;

insert into public.suppliers (
  id,
  supplier_code,
  supplier_name
)
values (
  '9f100000-0000-0000-0000-000000000001',
  'SUPPLIER-ATTACHMENT-001',
  'Supplier Attachment Test'
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
    '9f200000-0000-0000-0000-000000000001',
    'SUPPLIER',
    '9f100000-0000-0000-0000-000000000001',
    'GENERAL',
    'ops-attachments',
    'suppliers/9f100000-0000-0000-0000-000000000001/general-note.txt',
    'general-note.txt',
    '9f000000-0000-0000-0000-000000000001'
  ),
  (
    '9f200000-0000-0000-0000-000000000002',
    'SUPPLIER',
    '9f100000-0000-0000-0000-000000000001',
    'DOCUMENT',
    'ops-attachments',
    'suppliers/9f100000-0000-0000-0000-000000000001/supplier-document.pdf',
    'supplier-document.pdf',
    '9f000000-0000-0000-0000-000000000001'
  ),
  (
    '9f200000-0000-0000-0000-000000000003',
    'SUPPLIER',
    '9f100000-0000-0000-0000-000000000001',
    'PAYMENT_EVIDENCE',
    'ops-attachments',
    'suppliers/9f100000-0000-0000-0000-000000000001/hidden-payment.pdf',
    'hidden-payment.pdf',
    '9f000000-0000-0000-0000-000000000001'
  );

set local role authenticated;
set local request.jwt.claim.sub = '9f000000-0000-0000-0000-000000000002';

select is(
  (select count(*) from public.attachments),
  2::bigint,
  'ACCOUNTING sees only GENERAL/DOCUMENT supplier attachment metadata'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '9f000000-0000-0000-0000-000000000003';

select is(
  (select count(*) from public.attachments),
  2::bigint,
  'WAREHOUSE sees only GENERAL/DOCUMENT supplier attachment metadata'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '9f000000-0000-0000-0000-000000000004';

select is(
  (select count(*) from public.attachments),
  0::bigint,
  'SALES receives no supplier attachment metadata access'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '9f000000-0000-0000-0000-000000000005';

select is(
  (select count(*) from public.attachments),
  0::bigint,
  'PRINTER_PRODUCTION receives no supplier attachment metadata access'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '9f000000-0000-0000-0000-000000000001';

select is(
  (
    select count(*)
    from public.attachments
    where linked_entity_type = 'SUPPLIER'
      and linked_entity_id = '9f100000-0000-0000-0000-000000000001'
  ),
  3::bigint,
  'OWNER_ADMIN retains full supplier attachment metadata visibility'
);

reset role;

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'public'
      and tablename = 'attachments'
      and policyname = 'attachments_select_supplier_operational_roles'
      and cmd in ('UPDATE', 'DELETE')
  $$,
  array[0::bigint],
  'bounded supplier metadata unit adds no UPDATE/DELETE policy'
);

select * from finish();
rollback;
