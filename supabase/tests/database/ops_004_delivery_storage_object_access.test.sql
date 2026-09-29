begin;

create extension if not exists pgtap with schema extensions;

select plan(12);

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
      and policyname = 'ops_delivery_attachments_select'
      and cmd = 'SELECT'
  $$,
  array[1::bigint],
  'OPS-004 installs delivery Storage SELECT policy'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'ops_delivery_attachments_insert'
      and cmd = 'INSERT'
  $$,
  array[1::bigint],
  'OPS-004 installs delivery Storage INSERT policy'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'ops_delivery_attachments_select'
      and qual like '%DELIVERY%'
      and qual like '%DELIVERY_EVIDENCE%'
      and qual like '%OWNER_ADMIN%'
      and qual like '%WAREHOUSE%'
      and qual like '%SALES%'
  $$,
  array[1::bigint],
  'delivery Storage SELECT policy is limited to delivery-evidence objects for authorized operational roles'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'ops_delivery_attachments_insert'
      and with_check like '%DELIVERY%'
      and with_check like '%DELIVERY_EVIDENCE%'
      and with_check like '%OWNER_ADMIN%'
      and with_check like '%WAREHOUSE%'
      and with_check like '%uploaded_by_user_id%'
      and with_check not like '%SALES%'
      and with_check not like '%ACCOUNTING%'
  $$,
  array[1::bigint],
  'delivery Storage INSERT policy allows OWNER_ADMIN or self-attributed WAREHOUSE uploads only'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname in (
        'ops_delivery_attachments_select',
        'ops_delivery_attachments_insert'
      )
      and cmd in ('UPDATE', 'DELETE')
  $$,
  array[0::bigint],
  'bounded delivery Storage unit does not grant authenticated update/delete or upsert capability'
);

insert into auth.users (id, email)
values
  ('9d000000-0000-0000-0000-000000000001', 'ops-delivery-storage-owner@example.test'),
  ('9d000000-0000-0000-0000-000000000002', 'ops-delivery-storage-warehouse@example.test'),
  ('9d000000-0000-0000-0000-000000000003', 'ops-delivery-storage-sales@example.test'),
  ('9d000000-0000-0000-0000-000000000004', 'ops-delivery-storage-accounting@example.test');

insert into public.user_roles (user_id, role_id, assigned_by)
select x.user_id, r.id, '9d000000-0000-0000-0000-000000000001'::uuid
from (
  values
    ('9d000000-0000-0000-0000-000000000001'::uuid, 'OWNER_ADMIN'::text),
    ('9d000000-0000-0000-0000-000000000002'::uuid, 'WAREHOUSE'::text),
    ('9d000000-0000-0000-0000-000000000003'::uuid, 'SALES'::text),
    ('9d000000-0000-0000-0000-000000000004'::uuid, 'ACCOUNTING'::text)
) as x(user_id, role_code)
join public.roles r on r.code = x.role_code;

insert into public.customers (
  id,
  customer_code,
  display_name
)
values (
  '9d100000-0000-0000-0000-000000000001',
  'DELIVERY-STORAGE-CUSTOMER',
  'Delivery Storage Customer'
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
  '9d200000-0000-0000-0000-000000000001',
  'SO-DELIVERY-STORAGE-001',
  '9d100000-0000-0000-0000-000000000001',
  'CONFIRMED',
  '9d000000-0000-0000-0000-000000000001',
  'OPS-004 delivery storage parent order'
);

insert into public.deliveries (
  id,
  delivery_number,
  sales_order_id,
  status,
  consignee_name,
  created_by_user_id,
  notes
)
values (
  '9d300000-0000-0000-0000-000000000001',
  'DELIVERY-STORAGE-001',
  '9d200000-0000-0000-0000-000000000001',
  'READY_TO_SHIP',
  'Delivery Storage Consignee',
  '9d000000-0000-0000-0000-000000000002',
  'OPS-004 delivery storage test'
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
    '9d400000-0000-0000-0000-000000000001',
    'DELIVERY',
    '9d300000-0000-0000-0000-000000000001',
    'DELIVERY_EVIDENCE',
    'ops-attachments',
    'deliveries/9d300000-0000-0000-0000-000000000001/evidence-owner.jpg',
    'evidence-owner.jpg',
    '9d000000-0000-0000-0000-000000000001'
  ),
  (
    '9d400000-0000-0000-0000-000000000002',
    'DELIVERY',
    '9d300000-0000-0000-0000-000000000001',
    'GENERAL',
    'ops-attachments',
    'deliveries/9d300000-0000-0000-0000-000000000001/general-note.txt',
    'general-note.txt',
    '9d000000-0000-0000-0000-000000000001'
  ),
  (
    '9d400000-0000-0000-0000-000000000003',
    'DELIVERY',
    '9d300000-0000-0000-0000-000000000001',
    'DELIVERY_EVIDENCE',
    'ops-attachments',
    'deliveries/9d300000-0000-0000-0000-000000000001/evidence-warehouse.jpg',
    'evidence-warehouse.jpg',
    '9d000000-0000-0000-0000-000000000002'
  );

insert into storage.objects (bucket_id, name, owner_id)
values
  (
    'ops-attachments',
    'deliveries/9d300000-0000-0000-0000-000000000001/evidence-owner.jpg',
    '9d000000-0000-0000-0000-000000000001'
  ),
  (
    'ops-attachments',
    'deliveries/9d300000-0000-0000-0000-000000000001/general-note.txt',
    '9d000000-0000-0000-0000-000000000001'
  );

set local role authenticated;
set local request.jwt.claim.sub = '9d000000-0000-0000-0000-000000000002';

select is(
  (
    select count(*)
    from storage.objects
    where bucket_id = 'ops-attachments'
  ),
  1::bigint,
  'WAREHOUSE sees only delivery-evidence binary objects'
);

select lives_ok(
  $$
    insert into storage.objects (bucket_id, name, owner_id)
    values (
      'ops-attachments',
      'deliveries/9d300000-0000-0000-0000-000000000001/evidence-warehouse.jpg',
      '9d000000-0000-0000-0000-000000000002'
    )
    returning id
  $$,
  'WAREHOUSE can upload a pre-authorized self-attributed delivery-evidence object'
);

select is(
  (
    select count(*)
    from storage.objects
    where bucket_id = 'ops-attachments'
      and name = 'deliveries/9d300000-0000-0000-0000-000000000001/evidence-warehouse.jpg'
  ),
  1::bigint,
  'new delivery-evidence object is readable after WAREHOUSE upload'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '9d000000-0000-0000-0000-000000000003';

select is(
  (
    select count(*)
    from storage.objects
    where bucket_id = 'ops-attachments'
  ),
  2::bigint,
  'SALES can read authorized delivery-evidence binary objects'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '9d000000-0000-0000-0000-000000000004';

select is(
  (
    select count(*)
    from storage.objects
    where bucket_id = 'ops-attachments'
  ),
  0::bigint,
  'ACCOUNTING receives no direct delivery binary-object access'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '9d000000-0000-0000-0000-000000000001';

select is(
  (
    select count(*)
    from storage.objects
    where bucket_id = 'ops-attachments'
  ),
  2::bigint,
  'OWNER_ADMIN sees only authorized delivery-evidence objects'
);

reset role;

select * from finish();
rollback;
