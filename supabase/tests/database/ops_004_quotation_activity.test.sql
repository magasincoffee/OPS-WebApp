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
      and c.relname = 'quotations'
      and t.tgname = 'quotations_capture_activity'
      and not t.tgisinternal
  $$,
  array[1::bigint],
  'OPS-004 installs one automatic quotation activity trigger'
);

select results_eq(
  $$
    select p.prosecdef
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'capture_quotation_activity'
      and p.pronargs = 0
  $$,
  array[true],
  'quotation activity capture executes as SECURITY DEFINER'
);

select results_eq(
  $$
    select has_function_privilege(
      'authenticated',
      'public.capture_quotation_activity()',
      'EXECUTE'
    )
  $$,
  array[false],
  'authenticated users cannot directly execute the quotation audit trigger function'
);

insert into auth.users (id, email)
values (
  '97000000-0000-0000-0000-000000000001',
  'ops-quotation-activity@example.test'
);

insert into public.user_roles (user_id, role_id)
select
  '97000000-0000-0000-0000-000000000001'::uuid,
  r.id
from public.roles r
where r.code = 'SALES';

insert into public.customers (id, customer_code, display_name)
values (
  '97100000-0000-0000-0000-000000000001',
  'QUOTATION-ACTIVITY-CUSTOMER',
  'Quotation Activity Customer'
);

-- OPS-030 routes production quotation writes through bounded RPCs.
-- Restore table mutation only inside this rollback-only legacy audit fixture.
grant insert, update, delete on public.quotations to authenticated;

set local role authenticated;
set local request.jwt.claim.sub = '97000000-0000-0000-0000-000000000001';

insert into public.quotations (
  id,
  quotation_number,
  customer_id,
  created_by_user_id
)
values (
  '97200000-0000-0000-0000-000000000001',
  'QT-ACTIVITY-001',
  '97100000-0000-0000-0000-000000000001',
  '97000000-0000-0000-0000-000000000001'
);

update public.quotations
set notes = 'Updated quotation audit fixture'
where id = '97200000-0000-0000-0000-000000000001';

delete from public.quotations
where id = '97200000-0000-0000-0000-000000000001';

reset role;

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_type = 'QUOTATION'
      and linked_entity_id = '97200000-0000-0000-0000-000000000001'
  ),
  3::bigint,
  'create/update/delete each append one quotation activity record'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '97200000-0000-0000-0000-000000000001'
      and action_type = 'QUOTATION_CREATED'
      and before_data is null
      and after_data ->> 'quotation_number' = 'QT-ACTIVITY-001'
  ),
  1::bigint,
  'quotation creation captures the post-change snapshot'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '97200000-0000-0000-0000-000000000001'
      and action_type = 'QUOTATION_UPDATED'
      and before_data ->> 'notes' is null
      and after_data ->> 'notes' = 'Updated quotation audit fixture'
  ),
  1::bigint,
  'quotation update captures before and after snapshots'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '97200000-0000-0000-0000-000000000001'
      and action_type = 'QUOTATION_DELETED'
      and before_data ->> 'quotation_number' = 'QT-ACTIVITY-001'
      and after_data is null
  ),
  1::bigint,
  'quotation deletion captures the pre-delete snapshot'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '97200000-0000-0000-0000-000000000001'
      and actor_user_id = '97000000-0000-0000-0000-000000000001'
  ),
  3::bigint,
  'all quotation activity rows bind actor identity to auth.uid()'
);

select is(
  (
    select count(*)
    from public.activity_logs
    where linked_entity_id = '97200000-0000-0000-0000-000000000001'
      and event_source = 'USER'
  ),
  3::bigint,
  'authenticated quotation mutations are marked as USER events'
);

select results_eq(
  $$
    select count(*)::bigint
    from public.activity_logs
    where linked_entity_id = '97200000-0000-0000-0000-000000000001'
      and metadata ->> 'table_name' = 'quotations'
      and metadata ->> 'schema_name' = 'public'
  $$,
  array[3::bigint],
  'quotation activity metadata records its database source'
);

select * from finish();
rollback;
