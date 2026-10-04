begin;

create extension if not exists pgtap with schema extensions;

select plan(10);

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
      and policyname = 'ops_sales_order_item_artwork_select'
      and cmd = 'SELECT'
  $$,
  array[1::bigint],
  'OPS-004 installs sales-order-item artwork Storage SELECT policy'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'ops_sales_order_item_artwork_insert'
      and cmd = 'INSERT'
  $$,
  array[1::bigint],
  'OPS-004 installs sales-order-item artwork Storage INSERT policy'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'ops_sales_order_item_artwork_select'
      and qual like '%SALES_ORDER_ITEM%'
      and qual like '%ARTWORK%'
      and qual like '%SALES%'
      and qual like '%OWNER_ADMIN%'
  $$,
  array[1::bigint],
  'sales-order-item Storage SELECT policy is limited to artwork for authorized sales roles'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'ops_sales_order_item_artwork_insert'
      and with_check like '%SALES_ORDER_ITEM%'
      and with_check like '%ARTWORK%'
      and with_check like '%SALES%'
      and with_check like '%uploaded_by_user_id%'
  $$,
  array[1::bigint],
  'sales-order-item Storage INSERT policy requires self-attributed SALES artwork'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname in (
        'ops_sales_order_item_artwork_select',
        'ops_sales_order_item_artwork_insert'
      )
      and cmd in ('UPDATE', 'DELETE')
  $$,
  array[0::bigint],
  'bounded sales-order-item Storage unit does not grant authenticated update/delete or upsert capability'
);

insert into auth.users (id, email)
values
  ('99000000-0000-0000-0000-000000000001', 'ops-sales-storage-owner@example.test'),
  ('99000000-0000-0000-0000-000000000002', 'ops-sales-storage-sales@example.test'),
  ('99000000-0000-0000-0000-000000000003', 'ops-sales-storage-accounting@example.test');

insert into public.user_roles (user_id, role_id, assigned_by)
select x.user_id, r.id, '99000000-0000-0000-0000-000000000001'::uuid
from (
  values
    ('99000000-0000-0000-0000-000000000001'::uuid, 'OWNER_ADMIN'::text),
    ('99000000-0000-0000-0000-000000000002'::uuid, 'SALES'::text),
    ('99000000-0000-0000-0000-000000000003'::uuid, 'ACCOUNTING'::text)
) as x(user_id, role_code)
join public.roles r on r.code = x.role_code;

insert into public.customers (id, customer_code, display_name)
values (
  '99100000-0000-0000-0000-000000000001',
  'SALES-STORAGE-CUSTOMER',
  'Sales Storage Customer'
);

insert into public.product_categories (id, category_code, name)
values (
  '99200000-0000-0000-0000-000000000001',
  'SALES-STORAGE-CATEGORY',
  'Sales Storage Category'
);

insert into public.products (id, category_id, name, product_type)
values (
  '99300000-0000-0000-0000-000000000001',
  '99200000-0000-0000-0000-000000000001',
  'Sales Storage Product',
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
  '99400000-0000-0000-0000-000000000001',
  '99300000-0000-0000-0000-000000000001',
  'SALES-STORAGE-SKU',
  'Sales Storage Variant',
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
  '99500000-0000-0000-0000-000000000001',
  'SO-SALES-STORAGE-001',
  '99100000-0000-0000-0000-000000000001',
  '99000000-0000-0000-0000-000000000002',
  '99000000-0000-0000-0000-000000000002'
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
  print_specification
)
values (
  '99600000-0000-0000-0000-000000000001',
  '99500000-0000-0000-0000-000000000001',
  '99400000-0000-0000-0000-000000000001',
  'carton',
  1,
  1000,
  1000000,
  'PRINTED',
  2,
  'Two-color sales Storage access test'
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
    '99700000-0000-0000-0000-000000000001',
    'SALES_ORDER_ITEM',
    '99600000-0000-0000-0000-000000000001',
    'ARTWORK',
    'ops-attachments',
    'sales-order-items/99600000-0000-0000-0000-000000000001/artwork-1.pdf',
    'artwork-1.pdf',
    '99000000-0000-0000-0000-000000000001'
  ),
  (
    '99700000-0000-0000-0000-000000000002',
    'SALES_ORDER_ITEM',
    '99600000-0000-0000-0000-000000000001',
    'DOCUMENT',
    'ops-attachments',
    'sales-order-items/99600000-0000-0000-0000-000000000001/document.pdf',
    'document.pdf',
    '99000000-0000-0000-0000-000000000001'
  ),
  (
    '99700000-0000-0000-0000-000000000003',
    'SALES_ORDER_ITEM',
    '99600000-0000-0000-0000-000000000001',
    'ARTWORK',
    'ops-attachments',
    'sales-order-items/99600000-0000-0000-0000-000000000001/artwork-2.png',
    'artwork-2.png',
    '99000000-0000-0000-0000-000000000002'
  );

insert into storage.objects (bucket_id, name, owner_id)
values
  (
    'ops-attachments',
    'sales-order-items/99600000-0000-0000-0000-000000000001/artwork-1.pdf',
    '99000000-0000-0000-0000-000000000001'
  ),
  (
    'ops-attachments',
    'sales-order-items/99600000-0000-0000-0000-000000000001/document.pdf',
    '99000000-0000-0000-0000-000000000001'
  );

set local role authenticated;
set local request.jwt.claim.sub = '99000000-0000-0000-0000-000000000002';

select is(
  (
    select count(*)
    from storage.objects
    where bucket_id = 'ops-attachments'
  ),
  1::bigint,
  'SALES sees only sales-order-item artwork binary objects'
);

select lives_ok(
  $$
    insert into storage.objects (bucket_id, name, owner_id)
    values (
      'ops-attachments',
      'sales-order-items/99600000-0000-0000-0000-000000000001/artwork-2.png',
      '99000000-0000-0000-0000-000000000002'
    )
    returning id
  $$,
  'SALES can upload a pre-authorized self-attributed sales-order-item artwork object'
);

select is(
  (
    select count(*)
    from storage.objects
    where bucket_id = 'ops-attachments'
      and name = 'sales-order-items/99600000-0000-0000-0000-000000000001/artwork-2.png'
  ),
  1::bigint,
  'new sales-order-item artwork object is readable after upload under the same RLS policy'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '99000000-0000-0000-0000-000000000003';

select is(
  (
    select count(*)
    from storage.objects
    where bucket_id = 'ops-attachments'
  ),
  0::bigint,
  'ACCOUNTING receives no direct sales-order-item artwork binary-object access'
);

reset role;

select * from finish();
rollback;
