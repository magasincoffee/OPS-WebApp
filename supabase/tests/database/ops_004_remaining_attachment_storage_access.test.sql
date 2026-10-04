begin;

create extension if not exists pgtap with schema extensions;

select plan(18);

select is(
  (select public from storage.buckets where id = 'ops-attachments'),
  false,
  'OPS-004 keeps ops-attachments private'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'public'
      and tablename = 'attachments'
      and policyname = any(array[
        'attachments_select_product_variant_business_roles',
        'attachments_select_quotation_sales',
        'attachments_insert_quotation_sales',
        'attachments_select_sales_order_business_roles',
        'attachments_insert_sales_order_sales',
        'attachments_select_assigned_task_operational_role',
        'attachments_insert_assigned_task_operational_role',
        'attachments_select_stocktake_warehouse',
        'attachments_insert_stocktake_warehouse'
      ])
  $$,
  array[9::bigint],
  'all remaining attachment metadata policies are installed'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = any(array[
        'ops_supplier_attachments_select',
        'ops_product_variant_attachments_select',
        'ops_quotation_attachments_select',
        'ops_sales_order_attachments_select',
        'ops_task_attachments_select',
        'ops_stocktake_attachments_select'
      ])
      and cmd = 'SELECT'
  $$,
  array[6::bigint],
  'all six remaining Storage SELECT policies are installed'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = any(array[
        'ops_supplier_attachments_insert',
        'ops_product_variant_attachments_insert',
        'ops_quotation_attachments_insert',
        'ops_sales_order_attachments_insert',
        'ops_task_attachments_insert',
        'ops_stocktake_attachments_insert'
      ])
      and cmd = 'INSERT'
  $$,
  array[6::bigint],
  'all six remaining Storage INSERT policies are installed'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname like 'ops_%_attachments_%'
      and policyname = any(array[
        'ops_supplier_attachments_select',
        'ops_supplier_attachments_insert',
        'ops_product_variant_attachments_select',
        'ops_product_variant_attachments_insert',
        'ops_quotation_attachments_select',
        'ops_quotation_attachments_insert',
        'ops_sales_order_attachments_select',
        'ops_sales_order_attachments_insert',
        'ops_task_attachments_select',
        'ops_task_attachments_insert',
        'ops_stocktake_attachments_select',
        'ops_stocktake_attachments_insert'
      ])
      and cmd in ('UPDATE', 'DELETE')
  $$,
  array[0::bigint],
  'remaining Storage policies add no authenticated update/delete capability'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'public'
      and tablename = 'attachments'
      and policyname = 'attachments_select_product_variant_business_roles'
      and qual like '%PRODUCT_VARIANT%'
      and qual like '%GENERAL%'
      and qual like '%DOCUMENT%'
      and qual like '%SALES%'
      and qual like '%ACCOUNTING%'
      and qual like '%WAREHOUSE%'
      and qual like '%PRINTER_PRODUCTION%'
  $$,
  array[1::bigint],
  'product-variant metadata is readable by all non-owner V1 business roles for reference docs only'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'public'
      and tablename = 'attachments'
      and policyname = 'attachments_insert_quotation_sales'
      and with_check like '%QUOTATION%'
      and with_check like '%SALES%'
      and with_check like '%uploaded_by_user_id%'
      and with_check like '%auth.uid%'
  $$,
  array[1::bigint],
  'quotation metadata upload is limited to self-attributed SALES documents'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'public'
      and tablename = 'attachments'
      and policyname = 'attachments_select_sales_order_business_roles'
      and qual like '%SALES_ORDER%'
      and qual like '%SALES%'
      and qual like '%ACCOUNTING%'
      and qual not like '%WAREHOUSE%'
      and qual not like '%PRINTER_PRODUCTION%'
  $$,
  array[1::bigint],
  'sales-order metadata read follows SALES plus ACCOUNTING visibility'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'public'
      and tablename = 'attachments'
      and policyname = 'attachments_select_assigned_task_operational_role'
      and qual like '%TASK%'
      and qual like '%assignee_user_id%'
      and qual like '%auth.uid%'
      and qual like '%SALES%'
      and qual like '%ACCOUNTING%'
      and qual like '%WAREHOUSE%'
      and qual like '%PRINTER_PRODUCTION%'
  $$,
  array[1::bigint],
  'task metadata is limited to the authenticated assignee across operational roles'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'public'
      and tablename = 'attachments'
      and policyname = 'attachments_insert_stocktake_warehouse'
      and with_check like '%STOCKTAKE%'
      and with_check like '%WAREHOUSE%'
      and with_check like '%uploaded_by_user_id%'
      and with_check like '%auth.uid%'
  $$,
  array[1::bigint],
  'stocktake metadata upload is self-attributed and WAREHOUSE-only outside owner'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'ops_supplier_attachments_select'
      and qual like '%SUPPLIER%'
      and qual like '%OWNER_ADMIN%'
      and qual like '%ACCOUNTING%'
      and qual like '%WAREHOUSE%'
  $$,
  array[1::bigint],
  'supplier binary documents are readable only by procurement-visible roles'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'ops_supplier_attachments_insert'
      and with_check like '%OWNER_ADMIN%'
      and with_check not like '%ACCOUNTING%'
      and with_check not like '%WAREHOUSE%'
      and with_check not like '%SALES%'
      and with_check not like '%PRINTER_PRODUCTION%'
  $$,
  array[1::bigint],
  'supplier binary upload remains OWNER_ADMIN-only'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'ops_product_variant_attachments_select'
      and qual like '%PRODUCT_VARIANT%'
      and qual like '%OWNER_ADMIN%'
      and qual like '%SALES%'
      and qual like '%ACCOUNTING%'
      and qual like '%WAREHOUSE%'
      and qual like '%PRINTER_PRODUCTION%'
  $$,
  array[1::bigint],
  'product-variant binary reference documents follow all-role product visibility'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'ops_quotation_attachments_insert'
      and with_check like '%QUOTATION%'
      and with_check like '%SALES%'
      and with_check like '%uploaded_by_user_id%'
  $$,
  array[1::bigint],
  'quotation binary upload is metadata-first and self-attributed for SALES'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'ops_sales_order_attachments_select'
      and qual like '%SALES_ORDER%'
      and qual like '%OWNER_ADMIN%'
      and qual like '%SALES%'
      and qual like '%ACCOUNTING%'
  $$,
  array[1::bigint],
  'sales-order binary document read includes ACCOUNTING but not unrelated roles'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'ops_task_attachments_insert'
      and with_check like '%TASK%'
      and with_check like '%assignee_user_id%'
      and with_check like '%uploaded_by_user_id%'
      and with_check like '%auth.uid%'
      and with_check like '%PRINTER_PRODUCTION%'
  $$,
  array[1::bigint],
  'task binary upload requires assignment plus self-attributed metadata'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'ops_stocktake_attachments_insert'
      and with_check like '%STOCKTAKE%'
      and with_check like '%WAREHOUSE%'
      and with_check like '%uploaded_by_user_id%'
  $$,
  array[1::bigint],
  'stocktake binary upload follows WAREHOUSE execution responsibility'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_policies
    where schemaname = 'public'
      and tablename = 'attachments'
      and policyname = any(array[
        'attachments_select_product_variant_business_roles',
        'attachments_select_quotation_sales',
        'attachments_insert_quotation_sales',
        'attachments_select_sales_order_business_roles',
        'attachments_insert_sales_order_sales',
        'attachments_select_assigned_task_operational_role',
        'attachments_insert_assigned_task_operational_role',
        'attachments_select_stocktake_warehouse',
        'attachments_insert_stocktake_warehouse'
      ])
      and cmd in ('UPDATE', 'DELETE')
  $$,
  array[0::bigint],
  'remaining metadata policies preserve no authenticated update/delete posture'
);

select * from finish();
rollback;
