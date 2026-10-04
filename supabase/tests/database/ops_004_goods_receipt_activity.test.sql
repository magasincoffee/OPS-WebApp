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
      and c.relname = 'goods_receipts'
      and t.tgname = 'goods_receipts_capture_activity'
      and not t.tgisinternal
  $$,
  array[1::bigint],
  'OPS-004 installs one automatic goods-receipt activity trigger'
);

select results_eq(
  $$
    select p.prosecdef
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'capture_goods_receipt_activity'
      and p.pronargs = 0
  $$,
  array[true],
  'goods-receipt activity capture executes as SECURITY DEFINER'
);

select results_eq(
  $$
    select has_function_privilege(
      'authenticated',
      'public.capture_goods_receipt_activity()',
      'EXECUTE'
    )
  $$,
  array[false],
  'authenticated users cannot directly execute the goods-receipt audit trigger function'
);

insert into auth.users (id, email)
values (
  '97300000-0000-0000-0000-000000000001',
  'ops-goods-receipt-activity-warehouse@example.test'
);

insert into public.user_roles (user_id, role_id)
select
  '97300000-0000-0000-0000-000000000001'::uuid,
  r.id
from public.roles r
where r.code = 'WAREHOUSE';

insert into public.suppliers (
  id,
  supplier_code,
  supplier_name
)
values (
  '97400000-0000-0000-0000-000000000001',
  'GOODS-RECEIPT-ACTIVITY-SUPPLIER',
  'Goods Receipt Activity Supplier'
);

insert into public.purchase_orders (
  id,
  po_number,
  supplier_id,
  status,
  responsible_user_id,
  notes
)
values (
  '97500000-0000-0000-0000-000000000001',
  'PO-GR-ACTIVITY-001',
  '97400000-0000-0000-0000-000000000001',
  'ORDERED',
  '97300000-0000-0000-0000-000000000001',
  'OPS-004 goods-receipt activity parent PO'
);

set local role authenticated;
set local request.jwt.claim.sub = '97300000-0000-0000-0000-000000000001';

insert into public.goods_receipts (
  id,
  goods_receipt_number,
  purchase_order_id,
  received_by_user_id,
  document_reference,
  notes
)
values (
  '97600000-0000-0000-0000-000000000001',
  'GR-ACTIVITY-001',
  '97500000-0000-0000-0000-000000000001',
  '97300000-0000-0000-0000-000000000001',
  'DOC-GR-001',
  'OPS-004 goods-receipt activity test'
);

update public.goods_receipts
set notes = 'OPS-004 goods-receipt activity test updated'
where id = '97600000-0000-0000-0000-000000000001';

delete from public.goods_receipts
where id = '97600000-0000-0000-0000-000000000001';

reset role;

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_type = 'GOODS_RECEIPT'
      and linked_entity_id = '97600000-0000-0000-0000-000000000001'
  ),
  3::bigint,
  'create/update/delete each append one goods-receipt activity record'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '97600000-0000-0000-0000-000000000001'
      and action_type = 'GOODS_RECEIPT_CREATED'
      and before_data is null
      and after_data ->> 'goods_receipt_number' = 'GR-ACTIVITY-001'
  ),
  1::bigint,
  'goods-receipt creation captures the post-change snapshot'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '97600000-0000-0000-0000-000000000001'
      and action_type = 'GOODS_RECEIPT_UPDATED'
      and before_data ->> 'notes' = 'OPS-004 goods-receipt activity test'
      and after_data ->> 'notes' = 'OPS-004 goods-receipt activity test updated'
  ),
  1::bigint,
  'goods-receipt update captures before and after snapshots'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '97600000-0000-0000-0000-000000000001'
      and action_type = 'GOODS_RECEIPT_DELETED'
      and before_data ->> 'goods_receipt_number' = 'GR-ACTIVITY-001'
      and after_data is null
  ),
  1::bigint,
  'goods-receipt deletion captures the pre-delete snapshot'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '97600000-0000-0000-0000-000000000001'
      and actor_user_id = '97300000-0000-0000-0000-000000000001'
  ),
  3::bigint,
  'all goods-receipt activity rows bind actor identity to auth.uid()'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '97600000-0000-0000-0000-000000000001'
      and event_source = 'USER'
  ),
  3::bigint,
  'authenticated goods-receipt mutations are marked as USER events'
);

select results_eq(
  $$
    select count(*)::bigint
    from public.activity_logs
    where linked_entity_id = '97600000-0000-0000-0000-000000000001'
      and metadata ->> 'table_name' = 'goods_receipts'
      and metadata ->> 'schema_name' = 'public'
  $$,
  array[3::bigint],
  'goods-receipt activity metadata records its database source'
);

select * from finish();
rollback;
