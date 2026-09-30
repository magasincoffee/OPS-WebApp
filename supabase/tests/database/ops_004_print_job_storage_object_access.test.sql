begin;

create extension if not exists pgtap with schema extensions;

select plan(9);

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
      and policyname = 'ops_print_job_attachments_select'
      and cmd = 'SELECT'
  $$,
  array[1::bigint],
  'OPS-004 installs print-job Storage SELECT policy'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'ops_print_job_attachments_insert'
      and cmd = 'INSERT'
  $$,
  array[1::bigint],
  'OPS-004 installs print-job Storage INSERT policy'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'ops_print_job_attachments_select'
      and qual like '%PRINT_JOB%'
      and qual like '%ARTWORK%'
      and qual like '%PRODUCTION_EVIDENCE%'
      and qual like '%PRINTER_PRODUCTION%'
  $$,
  array[1::bigint],
  'print-job Storage SELECT policy is limited to production-safe attachment kinds'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'ops_print_job_attachments_insert'
      and with_check like '%PRINT_JOB%'
      and with_check like '%PRODUCTION_EVIDENCE%'
      and with_check like '%uploaded_by_user_id%'
      and with_check like '%PRINTER_PRODUCTION%'
  $$,
  array[1::bigint],
  'print-job Storage INSERT policy requires self-attributed production evidence'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname in (
        'ops_print_job_attachments_select',
        'ops_print_job_attachments_insert'
      )
      and cmd in ('UPDATE', 'DELETE')
  $$,
  array[0::bigint],
  'bounded Storage unit does not grant authenticated update/delete or upsert capability'
);

insert into auth.users (id, email)
values
  ('96000000-0000-0000-0000-000000000001', 'ops-storage-owner@example.test'),
  ('96000000-0000-0000-0000-000000000002', 'ops-storage-production@example.test');

insert into public.user_roles (user_id, role_id, assigned_by)
select x.user_id, r.id, '96000000-0000-0000-0000-000000000001'::uuid
from (
  values
    ('96000000-0000-0000-0000-000000000001'::uuid, 'OWNER_ADMIN'::text),
    ('96000000-0000-0000-0000-000000000002'::uuid, 'PRINTER_PRODUCTION'::text)
) as x(user_id, role_code)
join public.roles r on r.code = x.role_code;

insert into public.customers (id, customer_code, display_name)
values (
  '96100000-0000-0000-0000-000000000001',
  'STORAGE-CUSTOMER',
  'Storage Customer'
);

insert into public.product_categories (id, category_code, name)
values (
  '96200000-0000-0000-0000-000000000001',
  'STORAGE-CATEGORY',
  'Storage Category'
);

insert into public.products (id, category_id, name, product_type)
values (
  '96300000-0000-0000-0000-000000000001',
  '96200000-0000-0000-0000-000000000001',
  'Storage Product',
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
  '96400000-0000-0000-0000-000000000001',
  '96300000-0000-0000-0000-000000000001',
  'STORAGE-SKU',
  'Storage Variant',
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
  '96500000-0000-0000-0000-000000000001',
  'SO-STORAGE-001',
  '96100000-0000-0000-0000-000000000001',
  '96000000-0000-0000-0000-000000000001',
  '96000000-0000-0000-0000-000000000001'
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
  '96600000-0000-0000-0000-000000000001',
  '96500000-0000-0000-0000-000000000001',
  '96400000-0000-0000-0000-000000000001',
  'carton',
  1,
  1000,
  1000000,
  'PRINTED',
  2,
  'Two-color Storage access test',
  current_date + 1
);

-- OPS-032 requires the canonical DRAFT → line authoring → CONFIRMED branch before production.

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
select
  '96600000-0000-0000-0000-000000000002'::uuid,
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
from public.sales_order_items
where id = '96600000-0000-0000-0000-000000000001';

update public.sales_orders
set order_status = 'CONFIRMED'
where id = '96500000-0000-0000-0000-000000000001';

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
    '96700000-0000-0000-0000-000000000001',
    'PJ-STORAGE-ASSIGNED',
    '96500000-0000-0000-0000-000000000001',
    '96600000-0000-0000-0000-000000000001',
    '96100000-0000-0000-0000-000000000001',
    '96400000-0000-0000-0000-000000000001',
    'CUP',
    1000,
    2,
    'Two-color Storage access test',
    current_date + 1,
    '96000000-0000-0000-0000-000000000002',
    '96000000-0000-0000-0000-000000000001'
  ),
  (
    '96700000-0000-0000-0000-000000000002',
    'PJ-STORAGE-UNASSIGNED',
    '96500000-0000-0000-0000-000000000001',
    '96600000-0000-0000-0000-000000000002',
    '96100000-0000-0000-0000-000000000001',
    '96400000-0000-0000-0000-000000000001',
    'CUP',
    1000,
    2,
    'Two-color Storage access test',
    current_date + 1,
    null,
    '96000000-0000-0000-0000-000000000001'
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
    '96800000-0000-0000-0000-000000000001',
    'PRINT_JOB',
    '96700000-0000-0000-0000-000000000001',
    'ARTWORK',
    'print-jobs/assigned/artwork.pdf',
    'artwork.pdf',
    '96000000-0000-0000-0000-000000000001'
  ),
  (
    '96800000-0000-0000-0000-000000000002',
    'PRINT_JOB',
    '96700000-0000-0000-0000-000000000001',
    'PAYMENT_EVIDENCE',
    'print-jobs/assigned/payment.pdf',
    'payment.pdf',
    '96000000-0000-0000-0000-000000000001'
  ),
  (
    '96800000-0000-0000-0000-000000000003',
    'PRINT_JOB',
    '96700000-0000-0000-0000-000000000002',
    'ARTWORK',
    'print-jobs/unassigned/artwork.pdf',
    'unassigned-artwork.pdf',
    '96000000-0000-0000-0000-000000000001'
  ),
  (
    '96800000-0000-0000-0000-000000000004',
    'PRINT_JOB',
    '96700000-0000-0000-0000-000000000001',
    'PRODUCTION_EVIDENCE',
    'print-jobs/assigned/completion.jpg',
    'completion.jpg',
    '96000000-0000-0000-0000-000000000002'
  );

insert into storage.objects (bucket_id, name, owner_id)
values
  ('ops-attachments', 'print-jobs/assigned/artwork.pdf', '96000000-0000-0000-0000-000000000001'),
  ('ops-attachments', 'print-jobs/assigned/payment.pdf', '96000000-0000-0000-0000-000000000001'),
  ('ops-attachments', 'print-jobs/unassigned/artwork.pdf', '96000000-0000-0000-0000-000000000001');

set local role authenticated;
set local request.jwt.claim.sub = '96000000-0000-0000-0000-000000000002';

select is(
  (
    select count(*)
    from storage.objects
    where bucket_id = 'ops-attachments'
  ),
  1::bigint,
  'assigned PRINTER_PRODUCTION sees only its production-safe binary objects'
);

select lives_ok(
  $$
    insert into storage.objects (bucket_id, name, owner_id)
    values (
      'ops-attachments',
      'print-jobs/assigned/completion.jpg',
      '96000000-0000-0000-0000-000000000002'
    )
    returning id
  $$,
  'assigned PRINTER_PRODUCTION can upload a pre-authorized production-evidence object'
);

select is(
  (
    select count(*)
    from storage.objects
    where bucket_id = 'ops-attachments'
      and name = 'print-jobs/assigned/completion.jpg'
  ),
  1::bigint,
  'new production-evidence object is readable after upload under the same RLS policy'
);

reset role;

select * from finish();
rollback;
