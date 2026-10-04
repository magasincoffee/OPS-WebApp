begin;

create extension if not exists pgtap with schema extensions;

select plan(11);

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
      and policyname = 'ops_purchase_order_attachments_select'
      and cmd = 'SELECT'
  $$,
  array[1::bigint],
  'OPS-004 installs purchase-order Storage SELECT policy'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'ops_purchase_order_attachments_insert'
      and cmd = 'INSERT'
  $$,
  array[1::bigint],
  'OPS-004 installs purchase-order Storage INSERT policy'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'ops_purchase_order_attachments_select'
      and qual like '%PURCHASE_ORDER%'
      and qual like '%DOCUMENT%'
      and qual like '%PAYMENT_EVIDENCE%'
      and qual like '%ACCOUNTING%'
      and qual like '%OWNER_ADMIN%'
  $$,
  array[1::bigint],
  'purchase-order Storage SELECT policy is limited to document/payment evidence for authorized roles'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'ops_purchase_order_attachments_insert'
      and with_check like '%PURCHASE_ORDER%'
      and with_check like '%DOCUMENT%'
      and with_check like '%PAYMENT_EVIDENCE%'
      and with_check like '%OWNER_ADMIN%'
      and with_check not like '%ACCOUNTING%'
  $$,
  array[1::bigint],
  'purchase-order Storage INSERT policy remains OWNER_ADMIN-only'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname in (
        'ops_purchase_order_attachments_select',
        'ops_purchase_order_attachments_insert'
      )
      and cmd in ('UPDATE', 'DELETE')
  $$,
  array[0::bigint],
  'bounded purchase-order Storage unit does not grant authenticated update/delete or upsert capability'
);

insert into auth.users (id, email)
values
  ('9b000000-0000-0000-0000-000000000001', 'ops-po-storage-owner@example.test'),
  ('9b000000-0000-0000-0000-000000000002', 'ops-po-storage-accounting@example.test'),
  ('9b000000-0000-0000-0000-000000000003', 'ops-po-storage-warehouse@example.test');

insert into public.user_roles (user_id, role_id, assigned_by)
select x.user_id, r.id, '9b000000-0000-0000-0000-000000000001'::uuid
from (
  values
    ('9b000000-0000-0000-0000-000000000001'::uuid, 'OWNER_ADMIN'::text),
    ('9b000000-0000-0000-0000-000000000002'::uuid, 'ACCOUNTING'::text),
    ('9b000000-0000-0000-0000-000000000003'::uuid, 'WAREHOUSE'::text)
) as x(user_id, role_code)
join public.roles r on r.code = x.role_code;

insert into public.suppliers (
  id,
  supplier_code,
  supplier_name
)
values (
  '9b100000-0000-0000-0000-000000000001',
  'PO-STORAGE-SUPPLIER',
  'Purchase Order Storage Supplier'
);

insert into public.purchase_orders (
  id,
  po_number,
  supplier_id,
  responsible_user_id,
  payment_note,
  document_reference
)
values (
  '9b200000-0000-0000-0000-000000000001',
  'PO-STORAGE-001',
  '9b100000-0000-0000-0000-000000000001',
  '9b000000-0000-0000-0000-000000000001',
  'Supplier paid immediately',
  'DOC-PO-STORAGE-001'
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
    '9b300000-0000-0000-0000-000000000001',
    'PURCHASE_ORDER',
    '9b200000-0000-0000-0000-000000000001',
    'DOCUMENT',
    'ops-attachments',
    'purchase-orders/9b200000-0000-0000-0000-000000000001/document-1.pdf',
    'document-1.pdf',
    '9b000000-0000-0000-0000-000000000001'
  ),
  (
    '9b300000-0000-0000-0000-000000000002',
    'PURCHASE_ORDER',
    '9b200000-0000-0000-0000-000000000001',
    'PAYMENT_EVIDENCE',
    'ops-attachments',
    'purchase-orders/9b200000-0000-0000-0000-000000000001/payment-evidence.pdf',
    'payment-evidence.pdf',
    '9b000000-0000-0000-0000-000000000001'
  ),
  (
    '9b300000-0000-0000-0000-000000000003',
    'PURCHASE_ORDER',
    '9b200000-0000-0000-0000-000000000001',
    'ARTWORK',
    'ops-attachments',
    'purchase-orders/9b200000-0000-0000-0000-000000000001/artwork.pdf',
    'artwork.pdf',
    '9b000000-0000-0000-0000-000000000001'
  ),
  (
    '9b300000-0000-0000-0000-000000000004',
    'PURCHASE_ORDER',
    '9b200000-0000-0000-0000-000000000001',
    'DOCUMENT',
    'ops-attachments',
    'purchase-orders/9b200000-0000-0000-0000-000000000001/document-2.pdf',
    'document-2.pdf',
    '9b000000-0000-0000-0000-000000000001'
  );

insert into storage.objects (bucket_id, name, owner_id)
values
  (
    'ops-attachments',
    'purchase-orders/9b200000-0000-0000-0000-000000000001/document-1.pdf',
    '9b000000-0000-0000-0000-000000000001'
  ),
  (
    'ops-attachments',
    'purchase-orders/9b200000-0000-0000-0000-000000000001/payment-evidence.pdf',
    '9b000000-0000-0000-0000-000000000001'
  ),
  (
    'ops-attachments',
    'purchase-orders/9b200000-0000-0000-0000-000000000001/artwork.pdf',
    '9b000000-0000-0000-0000-000000000001'
  );

set local role authenticated;
set local request.jwt.claim.sub = '9b000000-0000-0000-0000-000000000002';

select is(
  (
    select count(*)
    from storage.objects
    where bucket_id = 'ops-attachments'
  ),
  2::bigint,
  'ACCOUNTING sees only purchase-order document and payment-evidence binary objects'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '9b000000-0000-0000-0000-000000000003';

select is(
  (
    select count(*)
    from storage.objects
    where bucket_id = 'ops-attachments'
  ),
  0::bigint,
  'WAREHOUSE receives no direct purchase-order binary-object access'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '9b000000-0000-0000-0000-000000000001';

select is(
  (
    select count(*)
    from storage.objects
    where bucket_id = 'ops-attachments'
  ),
  2::bigint,
  'OWNER_ADMIN sees only authorized purchase-order document/payment-evidence objects'
);

select lives_ok(
  $$
    insert into storage.objects (bucket_id, name, owner_id)
    values (
      'ops-attachments',
      'purchase-orders/9b200000-0000-0000-0000-000000000001/document-2.pdf',
      '9b000000-0000-0000-0000-000000000001'
    )
    returning id
  $$,
  'OWNER_ADMIN can upload a pre-authorized purchase-order document object'
);

select is(
  (
    select count(*)
    from storage.objects
    where bucket_id = 'ops-attachments'
      and name = 'purchase-orders/9b200000-0000-0000-0000-000000000001/document-2.pdf'
  ),
  1::bigint,
  'new purchase-order document object is readable after OWNER_ADMIN upload'
);

reset role;

select * from finish();
rollback;
