begin;

create extension if not exists pgtap with schema extensions;

select plan(8);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'public'
      and tablename = 'attachments'
      and policyname = 'attachments_select_sales_order_item_sales'
      and cmd = 'SELECT'
  $$,
  array[1::bigint],
  'OPS-004 installs sales-order-item artwork attachment metadata SELECT policy'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'public'
      and tablename = 'attachments'
      and policyname = 'attachments_insert_sales_order_item_sales_artwork'
      and cmd = 'INSERT'
  $$,
  array[1::bigint],
  'OPS-004 installs sales-order-item artwork attachment metadata INSERT policy'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'public'
      and tablename = 'attachments'
      and policyname = 'attachments_select_sales_order_item_sales'
      and qual like '%SALES%'
      and qual like '%SALES_ORDER_ITEM%'
      and qual like '%ARTWORK%'
      and qual like '%ops-attachments%'
  $$,
  array[1::bigint],
  'sales-order-item attachment SELECT policy is limited to SALES artwork metadata'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'public'
      and tablename = 'attachments'
      and policyname = 'attachments_insert_sales_order_item_sales_artwork'
      and with_check like '%SALES%'
      and with_check like '%SALES_ORDER_ITEM%'
      and with_check like '%ARTWORK%'
      and with_check like '%ops-attachments%'
      and with_check like '%uploaded_by_user_id%'
  $$,
  array[1::bigint],
  'sales-order-item attachment INSERT policy requires self-attributed SALES artwork'
);

insert into auth.users (id, email)
values
  ('98000000-0000-0000-0000-000000000001', 'ops-sales-artwork-owner@example.test'),
  ('98000000-0000-0000-0000-000000000002', 'ops-sales-artwork-sales@example.test'),
  ('98000000-0000-0000-0000-000000000003', 'ops-sales-artwork-accounting@example.test');

insert into public.user_roles (user_id, role_id, assigned_by)
select x.user_id, r.id, '98000000-0000-0000-0000-000000000001'::uuid
from (
  values
    ('98000000-0000-0000-0000-000000000001'::uuid, 'OWNER_ADMIN'::text),
    ('98000000-0000-0000-0000-000000000002'::uuid, 'SALES'::text),
    ('98000000-0000-0000-0000-000000000003'::uuid, 'ACCOUNTING'::text)
) as x(user_id, role_code)
join public.roles r on r.code = x.role_code;

insert into public.customers (id, customer_code, display_name)
values (
  '98100000-0000-0000-0000-000000000001',
  'SALES-ARTWORK-CUSTOMER',
  'Sales Artwork Customer'
);

insert into public.product_categories (id, category_code, name)
values (
  '98200000-0000-0000-0000-000000000001',
  'SALES-ARTWORK-CATEGORY',
  'Sales Artwork Category'
);

insert into public.products (id, category_id, name, product_type)
values (
  '98300000-0000-0000-0000-000000000001',
  '98200000-0000-0000-0000-000000000001',
  'Sales Artwork Product',
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
  '98400000-0000-0000-0000-000000000001',
  '98300000-0000-0000-0000-000000000001',
  'SALES-ARTWORK-SKU',
  'Sales Artwork Variant',
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
  '98500000-0000-0000-0000-000000000001',
  'SO-SALES-ARTWORK-001',
  '98100000-0000-0000-0000-000000000001',
  '98000000-0000-0000-0000-000000000002',
  '98000000-0000-0000-0000-000000000002'
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
  '98600000-0000-0000-0000-000000000001',
  '98500000-0000-0000-0000-000000000001',
  '98400000-0000-0000-0000-000000000001',
  'carton',
  1,
  1000,
  1000000,
  'PRINTED',
  2,
  'Two-color sales artwork access test'
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
    '98700000-0000-0000-0000-000000000001',
    'SALES_ORDER_ITEM',
    '98600000-0000-0000-0000-000000000001',
    'ARTWORK',
    'ops-attachments',
    'sales-order-items/98600000-0000-0000-0000-000000000001/artwork-1.pdf',
    'artwork-1.pdf',
    '98000000-0000-0000-0000-000000000001'
  ),
  (
    '98700000-0000-0000-0000-000000000002',
    'SALES_ORDER_ITEM',
    '98600000-0000-0000-0000-000000000001',
    'DOCUMENT',
    'ops-attachments',
    'sales-order-items/98600000-0000-0000-0000-000000000001/document.pdf',
    'document.pdf',
    '98000000-0000-0000-0000-000000000001'
  );

set local role authenticated;
set local request.jwt.claim.sub = '98000000-0000-0000-0000-000000000002';

select is(
  (select count(*) from public.attachments),
  1::bigint,
  'SALES sees only ARTWORK metadata linked to sales-order items'
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
  '98700000-0000-0000-0000-000000000003',
  'SALES_ORDER_ITEM',
  '98600000-0000-0000-0000-000000000001',
  'ARTWORK',
  'ops-attachments',
  'sales-order-items/98600000-0000-0000-0000-000000000001/artwork-2.png',
  'artwork-2.png',
  '98000000-0000-0000-0000-000000000002'
);

select is(
  (select count(*) from public.attachments),
  2::bigint,
  'SALES can add and read self-attributed sales-order-item artwork metadata'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '98000000-0000-0000-0000-000000000003';

select is(
  (select count(*) from public.attachments),
  0::bigint,
  'ACCOUNTING receives no direct sales-order-item artwork attachment metadata access'
);

reset role;

select is(
  (
    select count(*)
    from public.attachments
    where linked_entity_type = 'SALES_ORDER_ITEM'
      and linked_entity_id = '98600000-0000-0000-0000-000000000001'
  ),
  3::bigint,
  'privileged view confirms restricted sales-order-item attachment rows remain present'
);

select * from finish();
rollback;
