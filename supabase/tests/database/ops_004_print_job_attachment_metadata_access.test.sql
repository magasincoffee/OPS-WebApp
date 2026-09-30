begin;

create extension if not exists pgtap with schema extensions;

select plan(8);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'public'
      and tablename = 'attachments'
      and policyname = 'attachments_select_assigned_print_production'
      and cmd = 'SELECT'
  $$,
  array[1::bigint],
  'OPS-004 installs print-production attachment metadata SELECT policy'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'public'
      and tablename = 'attachments'
      and policyname = 'attachments_insert_assigned_print_production_evidence'
      and cmd = 'INSERT'
  $$,
  array[1::bigint],
  'OPS-004 installs print-production attachment metadata INSERT policy'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'public'
      and tablename = 'attachments'
      and policyname = 'attachments_select_assigned_print_production'
      and qual like '%ARTWORK%'
      and qual like '%PRODUCTION_EVIDENCE%'
      and qual like '%PRINTER_PRODUCTION%'
  $$,
  array[1::bigint],
  'production attachment SELECT policy is restricted to production-safe kinds'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'public'
      and tablename = 'attachments'
      and policyname = 'attachments_insert_assigned_print_production_evidence'
      and with_check like '%PRODUCTION_EVIDENCE%'
      and with_check like '%uploaded_by_user_id%'
      and with_check like '%PRINTER_PRODUCTION%'
  $$,
  array[1::bigint],
  'production attachment INSERT policy is limited to self-attributed production evidence'
);

insert into auth.users (id, email)
values
  ('95000000-0000-0000-0000-000000000001', 'ops-attachment-owner@example.test'),
  ('95000000-0000-0000-0000-000000000002', 'ops-attachment-production@example.test');

insert into public.user_roles (user_id, role_id, assigned_by)
select x.user_id, r.id, '95000000-0000-0000-0000-000000000001'::uuid
from (
  values
    ('95000000-0000-0000-0000-000000000001'::uuid, 'OWNER_ADMIN'::text),
    ('95000000-0000-0000-0000-000000000002'::uuid, 'PRINTER_PRODUCTION'::text)
) as x(user_id, role_code)
join public.roles r on r.code = x.role_code;

insert into public.customers (id, customer_code, display_name)
values (
  '95100000-0000-0000-0000-000000000001',
  'ATTACHMENT-CUSTOMER',
  'Attachment Customer'
);

insert into public.product_categories (id, category_code, name)
values (
  '95200000-0000-0000-0000-000000000001',
  'ATTACHMENT-CATEGORY',
  'Attachment Category'
);

insert into public.products (id, category_id, name, product_type)
values (
  '95300000-0000-0000-0000-000000000001',
  '95200000-0000-0000-0000-000000000001',
  'Attachment Product',
  'CUP'
);

insert into public.product_variants (
  id,
  product_id,
  sku_code,
  variant_name,
  base_inventory_unit
)
values (
  '95400000-0000-0000-0000-000000000001',
  '95300000-0000-0000-0000-000000000001',
  'ATTACHMENT-SKU',
  'Attachment Variant',
  'piece'
);

insert into public.sales_orders (
  id,
  order_number,
  customer_id,
  created_by_user_id,
  salesperson_user_id
)
values (
  '95500000-0000-0000-0000-000000000001',
  'SO-ATTACHMENT-001',
  '95100000-0000-0000-0000-000000000001',
  '95000000-0000-0000-0000-000000000001',
  '95000000-0000-0000-0000-000000000001'
);

insert into public.sales_order_items (
  id,
  sales_order_id,
  product_variant_id,
  sale_unit,
  sale_quantity,
  units_per_sale_unit,
  unit_price_per_sale_unit,
  print_mode,
  print_color_count,
  print_specification,
  requested_due_date
)
values (
  '95600000-0000-0000-0000-000000000001',
  '95500000-0000-0000-0000-000000000001',
  '95400000-0000-0000-0000-000000000001',
  'carton',
  1,
  1000,
  1000000,
  'PRINTED',
  2,
  'Two-color attachment access test',
  current_date + 1
);

-- OPS-032 requires the canonical DRAFT → line authoring → CONFIRMED branch before production.
update public.sales_orders
set order_status = 'CONFIRMED'
where id = '95500000-0000-0000-0000-000000000001';

insert into public.print_jobs (
  id,
  job_number,
  sales_order_id,
  sales_order_item_id,
  customer_id,
  product_variant_id,
  product_type_snapshot,
  quantity_base_units,
  print_color_count,
  print_specification,
  due_date,
  assignee_user_id,
  created_by_user_id
)
values
  (
    '95700000-0000-0000-0000-000000000001',
    'PJ-ATTACHMENT-ASSIGNED',
    '95500000-0000-0000-0000-000000000001',
    '95600000-0000-0000-0000-000000000001',
    '95100000-0000-0000-0000-000000000001',
    '95400000-0000-0000-0000-000000000001',
    'CUP',
    1000,
    2,
    'Assigned print job',
    current_date + 1,
    '95000000-0000-0000-0000-000000000002',
    '95000000-0000-0000-0000-000000000001'
  ),
  (
    '95700000-0000-0000-0000-000000000002',
    'PJ-ATTACHMENT-UNASSIGNED',
    '95500000-0000-0000-0000-000000000001',
    '95600000-0000-0000-0000-000000000001',
    '95100000-0000-0000-0000-000000000001',
    '95400000-0000-0000-0000-000000000001',
    'CUP',
    1000,
    2,
    'Unassigned print job',
    current_date + 1,
    '95000000-0000-0000-0000-000000000001',
    '95000000-0000-0000-0000-000000000001'
  );

insert into public.attachments (
  id,
  linked_entity_type,
  linked_entity_id,
  attachment_kind,
  storage_path,
  original_file_name,
  uploaded_by_user_id
)
values
  (
    '95800000-0000-0000-0000-000000000001',
    'PRINT_JOB',
    '95700000-0000-0000-0000-000000000001',
    'ARTWORK',
    'print-jobs/assigned/artwork.pdf',
    'artwork.pdf',
    '95000000-0000-0000-0000-000000000001'
  ),
  (
    '95800000-0000-0000-0000-000000000002',
    'PRINT_JOB',
    '95700000-0000-0000-0000-000000000001',
    'PAYMENT_EVIDENCE',
    'print-jobs/assigned/payment.pdf',
    'payment.pdf',
    '95000000-0000-0000-0000-000000000001'
  ),
  (
    '95800000-0000-0000-0000-000000000003',
    'PRINT_JOB',
    '95700000-0000-0000-0000-000000000002',
    'ARTWORK',
    'print-jobs/unassigned/artwork.pdf',
    'unassigned-artwork.pdf',
    '95000000-0000-0000-0000-000000000001'
  );

set local role authenticated;
set local request.jwt.claim.sub = '95000000-0000-0000-0000-000000000002';

select is(
  (select count(*) from public.attachments),
  1::bigint,
  'PRINTER_PRODUCTION sees only production-safe metadata for its assigned print job'
);

insert into public.attachments (
  id,
  linked_entity_type,
  linked_entity_id,
  attachment_kind,
  storage_path,
  original_file_name,
  uploaded_by_user_id
)
values (
  '95800000-0000-0000-0000-000000000004',
  'PRINT_JOB',
  '95700000-0000-0000-0000-000000000001',
  'PRODUCTION_EVIDENCE',
  'print-jobs/assigned/completion.jpg',
  'completion.jpg',
  '95000000-0000-0000-0000-000000000002'
);

select is(
  (select count(*) from public.attachments),
  2::bigint,
  'assigned PRINTER_PRODUCTION can add and then read production evidence metadata'
);

select is(
  (
    select count(*)
    from public.attachments
    where id = '95800000-0000-0000-0000-000000000004'
      and uploaded_by_user_id = auth.uid()
      and attachment_kind = 'PRODUCTION_EVIDENCE'
  ),
  1::bigint,
  'production evidence metadata is attributed to the authenticated production user'
);

reset role;

select is(
  (
    select count(*)
    from public.attachments
    where linked_entity_type = 'PRINT_JOB'
  ),
  4::bigint,
  'privileged view confirms restricted rows remain present rather than being deleted'
);

select * from finish();
rollback;
