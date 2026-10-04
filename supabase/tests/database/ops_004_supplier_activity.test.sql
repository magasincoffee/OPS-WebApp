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
      and c.relname = 'suppliers'
      and t.tgname = 'suppliers_capture_activity'
      and not t.tgisinternal
  $$,
  array[1::bigint],
  'OPS-004 installs one automatic supplier activity trigger'
);

select results_eq(
  $$
    select p.prosecdef
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'capture_supplier_activity'
      and p.pronargs = 0
  $$,
  array[true],
  'supplier activity capture executes as SECURITY DEFINER'
);

select results_eq(
  $$
    select has_function_privilege(
      'authenticated',
      'public.capture_supplier_activity()',
      'EXECUTE'
    )
  $$,
  array[false],
  'authenticated users cannot directly execute the supplier audit trigger function'
);

insert into auth.users (id, email)
values (
  '98200000-0000-0000-0000-000000000001',
  'ops-supplier-activity@example.test'
);

insert into public.user_roles (user_id, role_id)
select
  '98200000-0000-0000-0000-000000000001'::uuid,
  r.id
from public.roles r
where r.code = 'OWNER_ADMIN';

set local role authenticated;
set local request.jwt.claim.sub = '98200000-0000-0000-0000-000000000001';

insert into public.suppliers (
  id,
  supplier_code,
  supplier_name,
  contact_name
)
values (
  '98300000-0000-0000-0000-000000000001',
  'SUPPLIER-ACTIVITY-001',
  'Supplier Activity Initial',
  'Initial Contact'
);

update public.suppliers
set supplier_name = 'Supplier Activity Updated'
where id = '98300000-0000-0000-0000-000000000001';

delete from public.suppliers
where id = '98300000-0000-0000-0000-000000000001';

reset role;

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_type = 'SUPPLIER'
      and linked_entity_id = '98300000-0000-0000-0000-000000000001'
  ),
  3::bigint,
  'create/update/delete each append one supplier activity record'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '98300000-0000-0000-0000-000000000001'
      and action_type = 'SUPPLIER_CREATED'
      and before_data is null
      and after_data ->> 'supplier_code' = 'SUPPLIER-ACTIVITY-001'
      and after_data ->> 'supplier_name' = 'Supplier Activity Initial'
  ),
  1::bigint,
  'supplier creation captures the post-change snapshot'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '98300000-0000-0000-0000-000000000001'
      and action_type = 'SUPPLIER_UPDATED'
      and before_data ->> 'supplier_name' = 'Supplier Activity Initial'
      and after_data ->> 'supplier_name' = 'Supplier Activity Updated'
  ),
  1::bigint,
  'supplier update captures before and after snapshots'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '98300000-0000-0000-0000-000000000001'
      and action_type = 'SUPPLIER_DELETED'
      and before_data ->> 'supplier_code' = 'SUPPLIER-ACTIVITY-001'
      and before_data ->> 'supplier_name' = 'Supplier Activity Updated'
      and after_data is null
  ),
  1::bigint,
  'supplier deletion captures the pre-delete snapshot'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '98300000-0000-0000-0000-000000000001'
      and actor_user_id = '98200000-0000-0000-0000-000000000001'
  ),
  3::bigint,
  'all supplier activity rows bind actor identity to auth.uid()'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '98300000-0000-0000-0000-000000000001'
      and event_source = 'USER'
  ),
  3::bigint,
  'authenticated supplier mutations are marked as USER events'
);

select results_eq(
  $$
    select count(*)::bigint
    from public.activity_logs
    where linked_entity_id = '98300000-0000-0000-0000-000000000001'
      and metadata ->> 'table_name' = 'suppliers'
      and metadata ->> 'schema_name' = 'public'
  $$,
  array[3::bigint],
  'supplier activity metadata records its database source'
);

select * from finish();
rollback;
