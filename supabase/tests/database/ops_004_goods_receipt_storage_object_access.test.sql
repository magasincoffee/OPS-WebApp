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
      and policyname = 'ops_goods_receipt_attachments_select'
      and cmd = 'SELECT'
  $$,
  array[1::bigint],
  'OPS-004 installs goods-receipt Storage SELECT policy'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'ops_goods_receipt_attachments_insert'
      and cmd = 'INSERT'
  $$,
  array[1::bigint],
  'OPS-004 installs goods-receipt Storage INSERT policy'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'ops_goods_receipt_attachments_select'
      and qual like '%GOODS_RECEIPT%'
      and qual like '%DOCUMENT%'
      and qual like '%OWNER_ADMIN%'
      and qual like '%WAREHOUSE%'
      and qual like '%ACCOUNTING%'
  $$,
  array[1::bigint],
  'goods-receipt Storage SELECT policy is limited to document objects for authorized operational roles'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'ops_goods_receipt_attachments_insert'
      and with_check like '%GOODS_RECEIPT%'
      and with_check like '%DOCUMENT%'
      and with_check like '%OWNER_ADMIN%'
      and with_check like '%WAREHOUSE%'
      and with_check like '%uploaded_by_user_id%'
      and with_check not like '%ACCOUNTING%'
  $$,
  array[1::bigint],
  'goods-receipt Storage INSERT policy allows OWNER_ADMIN or self-attributed WAREHOUSE uploads only'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname in (
        'ops_goods_receipt_attachments_select',
        'ops_goods_receipt_attachments_insert'
      )
      and cmd in ('UPDATE', 'DELETE')
  $$,
  array[0::bigint],
  'bounded goods-receipt Storage unit does not grant authenticated update/delete or upsert capability'
);

insert into auth.users (id, email)
values
  ('9c000000-0000-0000-0000-000000000001', 'ops-gr-storage-owner@example.test'),
  ('9c000000-0000-0000-0000-000000000002', 'ops-gr-storage-warehouse@example.test'),
  ('9c000000-0000-0000-0000-000000000003', 'ops-gr-storage-accounting@example.test'),
  ('9c000000-0000-0000-0000-000000000004', 'ops-gr-storage-sales@example.test');

insert into public.user_roles (user_id, role_id, assigned_by)
select x.user_id, r.id, '9c000000-0000-0000-0000-000000000001'::uuid
from (
  values
    ('9c000000-0000-0000-0000-000000000001'::uuid, 'OWNER_ADMIN'::text),
    ('9c000000-0000-0000-0000-000000000002'::uuid, 'WAREHOUSE'::text),
    ('9c000000-0000-0000-0000-000000000003'::uuid, 'ACCOUNTING'::text),
    ('9c000000-0000-0000-0000-000000000004'::uuid, 'SALES'::text)
) as x(user_id, role_code)
join public.roles r on r.code = x.role_code;

insert into public.suppliers (
  id,
  supplier_code,
  supplier_name
)
values (
  '9c100000-0000-0000-0000-000000000001',
  'GR-STORAGE-SUPPLIER',
  'Goods Receipt Storage Supplier'
);

insert into public.purchase_orders (
  id,
  po_number,
  supplier_id,
  responsible_user_id
)
values (
  '9c200000-0000-0000-0000-000000000001',
  'PO-GR-STORAGE-001',
  '9c100000-0000-0000-0000-000000000001',
  '9c000000-0000-0000-0000-000000000001'
);

insert into public.goods_receipts (
  id,
  goods_receipt_number,
  purchase_order_id,
  received_by_user_id,
  document_reference
)
values (
  '9c300000-0000-0000-0000-000000000001',
  'GR-STORAGE-001',
  '9c200000-0000-0000-0000-000000000001',
  '9c000000-0000-0000-0000-000000000002',
  'GR-STORAGE-DOC-001'
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
    '9c400000-0000-0000-0000-000000000001',
    'GOODS_RECEIPT',
    '9c300000-0000-0000-0000-000000000001',
    'DOCUMENT',
    'ops-attachments',
    'goods-receipts/9c300000-0000-0000-0000-000000000001/document-1.pdf',
    'document-1.pdf',
    '9c000000-0000-0000-0000-000000000001'
  ),
  (
    '9c400000-0000-0000-0000-000000000002',
    'GOODS_RECEIPT',
    '9c300000-0000-0000-0000-000000000001',
    'PAYMENT_EVIDENCE',
    'ops-attachments',
    'goods-receipts/9c300000-0000-0000-0000-000000000001/payment-evidence.pdf',
    'payment-evidence.pdf',
    '9c000000-0000-0000-0000-000000000001'
  ),
  (
    '9c400000-0000-0000-0000-000000000003',
    'GOODS_RECEIPT',
    '9c300000-0000-0000-0000-000000000001',
    'DOCUMENT',
    'ops-attachments',
    'goods-receipts/9c300000-0000-0000-0000-000000000001/warehouse-document.pdf',
    'warehouse-document.pdf',
    '9c000000-0000-0000-0000-000000000002'
  );

insert into storage.objects (bucket_id, name, owner_id)
values
  (
    'ops-attachments',
    'goods-receipts/9c300000-0000-0000-0000-000000000001/document-1.pdf',
    '9c000000-0000-0000-0000-000000000001'
  ),
  (
    'ops-attachments',
    'goods-receipts/9c300000-0000-0000-0000-000000000001/payment-evidence.pdf',
    '9c000000-0000-0000-0000-000000000001'
  );

set local role authenticated;
set local request.jwt.claim.sub = '9c000000-0000-0000-0000-000000000002';

select is(
  (
    select count(*)
    from storage.objects
    where bucket_id = 'ops-attachments'
  ),
  1::bigint,
  'WAREHOUSE sees only goods-receipt document binary objects'
);

select lives_ok(
  $$
    insert into storage.objects (bucket_id, name, owner_id)
    values (
      'ops-attachments',
      'goods-receipts/9c300000-0000-0000-0000-000000000001/warehouse-document.pdf',
      '9c000000-0000-0000-0000-000000000002'
    )
    returning id
  $$,
  'WAREHOUSE can upload a pre-authorized self-attributed goods-receipt document object'
);

select is(
  (
    select count(*)
    from storage.objects
    where bucket_id = 'ops-attachments'
      and name = 'goods-receipts/9c300000-0000-0000-0000-000000000001/warehouse-document.pdf'
  ),
  1::bigint,
  'new goods-receipt document object is readable after WAREHOUSE upload'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '9c000000-0000-0000-0000-000000000003';

select is(
  (
    select count(*)
    from storage.objects
    where bucket_id = 'ops-attachments'
  ),
  2::bigint,
  'ACCOUNTING can read authorized goods-receipt document binary objects'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '9c000000-0000-0000-0000-000000000004';

select is(
  (
    select count(*)
    from storage.objects
    where bucket_id = 'ops-attachments'
  ),
  0::bigint,
  'SALES receives no direct goods-receipt binary-object access'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '9c000000-0000-0000-0000-000000000001';

select is(
  (
    select count(*)
    from storage.objects
    where bucket_id = 'ops-attachments'
  ),
  2::bigint,
  'OWNER_ADMIN sees only authorized goods-receipt document objects'
);

reset role;

select * from finish();
rollback;
