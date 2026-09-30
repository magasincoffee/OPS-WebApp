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
      and c.relname = 'quotation_items'
      and t.tgname = 'quotation_items_capture_activity'
      and not t.tgisinternal
  $$,
  array[1::bigint],
  'OPS-004 installs one automatic quotation-item activity trigger'
);

select results_eq(
  $$
    select p.prosecdef
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'capture_quotation_item_activity'
      and p.pronargs = 0
  $$,
  array[true],
  'quotation-item activity capture executes as SECURITY DEFINER'
);

select results_eq(
  $$
    select has_function_privilege(
      'authenticated',
      'public.capture_quotation_item_activity()',
      'EXECUTE'
    )
  $$,
  array[false],
  'authenticated users cannot directly execute the quotation-item audit trigger function'
);

insert into auth.users (id, email)
values (
  '98000000-0000-0000-0000-000000000001',
  'ops-quotation-item-activity@example.test'
);

insert into public.user_roles (user_id, role_id)
select
  '98000000-0000-0000-0000-000000000001'::uuid,
  r.id
from public.roles r
where r.code = 'SALES';

insert into public.customers (id, customer_code, display_name)
values (
  '98100000-0000-0000-0000-000000000001',
  'QUOTATION-ITEM-ACTIVITY-CUSTOMER',
  'Quotation Item Activity Customer'
);

insert into public.product_categories (id, category_code, name)
values (
  '98200000-0000-0000-0000-000000000001',
  'QI-ACTIVITY',
  'Quotation Item Activity Category'
);

insert into public.products (id, category_id, name)
values (
  '98300000-0000-0000-0000-000000000001',
  '98200000-0000-0000-0000-000000000001',
  'Quotation Item Activity Product'
);

insert into public.product_variants (id, product_id, sku_code, variant_name)
values (
  '98400000-0000-0000-0000-000000000001',
  '98300000-0000-0000-0000-000000000001',
  'QI-ACTIVITY-SKU-001',
  'Quotation Item Activity Variant'
);

insert into public.quotations (
  id,
  quotation_number,
  customer_id,
  created_by_user_id
)
values (
  '98500000-0000-0000-0000-000000000001',
  'QT-ITEM-ACTIVITY-001',
  '98100000-0000-0000-0000-000000000001',
  '98000000-0000-0000-0000-000000000001'
);

-- OPS-030 routes production quotation-item writes through bounded RPCs.
-- Restore table mutation only inside this rollback-only legacy audit fixture.
grant insert, update, delete on public.quotation_items to authenticated;

set local role authenticated;
set local request.jwt.claim.sub = '98000000-0000-0000-0000-000000000001';

insert into public.quotation_items (
  id,
  quotation_id,
  product_variant_id,
  sale_unit,
  sale_quantity,
  units_per_sale_unit,
  unit_price_per_sale_unit
)
values (
  '98600000-0000-0000-0000-000000000001',
  '98500000-0000-0000-0000-000000000001',
  '98400000-0000-0000-0000-000000000001',
  'carton',
  2,
  1000,
  1500000
);

update public.quotation_items
set sale_quantity = 3
where id = '98600000-0000-0000-0000-000000000001';

delete from public.quotation_items
where id = '98600000-0000-0000-0000-000000000001';

reset role;

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_type = 'QUOTATION_ITEM'
      and linked_entity_id = '98600000-0000-0000-0000-000000000001'
  ),
  3::bigint,
  'create/update/delete each append one quotation-item activity record'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '98600000-0000-0000-0000-000000000001'
      and action_type = 'QUOTATION_ITEM_CREATED'
      and before_data is null
      and after_data ->> 'sale_quantity' = '2.000000'
  ),
  1::bigint,
  'quotation-item creation captures the post-change snapshot'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '98600000-0000-0000-0000-000000000001'
      and action_type = 'QUOTATION_ITEM_UPDATED'
      and before_data ->> 'sale_quantity' = '2.000000'
      and after_data ->> 'sale_quantity' = '3.000000'
  ),
  1::bigint,
  'quotation-item update captures before and after quantity snapshots'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '98600000-0000-0000-0000-000000000001'
      and action_type = 'QUOTATION_ITEM_DELETED'
      and before_data ->> 'sale_unit' = 'carton'
      and after_data is null
  ),
  1::bigint,
  'quotation-item deletion captures the pre-delete snapshot'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '98600000-0000-0000-0000-000000000001'
      and actor_user_id = '98000000-0000-0000-0000-000000000001'
  ),
  3::bigint,
  'all quotation-item activity rows bind actor identity to auth.uid()'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '98600000-0000-0000-0000-000000000001'
      and event_source = 'USER'
  ),
  3::bigint,
  'authenticated quotation-item mutations are marked as USER events'
);

select results_eq(
  $$
    select count(*)::bigint
    from public.activity_logs
    where linked_entity_id = '98600000-0000-0000-0000-000000000001'
      and metadata ->> 'table_name' = 'quotation_items'
      and metadata ->> 'schema_name' = 'public'
      and metadata ->> 'quotation_id' = '98500000-0000-0000-0000-000000000001'
  $$,
  array[3::bigint],
  'quotation-item activity metadata records its database source and parent quotation'
);

select * from finish();
rollback;
