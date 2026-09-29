begin;

create extension if not exists pgtap with schema extensions;

select plan(6);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'public'
      and tablename = 'attachments'
      and policyname = 'attachments_select_purchase_order_accounting'
      and cmd = 'SELECT'
  $$,
  array[1::bigint],
  'OPS-004 installs purchase-order attachment metadata SELECT policy'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'public'
      and tablename = 'attachments'
      and policyname = 'attachments_select_purchase_order_accounting'
      and qual like '%ACCOUNTING%'
      and qual like '%PURCHASE_ORDER%'
      and qual like '%DOCUMENT%'
      and qual like '%PAYMENT_EVIDENCE%'
      and qual like '%ops-attachments%'
  $$,
  array[1::bigint],
  'purchase-order attachment SELECT policy is limited to accounting document/payment evidence'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'public'
      and tablename = 'attachments'
      and policyname like '%purchase_order%accounting%'
      and cmd in ('INSERT', 'UPDATE', 'DELETE')
  $$,
  array[0::bigint],
  'purchase-order accounting attachment access remains read-only'
);

insert into auth.users (id, email)
values
  ('99000000-0000-0000-0000-000000000001', 'ops-po-attachment-owner@example.test'),
  ('99000000-0000-0000-0000-000000000002', 'ops-po-attachment-accounting@example.test'),
  ('99000000-0000-0000-0000-000000000003', 'ops-po-attachment-warehouse@example.test');

insert into public.user_roles (user_id, role_id, assigned_by)
select x.user_id, r.id, '99000000-0000-0000-0000-000000000001'::uuid
from (
  values
    ('99000000-0000-0000-0000-000000000001'::uuid, 'OWNER_ADMIN'::text),
    ('99000000-0000-0000-0000-000000000002'::uuid, 'ACCOUNTING'::text),
    ('99000000-0000-0000-0000-000000000003'::uuid, 'WAREHOUSE'::text)
) as x(user_id, role_code)
join public.roles r on r.code = x.role_code;

insert into public.suppliers (
  id,
  supplier_code,
  supplier_name
)
values (
  '99100000-0000-0000-0000-000000000001',
  'PO-ATTACHMENT-SUPPLIER',
  'Purchase Order Attachment Supplier'
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
  '99200000-0000-0000-0000-000000000001',
  'PO-ATTACHMENT-001',
  '99100000-0000-0000-0000-000000000001',
  '99000000-0000-0000-0000-000000000001',
  'Supplier paid immediately',
  'DOC-PO-001'
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
    '99300000-0000-0000-0000-000000000001',
    'PURCHASE_ORDER',
    '99200000-0000-0000-0000-000000000001',
    'DOCUMENT',
    'ops-attachments',
    'purchase-orders/99200000-0000-0000-0000-000000000001/document.pdf',
    'purchase-order.pdf',
    '99000000-0000-0000-0000-000000000001'
  ),
  (
    '99300000-0000-0000-0000-000000000002',
    'PURCHASE_ORDER',
    '99200000-0000-0000-0000-000000000001',
    'PAYMENT_EVIDENCE',
    'ops-attachments',
    'purchase-orders/99200000-0000-0000-0000-000000000001/payment-evidence.pdf',
    'payment-evidence.pdf',
    '99000000-0000-0000-0000-000000000001'
  ),
  (
    '99300000-0000-0000-0000-000000000003',
    'PURCHASE_ORDER',
    '99200000-0000-0000-0000-000000000001',
    'ARTWORK',
    'ops-attachments',
    'purchase-orders/99200000-0000-0000-0000-000000000001/artwork.pdf',
    'artwork.pdf',
    '99000000-0000-0000-0000-000000000001'
  );

set local role authenticated;
set local request.jwt.claim.sub = '99000000-0000-0000-0000-000000000002';

select is(
  (select count(*) from public.attachments),
  2::bigint,
  'ACCOUNTING sees only purchase-order document and payment-evidence metadata'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '99000000-0000-0000-0000-000000000003';

select is(
  (select count(*) from public.attachments),
  0::bigint,
  'WAREHOUSE receives no direct purchase-order attachment metadata access'
);

reset role;

select is(
  (
    select count(*)
    from public.attachments
    where linked_entity_type = 'PURCHASE_ORDER'
      and linked_entity_id = '99200000-0000-0000-0000-000000000001'
  ),
  3::bigint,
  'privileged view confirms restricted purchase-order attachment rows remain present'
);

select * from finish();
rollback;
