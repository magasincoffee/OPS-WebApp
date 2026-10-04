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
      and c.relname = 'purchase_cost_history'
      and t.tgname = 'purchase_cost_history_capture_activity'
      and not t.tgisinternal
  $$,
  array[1::bigint],
  'OPS-004 installs one automatic purchase-cost-history activity trigger'
);

select results_eq(
  $$
    select p.prosecdef
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'capture_purchase_cost_history_activity'
      and p.pronargs = 0
  $$,
  array[true],
  'purchase-cost-history activity capture executes as SECURITY DEFINER'
);

select results_eq(
  $$
    select has_function_privilege(
      'authenticated',
      'public.capture_purchase_cost_history_activity()',
      'EXECUTE'
    )
  $$,
  array[false],
  'authenticated users cannot directly execute the purchase-cost-history audit trigger function'
);

insert into auth.users (id, email)
values (
  '99930000-0000-0000-0000-000000000001',
  'ops-purchase-cost-activity@example.test'
);

insert into public.user_roles (user_id, role_id)
select
  '99930000-0000-0000-0000-000000000001'::uuid,
  r.id
from public.roles r
where r.code = 'OWNER_ADMIN';

insert into public.product_categories (
  id,
  category_code,
  name
)
values (
  '99930000-0000-0000-0000-000000000010',
  'COST-ACTIVITY-CAT',
  'Cost Activity Category'
);

insert into public.products (
  id,
  category_id,
  name,
  product_type
)
values (
  '99930000-0000-0000-0000-000000000011',
  '99930000-0000-0000-0000-000000000010',
  'Cost Activity Product',
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
  '99930000-0000-0000-0000-000000000012',
  '99930000-0000-0000-0000-000000000011',
  'SKU-COST-ACTIVITY',
  'Cost Activity Variant',
  'piece',
  'carton'
);

insert into public.suppliers (
  id,
  supplier_code,
  supplier_name
)
values (
  '99930000-0000-0000-0000-000000000013',
  'SUP-COST-ACTIVITY',
  'Cost Activity Supplier'
);

insert into public.product_packaging (
  id,
  product_variant_id,
  package_code,
  package_name,
  units_per_package,
  is_purchase_default
)
values (
  '99930000-0000-0000-0000-000000000014',
  '99930000-0000-0000-0000-000000000012',
  'CTN-COST-ACTIVITY',
  'Cost Activity Carton',
  1000,
  true
);

set local role authenticated;
set local request.jwt.claim.sub = '99930000-0000-0000-0000-000000000001';

insert into public.purchase_cost_history (
  id,
  product_variant_id,
  supplier_id,
  packaging_id,
  purchase_unit,
  units_per_purchase_unit,
  purchase_price_per_purchase_unit,
  freight_cost_per_purchase_unit,
  other_allocated_cost_per_purchase_unit,
  inventory_cost_basis_per_base_unit,
  source_reference,
  notes
)
values (
  '99930000-0000-0000-0000-000000000020',
  '99930000-0000-0000-0000-000000000012',
  '99930000-0000-0000-0000-000000000013',
  '99930000-0000-0000-0000-000000000014',
  'carton',
  1000,
  120000,
  10000,
  5000,
  135,
  'PO-COST-INITIAL',
  'Initial cost history snapshot'
);

update public.purchase_cost_history
set
  purchase_price_per_purchase_unit = 125000,
  freight_cost_per_purchase_unit = 12000,
  source_reference = 'PO-COST-UPDATED',
  notes = 'Updated cost history snapshot'
where id = '99930000-0000-0000-0000-000000000020';

delete from public.purchase_cost_history
where id = '99930000-0000-0000-0000-000000000020';

reset role;

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_type = 'PURCHASE_COST_HISTORY'
      and linked_entity_id = '99930000-0000-0000-0000-000000000020'
  ),
  3::bigint,
  'create/update/delete each append one purchase-cost-history activity record'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '99930000-0000-0000-0000-000000000020'
      and action_type = 'PURCHASE_COST_HISTORY_CREATED'
      and before_data is null
      and (after_data ->> 'purchase_price_per_purchase_unit')::numeric = 120000
      and after_data ->> 'source_reference' = 'PO-COST-INITIAL'
  ),
  1::bigint,
  'purchase-cost-history creation captures the post-change cost snapshot'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '99930000-0000-0000-0000-000000000020'
      and action_type = 'PURCHASE_COST_HISTORY_UPDATED'
      and (before_data ->> 'purchase_price_per_purchase_unit')::numeric = 120000
      and (after_data ->> 'purchase_price_per_purchase_unit')::numeric = 125000
      and before_data ->> 'source_reference' = 'PO-COST-INITIAL'
      and after_data ->> 'source_reference' = 'PO-COST-UPDATED'
  ),
  1::bigint,
  'purchase-cost-history update captures before and after cost snapshots'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '99930000-0000-0000-0000-000000000020'
      and action_type = 'PURCHASE_COST_HISTORY_DELETED'
      and before_data ->> 'source_reference' = 'PO-COST-UPDATED'
      and after_data is null
  ),
  1::bigint,
  'purchase-cost-history deletion captures the pre-delete snapshot'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '99930000-0000-0000-0000-000000000020'
      and actor_user_id = '99930000-0000-0000-0000-000000000001'
  ),
  3::bigint,
  'all purchase-cost-history activity rows bind actor identity to auth.uid()'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '99930000-0000-0000-0000-000000000020'
      and event_source = 'USER'
  ),
  3::bigint,
  'authenticated purchase-cost-history mutations are marked as USER events'
);

select results_eq(
  $$
    select count(*)::bigint
    from public.activity_logs
    where linked_entity_id = '99930000-0000-0000-0000-000000000020'
      and metadata ->> 'table_name' = 'purchase_cost_history'
      and metadata ->> 'schema_name' = 'public'
      and metadata ->> 'product_variant_id' = '99930000-0000-0000-0000-000000000012'
      and metadata ->> 'supplier_id' = '99930000-0000-0000-0000-000000000013'
      and metadata ->> 'packaging_id' = '99930000-0000-0000-0000-000000000014'
      and metadata ->> 'source_reference' in ('PO-COST-INITIAL', 'PO-COST-UPDATED')
  $$,
  array[3::bigint],
  'purchase-cost-history metadata records its database source and cost lineage'
);

select * from finish();
rollback;
