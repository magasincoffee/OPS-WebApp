begin;

create extension if not exists pgtap with schema extensions;

select plan(10);

select results_eq(
  $$
    select count(*)::bigint
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'print_jobs'
      and t.tgname = 'print_jobs_capture_activity'
      and not t.tgisinternal
  $$,
  array[1::bigint],
  'OPS-004 installs one automatic print-job activity trigger'
);

select results_eq(
  $$
    select p.prosecdef
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'capture_print_job_activity'
      and p.pronargs = 0
  $$,
  array[true],
  'print-job activity capture executes as SECURITY DEFINER'
);

select results_eq(
  $$
    select has_function_privilege(
      'authenticated',
      'public.capture_print_job_activity()',
      'EXECUTE'
    )
  $$,
  array[false],
  'authenticated users cannot directly execute the print-job audit trigger function'
);

insert into auth.users (id, email)
values (
  '94000000-0000-0000-0000-000000000001',
  'ops-print-activity-owner@example.test'
);

insert into public.user_roles (user_id, role_id)
select
  '94000000-0000-0000-0000-000000000001'::uuid,
  r.id
from public.roles r
where r.code in ('OWNER_ADMIN','PRINTER_PRODUCTION');

insert into public.customers (id, customer_code, display_name)
values (
  '94100000-0000-0000-0000-000000000001',
  'PRINT-ACTIVITY-CUSTOMER',
  'Print Activity Customer'
);

insert into public.product_categories (id, category_code, name)
values (
  '94200000-0000-0000-0000-000000000001',
  'PRINT-ACTIVITY-CATEGORY',
  'Print Activity Category'
);

insert into public.products (id, category_id, name, product_type)
values (
  '94300000-0000-0000-0000-000000000001',
  '94200000-0000-0000-0000-000000000001',
  'Print Activity Product',
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
  '94400000-0000-0000-0000-000000000001',
  '94300000-0000-0000-0000-000000000001',
  'PRINT-ACTIVITY-SKU',
  'Print Activity Variant',
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
  '94500000-0000-0000-0000-000000000001',
  'SO-PRINT-ACTIVITY-001',
  '94100000-0000-0000-0000-000000000001',
  '94000000-0000-0000-0000-000000000001',
  '94000000-0000-0000-0000-000000000001'
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
  '94600000-0000-0000-0000-000000000001',
  '94500000-0000-0000-0000-000000000001',
  '94400000-0000-0000-0000-000000000001',
  'carton',
  1,
  1000,
  1000000,
  'PRINTED',
  2,
  'Two-color test print',
  current_date + 1
);

-- OPS-032 requires the canonical DRAFT → line authoring → CONFIRMED branch before production.
update public.sales_orders
set order_status = 'CONFIRMED'
where id = '94500000-0000-0000-0000-000000000001';

set local role authenticated;
set local request.jwt.claim.sub = '94000000-0000-0000-0000-000000000001';

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
values (
  '94700000-0000-0000-0000-000000000001',
  'PJ-ACTIVITY-001',
  '94500000-0000-0000-0000-000000000001',
  '94600000-0000-0000-0000-000000000001',
  '94100000-0000-0000-0000-000000000001',
  '94400000-0000-0000-0000-000000000001',
  'CUP',
  1000,
  2,
  'Two-color test print',
  current_date + 1,
  '94000000-0000-0000-0000-000000000001',
  '94000000-0000-0000-0000-000000000001'
);

update public.print_jobs
set
  status = 'ACCEPTED',
  accepted_at = timezone('utc', now())
where id = '94700000-0000-0000-0000-000000000001';

delete from public.print_jobs
where id = '94700000-0000-0000-0000-000000000001';

reset role;

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_type = 'PRINT_JOB'
      and linked_entity_id = '94700000-0000-0000-0000-000000000001'
  ),
  3::bigint,
  'create/update/delete each append one print-job activity record'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '94700000-0000-0000-0000-000000000001'
      and action_type = 'PRINT_JOB_CREATED'
      and before_data is null
      and after_data ->> 'job_number' = 'PJ-ACTIVITY-001'
  ),
  1::bigint,
  'print-job creation captures the post-change snapshot'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '94700000-0000-0000-0000-000000000001'
      and action_type = 'PRINT_JOB_UPDATED'
      and before_data ->> 'status' = 'WAITING'
      and after_data ->> 'status' = 'ACCEPTED'
  ),
  1::bigint,
  'print-job update captures before and after status snapshots'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '94700000-0000-0000-0000-000000000001'
      and action_type = 'PRINT_JOB_DELETED'
      and before_data ->> 'job_number' = 'PJ-ACTIVITY-001'
      and after_data is null
  ),
  1::bigint,
  'print-job deletion captures the pre-delete snapshot'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '94700000-0000-0000-0000-000000000001'
      and actor_user_id = '94000000-0000-0000-0000-000000000001'
  ),
  3::bigint,
  'all print-job activity rows bind actor identity to auth.uid()'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '94700000-0000-0000-0000-000000000001'
      and event_source = 'USER'
  ),
  3::bigint,
  'authenticated print-job mutations are marked as USER events'
);

select results_eq(
  $$
    select count(*)::bigint
    from public.activity_logs
    where linked_entity_id = '94700000-0000-0000-0000-000000000001'
      and metadata ->> 'table_name' = 'print_jobs'
      and metadata ->> 'schema_name' = 'public'
  $$,
  array[3::bigint],
  'print-job activity metadata records its database source'
);

select * from finish();
rollback;
