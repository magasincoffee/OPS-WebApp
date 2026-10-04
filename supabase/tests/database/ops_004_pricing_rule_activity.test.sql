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
      and c.relname = 'pricing_rules'
      and t.tgname = 'pricing_rules_capture_activity'
      and not t.tgisinternal
  $$,
  array[1::bigint],
  'OPS-004 installs one automatic pricing-rule activity trigger'
);

select results_eq(
  $$
    select p.prosecdef
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'capture_pricing_rule_activity'
      and p.pronargs = 0
  $$,
  array[true],
  'pricing-rule activity capture executes as SECURITY DEFINER'
);

select results_eq(
  $$
    select has_function_privilege(
      'authenticated',
      'public.capture_pricing_rule_activity()',
      'EXECUTE'
    )
  $$,
  array[false],
  'authenticated users cannot directly execute the pricing-rule audit trigger function'
);

insert into auth.users (id, email)
values (
  '99940000-0000-0000-0000-000000000001',
  'ops-pricing-rule-activity@example.test'
);

insert into public.user_roles (user_id, role_id)
select
  '99940000-0000-0000-0000-000000000001'::uuid,
  r.id
from public.roles r
where r.code = 'OWNER_ADMIN';

insert into public.product_categories (
  id,
  category_code,
  name
)
values (
  '99940000-0000-0000-0000-000000000010',
  'PRICE-ACTIVITY-CAT',
  'Pricing Activity Category'
);

insert into public.products (
  id,
  category_id,
  name,
  product_type
)
values (
  '99940000-0000-0000-0000-000000000011',
  '99940000-0000-0000-0000-000000000010',
  'Pricing Activity Product',
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
  '99940000-0000-0000-0000-000000000012',
  '99940000-0000-0000-0000-000000000011',
  'SKU-PRICE-ACTIVITY',
  'Pricing Activity Variant',
  'piece',
  'carton'
);

set local role authenticated;
set local request.jwt.claim.sub = '99940000-0000-0000-0000-000000000001';

insert into public.pricing_rules (
  id,
  name,
  product_variant_id,
  product_type,
  print_mode,
  min_print_colors,
  max_print_colors,
  currency_code,
  priority,
  effective_from,
  effective_to,
  is_active
)
values (
  '99940000-0000-0000-0000-000000000020',
  'Initial pricing rule',
  '99940000-0000-0000-0000-000000000012',
  'CUP',
  'PRINTED',
  1,
  2,
  'VND',
  100,
  date '2026-09-29',
  null,
  true
);

update public.pricing_rules
set
  name = 'Updated pricing rule',
  max_print_colors = 3,
  priority = 90,
  is_active = false
where id = '99940000-0000-0000-0000-000000000020';

delete from public.pricing_rules
where id = '99940000-0000-0000-0000-000000000020';

reset role;

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_type = 'PRICING_RULE'
      and linked_entity_id = '99940000-0000-0000-0000-000000000020'
  ),
  3::bigint,
  'create/update/delete each append one pricing-rule activity record'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '99940000-0000-0000-0000-000000000020'
      and action_type = 'PRICING_RULE_CREATED'
      and before_data is null
      and after_data ->> 'name' = 'Initial pricing rule'
      and after_data ->> 'print_mode' = 'PRINTED'
      and (after_data ->> 'priority')::integer = 100
  ),
  1::bigint,
  'pricing-rule creation captures the post-change pricing snapshot'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '99940000-0000-0000-0000-000000000020'
      and action_type = 'PRICING_RULE_UPDATED'
      and before_data ->> 'name' = 'Initial pricing rule'
      and after_data ->> 'name' = 'Updated pricing rule'
      and (before_data ->> 'priority')::integer = 100
      and (after_data ->> 'priority')::integer = 90
      and (after_data ->> 'is_active')::boolean = false
  ),
  1::bigint,
  'pricing-rule update captures before and after pricing snapshots'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '99940000-0000-0000-0000-000000000020'
      and action_type = 'PRICING_RULE_DELETED'
      and before_data ->> 'name' = 'Updated pricing rule'
      and after_data is null
  ),
  1::bigint,
  'pricing-rule deletion captures the pre-delete snapshot'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '99940000-0000-0000-0000-000000000020'
      and actor_user_id = '99940000-0000-0000-0000-000000000001'
  ),
  3::bigint,
  'all pricing-rule activity rows bind actor identity to auth.uid()'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '99940000-0000-0000-0000-000000000020'
      and event_source = 'USER'
  ),
  3::bigint,
  'authenticated pricing-rule mutations are marked as USER events'
);

select results_eq(
  $$
    select count(*)::bigint
    from public.activity_logs
    where linked_entity_id = '99940000-0000-0000-0000-000000000020'
      and metadata ->> 'table_name' = 'pricing_rules'
      and metadata ->> 'schema_name' = 'public'
      and metadata ->> 'product_variant_id' = '99940000-0000-0000-0000-000000000012'
      and metadata ->> 'product_type' = 'CUP'
      and metadata ->> 'print_mode' = 'PRINTED'
      and metadata ->> 'currency_code' = 'VND'
  $$,
  array[3::bigint],
  'pricing-rule metadata records its database source and pricing lineage'
);

select * from finish();
rollback;
