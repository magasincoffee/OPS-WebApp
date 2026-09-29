begin;

create extension if not exists pgtap with schema extensions;

select plan(9);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'public'
      and tablename = 'attachments'
      and policyname = 'attachments_select_delivery_operational_roles'
      and cmd = 'SELECT'
  $$,
  array[1::bigint],
  'OPS-004 installs delivery attachment metadata SELECT policy'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'public'
      and tablename = 'attachments'
      and policyname = 'attachments_insert_delivery_warehouse_evidence'
      and cmd = 'INSERT'
  $$,
  array[1::bigint],
  'OPS-004 installs delivery attachment metadata INSERT policy'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'public'
      and tablename = 'attachments'
      and policyname = 'attachments_select_delivery_operational_roles'
      and qual like '%WAREHOUSE%'
      and qual like '%SALES%'
      and qual like '%DELIVERY%'
      and qual like '%DELIVERY_EVIDENCE%'
      and qual like '%ops-attachments%'
  $$,
  array[1::bigint],
  'delivery attachment SELECT policy is limited to operational delivery evidence metadata'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'public'
      and tablename = 'attachments'
      and policyname = 'attachments_insert_delivery_warehouse_evidence'
      and with_check like '%WAREHOUSE%'
      and with_check like '%DELIVERY%'
      and with_check like '%DELIVERY_EVIDENCE%'
      and with_check like '%ops-attachments%'
      and with_check like '%uploaded_by_user_id%'
  $$,
  array[1::bigint],
  'delivery attachment INSERT policy requires self-attributed WAREHOUSE evidence metadata'
);

insert into auth.users (id, email)
values
  ('9b000000-0000-0000-0000-000000000001', 'ops-delivery-attachment-owner@example.test'),
  ('9b000000-0000-0000-0000-000000000002', 'ops-delivery-attachment-warehouse@example.test'),
  ('9b000000-0000-0000-0000-000000000003', 'ops-delivery-attachment-sales@example.test'),
  ('9b000000-0000-0000-0000-000000000004', 'ops-delivery-attachment-accounting@example.test');

insert into public.user_roles (user_id, role_id, assigned_by)
select x.user_id, r.id, '9b000000-0000-0000-0000-000000000001'::uuid
from (
  values
    ('9b000000-0000-0000-0000-000000000001'::uuid, 'OWNER_ADMIN'::text),
    ('9b000000-0000-0000-0000-000000000002'::uuid, 'WAREHOUSE'::text),
    ('9b000000-0000-0000-0000-000000000003'::uuid, 'SALES'::text),
    ('9b000000-0000-0000-0000-000000000004'::uuid, 'ACCOUNTING'::text)
) as x(user_id, role_code)
join public.roles r on r.code = x.role_code;

insert into public.customers (
  id,
  customer_code,
  display_name
)
values (
  '9b100000-0000-0000-0000-000000000001',
  'DELIVERY-ATTACHMENT-CUSTOMER',
  'Delivery Attachment Customer'
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
  '9b200000-0000-0000-0000-000000000001',
  'SO-DELIVERY-ATTACHMENT-001',
  '9b100000-0000-0000-0000-000000000001',
  'CONFIRMED',
  '9b000000-0000-0000-0000-000000000001',
  'OPS-004 delivery attachment parent order'
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
  '9b300000-0000-0000-0000-000000000001',
  'DELIVERY-ATTACHMENT-001',
  '9b200000-0000-0000-0000-000000000001',
  'READY_TO_SHIP',
  'Delivery Attachment Consignee',
  '9b000000-0000-0000-0000-000000000002',
  'OPS-004 delivery attachment test'
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
    '9b400000-0000-0000-0000-000000000001',
    'DELIVERY',
    '9b300000-0000-0000-0000-000000000001',
    'DELIVERY_EVIDENCE',
    'ops-attachments',
    'deliveries/9b300000-0000-0000-0000-000000000001/delivery-evidence.jpg',
    'delivery-evidence.jpg',
    '9b000000-0000-0000-0000-000000000001'
  ),
  (
    '9b400000-0000-0000-0000-000000000002',
    'DELIVERY',
    '9b300000-0000-0000-0000-000000000001',
    'GENERAL',
    'ops-attachments',
    'deliveries/9b300000-0000-0000-0000-000000000001/general-note.txt',
    'general-note.txt',
    '9b000000-0000-0000-0000-000000000001'
  );

set local role authenticated;
set local request.jwt.claim.sub = '9b000000-0000-0000-0000-000000000002';

select is(
  (select count(*) from public.attachments),
  1::bigint,
  'WAREHOUSE sees only DELIVERY_EVIDENCE metadata linked to deliveries'
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
  '9b400000-0000-0000-0000-000000000003',
  'DELIVERY',
  '9b300000-0000-0000-0000-000000000001',
  'DELIVERY_EVIDENCE',
  'ops-attachments',
  'deliveries/9b300000-0000-0000-0000-000000000001/warehouse-delivery-evidence.jpg',
  'warehouse-delivery-evidence.jpg',
  '9b000000-0000-0000-0000-000000000002'
);

select is(
  (select count(*) from public.attachments),
  2::bigint,
  'WAREHOUSE can add and read self-attributed delivery evidence metadata'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '9b000000-0000-0000-0000-000000000003';

select is(
  (select count(*) from public.attachments),
  2::bigint,
  'SALES can read delivery evidence metadata for delivery follow-up'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '9b000000-0000-0000-0000-000000000004';

select is(
  (select count(*) from public.attachments),
  0::bigint,
  'ACCOUNTING receives no delivery attachment metadata access'
);

reset role;

select is(
  (
    select count(*)
    from public.attachments
    where linked_entity_type = 'DELIVERY'
      and linked_entity_id = '9b300000-0000-0000-0000-000000000001'
  ),
  3::bigint,
  'privileged view confirms restricted delivery attachment rows remain present'
);

select * from finish();
rollback;
