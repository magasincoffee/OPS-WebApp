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
      and c.relname = 'products'
      and t.tgname = 'products_capture_activity'
      and not t.tgisinternal
  $$,
  array[1::bigint],
  'OPS-004 installs one automatic product activity trigger'
);

select results_eq(
  $$
    select p.prosecdef
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'capture_product_activity'
      and p.pronargs = 0
  $$,
  array[true],
  'product activity capture executes as SECURITY DEFINER'
);

select results_eq(
  $$
    select has_function_privilege(
      'authenticated',
      'public.capture_product_activity()',
      'EXECUTE'
    )
  $$,
  array[false],
  'authenticated users cannot directly execute the product audit trigger function'
);

insert into auth.users (id, email)
values (
  '98400000-0000-0000-0000-000000000001',
  'ops-product-activity@example.test'
);

insert into public.user_roles (user_id, role_id)
select
  '98400000-0000-0000-0000-000000000001'::uuid,
  r.id
from public.roles r
where r.code = 'OWNER_ADMIN';

set local role authenticated;
set local request.jwt.claim.sub = '98400000-0000-0000-0000-000000000001';

insert into public.product_categories (
  id,
  category_code,
  name
)
values (
  '98500000-0000-0000-0000-000000000001',
  'PRODUCT-ACTIVITY-CATEGORY',
  'Product Activity Category'
);

insert into public.products (
  id,
  category_id,
  name,
  product_type,
  description
)
values (
  '98600000-0000-0000-0000-000000000001',
  '98500000-0000-0000-0000-000000000001',
  'Product Activity Initial',
  'CUP',
  'Initial product description'
);

update public.products
set
  name = 'Product Activity Updated',
  description = 'Updated product description'
where id = '98600000-0000-0000-0000-000000000001';

delete from public.products
where id = '98600000-0000-0000-0000-000000000001';

reset role;

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_type = 'PRODUCT'
      and linked_entity_id = '98600000-0000-0000-0000-000000000001'
  ),
  3::bigint,
  'create/update/delete each append one product activity record'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '98600000-0000-0000-0000-000000000001'
      and action_type = 'PRODUCT_CREATED'
      and before_data is null
      and after_data ->> 'name' = 'Product Activity Initial'
      and after_data ->> 'product_type' = 'CUP'
  ),
  1::bigint,
  'product creation captures the post-change snapshot'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '98600000-0000-0000-0000-000000000001'
      and action_type = 'PRODUCT_UPDATED'
      and before_data ->> 'name' = 'Product Activity Initial'
      and after_data ->> 'name' = 'Product Activity Updated'
      and before_data ->> 'description' = 'Initial product description'
      and after_data ->> 'description' = 'Updated product description'
  ),
  1::bigint,
  'product update captures before and after snapshots'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '98600000-0000-0000-0000-000000000001'
      and action_type = 'PRODUCT_DELETED'
      and before_data ->> 'name' = 'Product Activity Updated'
      and after_data is null
  ),
  1::bigint,
  'product deletion captures the pre-delete snapshot'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '98600000-0000-0000-0000-000000000001'
      and actor_user_id = '98400000-0000-0000-0000-000000000001'
  ),
  3::bigint,
  'all product activity rows bind actor identity to auth.uid()'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '98600000-0000-0000-0000-000000000001'
      and event_source = 'USER'
  ),
  3::bigint,
  'authenticated product mutations are marked as USER events'
);

select results_eq(
  $$
    select count(*)::bigint
    from public.activity_logs
    where linked_entity_id = '98600000-0000-0000-0000-000000000001'
      and metadata ->> 'table_name' = 'products'
      and metadata ->> 'schema_name' = 'public'
      and metadata ->> 'category_id' = '98500000-0000-0000-0000-000000000001'
  $$,
  array[3::bigint],
  'product activity metadata records its database source and category linkage'
);

select * from finish();
rollback;
