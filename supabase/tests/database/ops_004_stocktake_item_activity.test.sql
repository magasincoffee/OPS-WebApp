begin;

create extension if not exists pgtap with schema extensions;

select plan(11);

select results_eq(
  $$
    select count(*)::bigint
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'stocktake_items'
      and t.tgname = 'stocktake_items_capture_activity'
      and not t.tgisinternal
  $$,
  array[1::bigint],
  'OPS-004 installs one automatic stocktake-item activity trigger'
);

select results_eq(
  $$
    select p.prosecdef
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'capture_stocktake_item_activity'
      and p.pronargs = 0
  $$,
  array[true],
  'stocktake-item activity capture executes as SECURITY DEFINER'
);

select results_eq(
  $$
    select has_function_privilege(
      'authenticated',
      'public.capture_stocktake_item_activity()',
      'EXECUTE'
    )
  $$,
  array[false],
  'authenticated users cannot directly execute the stocktake-item audit trigger function'
);

insert into auth.users (id, email)
values (
  '9c100000-0000-0000-0000-000000000001',
  'ops-stocktake-item-activity-owner@example.test'
);

insert into public.user_roles (user_id, role_id)
select
  '9c100000-0000-0000-0000-000000000001'::uuid,
  r.id
from public.roles r
where r.code = 'OWNER_ADMIN';

insert into public.product_categories (id, category_code, name)
values (
  '9c200000-0000-0000-0000-000000000001',
  'STI-ACTIVITY',
  'Stocktake Item Activity Category'
);

insert into public.products (id, category_id, name)
values (
  '9c300000-0000-0000-0000-000000000001',
  '9c200000-0000-0000-0000-000000000001',
  'Stocktake Item Activity Product'
);

insert into public.product_variants (id, product_id, sku_code, variant_name)
values (
  '9c400000-0000-0000-0000-000000000001',
  '9c300000-0000-0000-0000-000000000001',
  'STI-ACTIVITY-SKU-001',
  'Stocktake Item Activity Variant'
);

insert into public.stocktakes (
  id,
  stocktake_number,
  stocktake_date,
  status,
  created_by_user_id,
  notes
)
values (
  '9c500000-0000-0000-0000-000000000001',
  'ST-ITEM-ACTIVITY-001',
  date '2026-09-29',
  'DRAFT',
  '9c100000-0000-0000-0000-000000000001',
  'OPS-004 stocktake-item activity test parent stocktake'
);

set local role authenticated;
set local request.jwt.claim.sub = '9c100000-0000-0000-0000-000000000001';

insert into public.stocktake_items (
  id,
  stocktake_id,
  product_variant_id,
  system_on_hand_quantity,
  counted_on_hand_quantity,
  notes
)
values (
  '9c600000-0000-0000-0000-000000000001',
  '9c500000-0000-0000-0000-000000000001',
  '9c400000-0000-0000-0000-000000000001',
  100,
  95,
  'Initial stocktake-item note'
);

update public.stocktake_items
set counted_on_hand_quantity = 110,
    notes = 'Updated stocktake-item note'
where id = '9c600000-0000-0000-0000-000000000001';

delete from public.stocktake_items
where id = '9c600000-0000-0000-0000-000000000001';

reset role;

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_type = 'STOCKTAKE_ITEM'
      and linked_entity_id = '9c600000-0000-0000-0000-000000000001'
  ),
  3::bigint,
  'create/update/delete each append one stocktake-item activity record'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '9c600000-0000-0000-0000-000000000001'
      and action_type = 'STOCKTAKE_ITEM_CREATED'
      and before_data is null
      and (after_data ->> 'system_on_hand_quantity')::numeric = 100
      and (after_data ->> 'counted_on_hand_quantity')::numeric = 95
      and (after_data ->> 'variance_quantity')::numeric = -5
  ),
  1::bigint,
  'stocktake-item creation captures the post-change snapshot including generated variance'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '9c600000-0000-0000-0000-000000000001'
      and action_type = 'STOCKTAKE_ITEM_UPDATED'
      and (before_data ->> 'counted_on_hand_quantity')::numeric = 95
      and (after_data ->> 'counted_on_hand_quantity')::numeric = 110
      and (before_data ->> 'variance_quantity')::numeric = -5
      and (after_data ->> 'variance_quantity')::numeric = 10
      and before_data ->> 'notes' = 'Initial stocktake-item note'
      and after_data ->> 'notes' = 'Updated stocktake-item note'
  ),
  1::bigint,
  'stocktake-item update captures before and after snapshots'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '9c600000-0000-0000-0000-000000000001'
      and action_type = 'STOCKTAKE_ITEM_DELETED'
      and (before_data ->> 'variance_quantity')::numeric = 10
      and after_data is null
  ),
  1::bigint,
  'stocktake-item deletion captures the pre-delete snapshot'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '9c600000-0000-0000-0000-000000000001'
      and actor_user_id = '9c100000-0000-0000-0000-000000000001'
  ),
  3::bigint,
  'all stocktake-item activity rows bind actor identity to auth.uid()'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '9c600000-0000-0000-0000-000000000001'
      and event_source = 'USER'
  ),
  3::bigint,
  'authenticated stocktake-item mutations are marked as USER events'
);

select results_eq(
  $$
    select count(*)::bigint
    from public.activity_logs
    where linked_entity_id = '9c600000-0000-0000-0000-000000000001'
      and metadata ->> 'table_name' = 'stocktake_items'
      and metadata ->> 'schema_name' = 'public'
  $$,
  array[3::bigint],
  'stocktake-item activity metadata records its database source'
);

select results_eq(
  $$
    select count(*)::bigint
    from public.activity_logs
    where linked_entity_id = '9c600000-0000-0000-0000-000000000001'
      and metadata ->> 'stocktake_id' = '9c500000-0000-0000-0000-000000000001'
      and metadata ->> 'product_variant_id' = '9c400000-0000-0000-0000-000000000001'
  $$,
  array[3::bigint],
  'stocktake-item activity metadata preserves parent stocktake and product-variant linkage'
);

select * from finish();
rollback;
