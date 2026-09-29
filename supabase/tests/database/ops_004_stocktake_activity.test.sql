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
      and c.relname = 'stocktakes'
      and t.tgname = 'stocktakes_capture_activity'
      and not t.tgisinternal
  $$,
  array[1::bigint],
  'OPS-004 installs one automatic stocktake activity trigger'
);

select results_eq(
  $$
    select p.prosecdef
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'capture_stocktake_activity'
      and p.pronargs = 0
  $$,
  array[true],
  'stocktake activity capture executes as SECURITY DEFINER'
);

select results_eq(
  $$
    select has_function_privilege(
      'authenticated',
      'public.capture_stocktake_activity()',
      'EXECUTE'
    )
  $$,
  array[false],
  'authenticated users cannot directly execute the stocktake audit trigger function'
);

insert into auth.users (id, email)
values (
  '9b100000-0000-0000-0000-000000000001',
  'ops-stocktake-activity-owner@example.test'
);

insert into public.user_roles (user_id, role_id)
select
  '9b100000-0000-0000-0000-000000000001'::uuid,
  r.id
from public.roles r
where r.code = 'OWNER_ADMIN';

set local role authenticated;
set local request.jwt.claim.sub = '9b100000-0000-0000-0000-000000000001';

insert into public.stocktakes (
  id, stocktake_number, stocktake_date, status, created_by_user_id, notes
)
values (
  '9b200000-0000-0000-0000-000000000001',
  'ST-ACTIVITY-001',
  date '2026-09-29',
  'DRAFT',
  '9b100000-0000-0000-0000-000000000001',
  'Initial stocktake note'
);

update public.stocktakes
set status = 'COUNTED',
    counted_at = timestamptz '2026-09-29 10:00:00+00',
    notes = 'Counted stocktake note'
where id = '9b200000-0000-0000-0000-000000000001';

delete from public.stocktakes
where id = '9b200000-0000-0000-0000-000000000001';

reset role;

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_type = 'STOCKTAKE'
      and linked_entity_id = '9b200000-0000-0000-0000-000000000001'
  ),
  3::bigint,
  'create/update/delete each append one stocktake activity record'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '9b200000-0000-0000-0000-000000000001'
      and action_type = 'STOCKTAKE_CREATED'
      and before_data is null
      and after_data ->> 'status' = 'DRAFT'
      and after_data ->> 'notes' = 'Initial stocktake note'
  ),
  1::bigint,
  'stocktake creation captures the post-change snapshot'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '9b200000-0000-0000-0000-000000000001'
      and action_type = 'STOCKTAKE_UPDATED'
      and before_data ->> 'status' = 'DRAFT'
      and after_data ->> 'status' = 'COUNTED'
      and before_data ->> 'notes' = 'Initial stocktake note'
      and after_data ->> 'notes' = 'Counted stocktake note'
  ),
  1::bigint,
  'stocktake update captures before and after snapshots'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '9b200000-0000-0000-0000-000000000001'
      and action_type = 'STOCKTAKE_DELETED'
      and before_data ->> 'status' = 'COUNTED'
      and after_data is null
  ),
  1::bigint,
  'stocktake deletion captures the pre-delete snapshot'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '9b200000-0000-0000-0000-000000000001'
      and actor_user_id = '9b100000-0000-0000-0000-000000000001'
  ),
  3::bigint,
  'all stocktake activity rows bind actor identity to auth.uid()'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '9b200000-0000-0000-0000-000000000001'
      and event_source = 'USER'
  ),
  3::bigint,
  'authenticated stocktake mutations are marked as USER events'
);

select results_eq(
  $$
    select count(*)::bigint
    from public.activity_logs
    where linked_entity_id = '9b200000-0000-0000-0000-000000000001'
      and metadata ->> 'table_name' = 'stocktakes'
      and metadata ->> 'schema_name' = 'public'
  $$,
  array[3::bigint],
  'stocktake activity metadata records its database source'
);

select results_eq(
  $$
    select count(*)::bigint
    from public.activity_logs
    where linked_entity_id = '9b200000-0000-0000-0000-000000000001'
      and metadata ->> 'stocktake_number' = 'ST-ACTIVITY-001'
  $$,
  array[3::bigint],
  'stocktake activity metadata preserves stocktake identity'
);

select * from finish();
rollback;
