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
      and c.relname = 'price_tiers'
      and t.tgname = 'price_tiers_capture_activity'
      and not t.tgisinternal
  $$,
  array[1::bigint],
  'OPS-004 installs one automatic price-tier activity trigger'
);

select results_eq(
  $$
    select p.prosecdef
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'capture_price_tier_activity'
      and p.pronargs = 0
  $$,
  array[true],
  'price-tier activity capture executes as SECURITY DEFINER'
);

select results_eq(
  $$
    select has_function_privilege(
      'authenticated',
      'public.capture_price_tier_activity()',
      'EXECUTE'
    )
  $$,
  array[false],
  'authenticated users cannot directly execute the price-tier audit trigger function'
);

insert into auth.users (id, email)
values (
  '99950000-0000-0000-0000-000000000001',
  'ops-price-tier-activity@example.test'
);

insert into public.user_roles (user_id, role_id)
select
  '99950000-0000-0000-0000-000000000001'::uuid,
  r.id
from public.roles r
where r.code = 'OWNER_ADMIN';

insert into public.product_categories (
  id,
  category_code,
  name
)
values (
  '99950000-0000-0000-0000-000000000010',
  'TIER-ACTIVITY-CAT',
  'Tier Activity Category'
);

insert into public.products (
  id,
  category_id,
  name,
  product_type
)
values (
  '99950000-0000-0000-0000-000000000011',
  '99950000-0000-0000-0000-000000000010',
  'Tier Activity Product',
  'CUP'
);

insert into public.product_variants (
  id,
  product_id,
  sku_code,
  variant_name,
  base_inventory_unit,
  default_purchase_unit
)
values (
  '99950000-0000-0000-0000-000000000012',
  '99950000-0000-0000-0000-000000000011',
  'SKU-TIER-ACTIVITY',
  'Tier Activity Variant',
  'piece',
  'carton'
);

set local role authenticated;
set local request.jwt.claim.sub = '99950000-0000-0000-0000-000000000001';

insert into public.pricing_rules (
  id,
  name,
  product_variant_id,
  product_type,
  print_mode,
  currency_code,
  priority,
  effective_from,
  is_active
)
values (
  '99950000-0000-0000-0000-000000000020',
  'Price tier parent rule',
  '99950000-0000-0000-0000-000000000012',
  'CUP',
  'PRINTED',
  'VND',
  100,
  date '2026-09-29',
  true
);

insert into public.price_tiers (
  id,
  pricing_rule_id,
  min_quantity_base_units,
  max_quantity_base_units,
  fixed_selling_price_per_base_unit,
  markup_percent,
  margin_percent,
  print_cost_per_base_unit
)
values (
  '99950000-0000-0000-0000-000000000030',
  '99950000-0000-0000-0000-000000000020',
  1000,
  4999,
  1200,
  null,
  null,
  50
);

update public.price_tiers
set
  max_quantity_base_units = 5999,
  fixed_selling_price_per_base_unit = 1300,
  print_cost_per_base_unit = 60
where id = '99950000-0000-0000-0000-000000000030';

delete from public.price_tiers
where id = '99950000-0000-0000-0000-000000000030';

reset role;

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_type = 'PRICE_TIER'
      and linked_entity_id = '99950000-0000-0000-0000-000000000030'
  ),
  3::bigint,
  'create/update/delete each append one price-tier activity record'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '99950000-0000-0000-0000-000000000030'
      and action_type = 'PRICE_TIER_CREATED'
      and before_data is null
      and (after_data ->> 'min_quantity_base_units')::numeric = 1000
      and (after_data ->> 'max_quantity_base_units')::numeric = 4999
      and (after_data ->> 'fixed_selling_price_per_base_unit')::numeric = 1200
      and (after_data ->> 'print_cost_per_base_unit')::numeric = 50
  ),
  1::bigint,
  'price-tier creation captures the post-change tier snapshot'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '99950000-0000-0000-0000-000000000030'
      and action_type = 'PRICE_TIER_UPDATED'
      and (before_data ->> 'max_quantity_base_units')::numeric = 4999
      and (after_data ->> 'max_quantity_base_units')::numeric = 5999
      and (before_data ->> 'fixed_selling_price_per_base_unit')::numeric = 1200
      and (after_data ->> 'fixed_selling_price_per_base_unit')::numeric = 1300
      and (after_data ->> 'print_cost_per_base_unit')::numeric = 60
  ),
  1::bigint,
  'price-tier update captures before and after pricing snapshots'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '99950000-0000-0000-0000-000000000030'
      and action_type = 'PRICE_TIER_DELETED'
      and (before_data ->> 'fixed_selling_price_per_base_unit')::numeric = 1300
      and after_data is null
  ),
  1::bigint,
  'price-tier deletion captures the pre-delete snapshot'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '99950000-0000-0000-0000-000000000030'
      and actor_user_id = '99950000-0000-0000-0000-000000000001'
  ),
  3::bigint,
  'all price-tier activity rows bind actor identity to auth.uid()'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '99950000-0000-0000-0000-000000000030'
      and event_source = 'USER'
  ),
  3::bigint,
  'authenticated price-tier mutations are marked as USER events'
);

select results_eq(
  $$
    select count(*)::bigint
    from public.activity_logs
    where linked_entity_id = '99950000-0000-0000-0000-000000000030'
      and metadata ->> 'table_name' = 'price_tiers'
      and metadata ->> 'schema_name' = 'public'
      and metadata ->> 'pricing_rule_id' = '99950000-0000-0000-0000-000000000020'
      and (metadata ->> 'min_quantity_base_units')::numeric = 1000
  $$,
  array[3::bigint],
  'price-tier metadata records its database source and pricing-rule lineage'
);

select * from finish();
rollback;
