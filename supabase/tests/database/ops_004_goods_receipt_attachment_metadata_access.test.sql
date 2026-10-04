begin;

create extension if not exists pgtap with schema extensions;

select plan(9);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'public'
      and tablename = 'attachments'
      and policyname = 'attachments_select_goods_receipt_operational_roles'
      and cmd = 'SELECT'
  $$,
  array[1::bigint],
  'OPS-004 installs goods-receipt attachment metadata SELECT policy'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'public'
      and tablename = 'attachments'
      and policyname = 'attachments_insert_goods_receipt_warehouse_document'
      and cmd = 'INSERT'
  $$,
  array[1::bigint],
  'OPS-004 installs goods-receipt attachment metadata INSERT policy'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'public'
      and tablename = 'attachments'
      and policyname = 'attachments_select_goods_receipt_operational_roles'
      and qual like '%WAREHOUSE%'
      and qual like '%ACCOUNTING%'
      and qual like '%GOODS_RECEIPT%'
      and qual like '%DOCUMENT%'
      and qual like '%ops-attachments%'
  $$,
  array[1::bigint],
  'goods-receipt attachment SELECT policy is limited to operational document metadata'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'public'
      and tablename = 'attachments'
      and policyname = 'attachments_insert_goods_receipt_warehouse_document'
      and with_check like '%WAREHOUSE%'
      and with_check like '%GOODS_RECEIPT%'
      and with_check like '%DOCUMENT%'
      and with_check like '%ops-attachments%'
      and with_check like '%uploaded_by_user_id%'
  $$,
  array[1::bigint],
  'goods-receipt attachment INSERT policy requires self-attributed WAREHOUSE document metadata'
);

insert into auth.users (id, email)
values
  ('9a000000-0000-0000-0000-000000000001', 'ops-gr-attachment-owner@example.test'),
  ('9a000000-0000-0000-0000-000000000002', 'ops-gr-attachment-warehouse@example.test'),
  ('9a000000-0000-0000-0000-000000000003', 'ops-gr-attachment-accounting@example.test'),
  ('9a000000-0000-0000-0000-000000000004', 'ops-gr-attachment-sales@example.test');

insert into public.user_roles (user_id, role_id, assigned_by)
select x.user_id, r.id, '9a000000-0000-0000-0000-000000000001'::uuid
from (
  values
    ('9a000000-0000-0000-0000-000000000001'::uuid, 'OWNER_ADMIN'::text),
    ('9a000000-0000-0000-0000-000000000002'::uuid, 'WAREHOUSE'::text),
    ('9a000000-0000-0000-0000-000000000003'::uuid, 'ACCOUNTING'::text),
    ('9a000000-0000-0000-0000-000000000004'::uuid, 'SALES'::text)
) as x(user_id, role_code)
join public.roles r on r.code = x.role_code;

insert into public.suppliers (
  id,
  supplier_code,
  supplier_name
)
values (
  '9a100000-0000-0000-0000-000000000001',
  'GR-ATTACHMENT-SUPPLIER',
  'Goods Receipt Attachment Supplier'
);

insert into public.purchase_orders (
  id,
  po_number,
  supplier_id,
  responsible_user_id
)
values (
  '9a200000-0000-0000-0000-000000000001',
  'PO-GR-ATTACHMENT-001',
  '9a100000-0000-0000-0000-000000000001',
  '9a000000-0000-0000-0000-000000000001'
);

insert into public.goods_receipts (
  id,
  goods_receipt_number,
  purchase_order_id,
  received_by_user_id,
  document_reference
)
values (
  '9a300000-0000-0000-0000-000000000001',
  'GR-ATTACHMENT-001',
  '9a200000-0000-0000-0000-000000000001',
  '9a000000-0000-0000-0000-000000000002',
  'GR-DOC-001'
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
    '9a400000-0000-0000-0000-000000000001',
    'GOODS_RECEIPT',
    '9a300000-0000-0000-0000-000000000001',
    'DOCUMENT',
    'ops-attachments',
    'goods-receipts/9a300000-0000-0000-0000-000000000001/document.pdf',
    'goods-receipt.pdf',
    '9a000000-0000-0000-0000-000000000001'
  ),
  (
    '9a400000-0000-0000-0000-000000000002',
    'GOODS_RECEIPT',
    '9a300000-0000-0000-0000-000000000001',
    'PAYMENT_EVIDENCE',
    'ops-attachments',
    'goods-receipts/9a300000-0000-0000-0000-000000000001/payment-evidence.pdf',
    'payment-evidence.pdf',
    '9a000000-0000-0000-0000-000000000001'
  );

set local role authenticated;
set local request.jwt.claim.sub = '9a000000-0000-0000-0000-000000000002';

select is(
  (select count(*) from public.attachments),
  1::bigint,
  'WAREHOUSE sees only DOCUMENT metadata linked to goods receipts'
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
  '9a400000-0000-0000-0000-000000000003',
  'GOODS_RECEIPT',
  '9a300000-0000-0000-0000-000000000001',
  'DOCUMENT',
  'ops-attachments',
  'goods-receipts/9a300000-0000-0000-0000-000000000001/warehouse-document.pdf',
  'warehouse-document.pdf',
  '9a000000-0000-0000-0000-000000000002'
);

select is(
  (select count(*) from public.attachments),
  2::bigint,
  'WAREHOUSE can add and read self-attributed goods-receipt document metadata'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '9a000000-0000-0000-0000-000000000003';

select is(
  (select count(*) from public.attachments),
  2::bigint,
  'ACCOUNTING can read goods-receipt document metadata'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '9a000000-0000-0000-0000-000000000004';

select is(
  (select count(*) from public.attachments),
  0::bigint,
  'SALES receives no goods-receipt attachment metadata access'
);

reset role;

select is(
  (
    select count(*)
    from public.attachments
    where linked_entity_type = 'GOODS_RECEIPT'
      and linked_entity_id = '9a300000-0000-0000-0000-000000000001'
  ),
  3::bigint,
  'privileged view confirms restricted goods-receipt attachment rows remain present'
);

select * from finish();
rollback;
