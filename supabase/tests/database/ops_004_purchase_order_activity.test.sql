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
      and c.relname = 'purchase_orders'
      and t.tgname = 'purchase_orders_capture_activity'
      and not t.tgisinternal
  $$,
  array[1::bigint],
  'OPS-004 installs one automatic purchase-order activity trigger'
);

select results_eq(
  $$
    select p.prosecdef
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'capture_purchase_order_activity'
      and p.pronargs = 0
  $$,
  array[true],
  'purchase-order activity capture executes as SECURITY DEFINER'
);

select results_eq(
  $$
    select has_function_privilege(
      'authenticated',
      'public.capture_purchase_order_activity()',
      'EXECUTE'
    )
  $$,
  array[false],
  'authenticated users cannot directly execute the purchase-order audit trigger function'
);

insert into auth.users (id, email)
values (
  '97000000-0000-0000-0000-000000000001',
  'ops-purchase-activity-owner@example.test'
);

insert into public.user_roles (user_id, role_id)
select
  '97000000-0000-0000-0000-000000000001'::uuid,
  r.id
from public.roles r
where r.code = 'OWNER_ADMIN';

insert into public.suppliers (
  id,
  supplier_code,
  supplier_name
)
values (
  '97100000-0000-0000-0000-000000000001',
  'PURCHASE-ACTIVITY-SUPPLIER',
  'Purchase Activity Supplier'
);

set local role authenticated;
set local request.jwt.claim.sub = '97000000-0000-0000-0000-000000000001';

insert into public.purchase_orders (
  id,
  po_number,
  supplier_id,
  status,
  freight_amount,
  responsible_user_id,
  notes
)
values (
  '97200000-0000-0000-0000-000000000001',
  'PO-ACTIVITY-001',
  '97100000-0000-0000-0000-000000000001',
  'DRAFT',
  125000,
  '97000000-0000-0000-0000-000000000001',
  'OPS-004 purchase-order activity test'
);

update public.purchase_orders
set status = 'ORDERED'
where id = '97200000-0000-0000-0000-000000000001';

delete from public.purchase_orders
where id = '97200000-0000-0000-0000-000000000001';

reset role;

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_type = 'PURCHASE_ORDER'
      and linked_entity_id = '97200000-0000-0000-0000-000000000001'
  ),
  3::bigint,
  'create/update/delete each append one purchase-order activity record'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '97200000-0000-0000-0000-000000000001'
      and action_type = 'PURCHASE_ORDER_CREATED'
      and before_data is null
      and after_data ->> 'po_number' = 'PO-ACTIVITY-001'
  ),
  1::bigint,
  'purchase-order creation captures the post-change snapshot'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '97200000-0000-0000-0000-000000000001'
      and action_type = 'PURCHASE_ORDER_UPDATED'
      and before_data ->> 'status' = 'DRAFT'
      and after_data ->> 'status' = 'ORDERED'
  ),
  1::bigint,
  'purchase-order update captures before and after status snapshots'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '97200000-0000-0000-0000-000000000001'
      and action_type = 'PURCHASE_ORDER_DELETED'
      and before_data ->> 'po_number' = 'PO-ACTIVITY-001'
      and after_data is null
  ),
  1::bigint,
  'purchase-order deletion captures the pre-delete snapshot'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '97200000-0000-0000-0000-000000000001'
      and actor_user_id = '97000000-0000-0000-0000-000000000001'
  ),
  3::bigint,
  'all purchase-order activity rows bind actor identity to auth.uid()'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '97200000-0000-0000-0000-000000000001'
      and event_source = 'USER'
  ),
  3::bigint,
  'authenticated purchase-order mutations are marked as USER events'
);

select results_eq(
  $$
    select count(*)::bigint
    from public.activity_logs
    where linked_entity_id = '97200000-0000-0000-0000-000000000001'
      and metadata ->> 'table_name' = 'purchase_orders'
      and metadata ->> 'schema_name' = 'public'
  $$,
  array[3::bigint],
  'purchase-order activity metadata records its database source'
);

select * from finish();
rollback;
