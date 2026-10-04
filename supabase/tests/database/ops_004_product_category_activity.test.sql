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
      and c.relname = 'product_categories'
      and t.tgname = 'product_categories_capture_activity'
      and not t.tgisinternal
  $$,
  array[1::bigint],
  'OPS-004 installs one automatic product-category activity trigger'
);

select results_eq(
  $$
    select p.prosecdef
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'capture_product_category_activity'
      and p.pronargs = 0
  $$,
  array[true],
  'product-category activity capture executes as SECURITY DEFINER'
);

select results_eq(
  $$
    select has_function_privilege(
      'authenticated',
      'public.capture_product_category_activity()',
      'EXECUTE'
    )
  $$,
  array[false],
  'authenticated users cannot directly execute the product-category audit trigger function'
);

insert into auth.users (id, email)
values (
  '99700000-0000-0000-0000-000000000001',
  'ops-product-category-activity@example.test'
);

insert into public.user_roles (user_id, role_id)
select
  '99700000-0000-0000-0000-000000000001'::uuid,
  r.id
from public.roles r
where r.code = 'OWNER_ADMIN';

set local role authenticated;
set local request.jwt.claim.sub = '99700000-0000-0000-0000-000000000001';

insert into public.product_categories (
  id,
  category_code,
  name,
  description
)
values (
  '99800000-0000-0000-0000-000000000001',
  'CAT-ACTIVITY-INITIAL',
  'Category Activity Initial',
  'Initial category description'
);

update public.product_categories
set
  category_code = 'CAT-ACTIVITY-UPDATED',
  name = 'Category Activity Updated',
  description = 'Updated category description'
where id = '99800000-0000-0000-0000-000000000001';

delete from public.product_categories
where id = '99800000-0000-0000-0000-000000000001';

reset role;

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_type = 'PRODUCT_CATEGORY'
      and linked_entity_id = '99800000-0000-0000-0000-000000000001'
  ),
  3::bigint,
  'create/update/delete each append one product-category activity record'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '99800000-0000-0000-0000-000000000001'
      and action_type = 'PRODUCT_CATEGORY_CREATED'
      and before_data is null
      and after_data ->> 'category_code' = 'CAT-ACTIVITY-INITIAL'
      and after_data ->> 'name' = 'Category Activity Initial'
  ),
  1::bigint,
  'product-category creation captures the post-change snapshot'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '99800000-0000-0000-0000-000000000001'
      and action_type = 'PRODUCT_CATEGORY_UPDATED'
      and before_data ->> 'category_code' = 'CAT-ACTIVITY-INITIAL'
      and after_data ->> 'category_code' = 'CAT-ACTIVITY-UPDATED'
      and before_data ->> 'description' = 'Initial category description'
      and after_data ->> 'description' = 'Updated category description'
  ),
  1::bigint,
  'product-category update captures before and after snapshots'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '99800000-0000-0000-0000-000000000001'
      and action_type = 'PRODUCT_CATEGORY_DELETED'
      and before_data ->> 'name' = 'Category Activity Updated'
      and after_data is null
  ),
  1::bigint,
  'product-category deletion captures the pre-delete snapshot'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '99800000-0000-0000-0000-000000000001'
      and actor_user_id = '99700000-0000-0000-0000-000000000001'
  ),
  3::bigint,
  'all product-category activity rows bind actor identity to auth.uid()'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '99800000-0000-0000-0000-000000000001'
      and event_source = 'USER'
  ),
  3::bigint,
  'authenticated product-category mutations are marked as USER events'
);

select results_eq(
  $$
    select count(*)::bigint
    from public.activity_logs
    where linked_entity_id = '99800000-0000-0000-0000-000000000001'
      and metadata ->> 'table_name' = 'product_categories'
      and metadata ->> 'schema_name' = 'public'
      and metadata ->> 'category_code' in (
        'CAT-ACTIVITY-INITIAL',
        'CAT-ACTIVITY-UPDATED'
      )
  $$,
  array[3::bigint],
  'product-category activity metadata records its database source and category code'
);

select * from finish();
rollback;
