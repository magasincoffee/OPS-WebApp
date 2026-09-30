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
      and c.relname = 'print_job_events'
      and t.tgname = 'print_job_events_capture_activity'
      and not t.tgisinternal
  $$,
  array[1::bigint],
  'OPS-004 installs one automatic print-job-event activity trigger'
);

select results_eq(
  $$
    select p.prosecdef
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'capture_print_job_event_activity'
      and p.pronargs = 0
  $$,
  array[true],
  'print-job-event activity capture executes as SECURITY DEFINER'
);

select results_eq(
  $$
    select has_function_privilege(
      'authenticated',
      'public.capture_print_job_event_activity()',
      'EXECUTE'
    )
  $$,
  array[false],
  'authenticated users cannot directly execute the print-job-event audit trigger function'
);

insert into auth.users (id, email)
values (
  '95000000-0000-0000-0000-000000000001',
  'ops-print-event-activity-owner@example.test'
);

insert into public.user_roles (user_id, role_id)
select
  '95000000-0000-0000-0000-000000000001'::uuid,
  r.id
from public.roles r
where r.code in ('OWNER_ADMIN','PRINTER_PRODUCTION');

insert into public.customers (id, customer_code, display_name)
values (
  '95100000-0000-0000-0000-000000000001',
  'PRINT-EVENT-ACTIVITY-CUSTOMER',
  'Print Event Activity Customer'
);

insert into public.product_categories (id, category_code, name)
values (
  '95200000-0000-0000-0000-000000000001',
  'PRINT-EVENT-ACTIVITY-CATEGORY',
  'Print Event Activity Category'
);

insert into public.products (id, category_id, name, product_type)
values (
  '95300000-0000-0000-0000-000000000001',
  '95200000-0000-0000-0000-000000000001',
  'Print Event Activity Product',
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
  'PRINT-EVENT-ACTIVITY-SKU',
  'Print Event Activity Variant',
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
  'SO-PRINT-EVENT-ACTIVITY-001',
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
  'Two-color event activity test',
  current_date + 1
);

-- OPS-032 requires the canonical DRAFT → line authoring → CONFIRMED branch before production.
update public.sales_orders
set order_status = 'CONFIRMED'
where id = '95500000-0000-0000-0000-000000000001';

set local role authenticated;
set local request.jwt.claim.sub = '95000000-0000-0000-0000-000000000001';

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
  '95700000-0000-0000-0000-000000000001',
  'PJ-EVENT-ACTIVITY-001',
  '95500000-0000-0000-0000-000000000001',
  '95600000-0000-0000-0000-000000000001',
  '95100000-0000-0000-0000-000000000001',
  '95400000-0000-0000-0000-000000000001',
  'CUP',
  1000,
  2,
  'Two-color event activity test',
  current_date + 1,
  '95000000-0000-0000-0000-000000000001',
  '95000000-0000-0000-0000-000000000001'
);

insert into public.print_job_events (
  id,
  print_job_id,
  event_type,
  from_status,
  to_status,
  assignee_user_id,
  actor_user_id,
  note
)
values (
  '95800000-0000-0000-0000-000000000001',
  '95700000-0000-0000-0000-000000000001',
  'STATUS_CHANGED',
  'WAITING',
  'ACCEPTED',
  '95000000-0000-0000-0000-000000000001',
  '95000000-0000-0000-0000-000000000001',
  'Accepted for production'
);

update public.print_job_events
set note = 'Accepted for production - verified'
where id = '95800000-0000-0000-0000-000000000001';

delete from public.print_job_events
where id = '95800000-0000-0000-0000-000000000001';

reset role;

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_type = 'PRINT_JOB_EVENT'
      and linked_entity_id = '95800000-0000-0000-0000-000000000001'
  ),
  3::bigint,
  'create/update/delete each append one print-job-event activity record'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '95800000-0000-0000-0000-000000000001'
      and action_type = 'PRINT_JOB_EVENT_CREATED'
      and before_data is null
      and after_data ->> 'event_type' = 'STATUS_CHANGED'
  ),
  1::bigint,
  'print-job-event creation captures the post-change snapshot'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '95800000-0000-0000-0000-000000000001'
      and action_type = 'PRINT_JOB_EVENT_UPDATED'
      and before_data ->> 'note' = 'Accepted for production'
      and after_data ->> 'note' = 'Accepted for production - verified'
  ),
  1::bigint,
  'print-job-event update captures before and after snapshots'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '95800000-0000-0000-0000-000000000001'
      and action_type = 'PRINT_JOB_EVENT_DELETED'
      and before_data ->> 'event_type' = 'STATUS_CHANGED'
      and after_data is null
  ),
  1::bigint,
  'print-job-event deletion captures the pre-delete snapshot'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '95800000-0000-0000-0000-000000000001'
      and actor_user_id = '95000000-0000-0000-0000-000000000001'
  ),
  3::bigint,
  'all print-job-event activity rows bind actor identity to auth.uid()'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '95800000-0000-0000-0000-000000000001'
      and event_source = 'USER'
  ),
  3::bigint,
  'authenticated print-job-event mutations are marked as USER events'
);

select results_eq(
  $$
    select count(*)::bigint
    from public.activity_logs
    where linked_entity_id = '95800000-0000-0000-0000-000000000001'
      and metadata ->> 'table_name' = 'print_job_events'
      and metadata ->> 'schema_name' = 'public'
      and metadata ->> 'print_job_id' = '95700000-0000-0000-0000-000000000001'
      and metadata ->> 'event_type' = 'STATUS_CHANGED'
  $$,
  array[3::bigint],
  'print-job-event activity metadata records database source and parent job'
);

select * from finish();
rollback;
