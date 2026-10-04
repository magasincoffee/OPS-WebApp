begin;

create extension if not exists pgtap with schema extensions;

select plan(9);

select has_table(
  'public',
  'activity_logs',
  'OPS-004 creates the shared activity_logs table'
);

select has_column(
  'public',
  'activity_logs',
  'linked_entity_type',
  'activity_logs records linked entity type'
);

select has_column(
  'public',
  'activity_logs',
  'action_type',
  'activity_logs records action type'
);

select has_column(
  'public',
  'activity_logs',
  'actor_user_id',
  'activity_logs records the actor when available'
);

select has_trigger(
  'public',
  'activity_logs',
  'activity_logs_prevent_update',
  'activity_logs blocks UPDATE to preserve append-only audit history'
);

select has_trigger(
  'public',
  'activity_logs',
  'activity_logs_prevent_delete',
  'activity_logs blocks DELETE to preserve append-only audit history'
);

select results_eq(
  $$
    select c.relrowsecurity
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'activity_logs'
      and c.relkind in ('r', 'p')
  $$,
  array[true],
  'RLS is enabled on activity_logs'
);

select results_eq(
  $$
    select has_table_privilege('authenticated', 'public.activity_logs', 'INSERT')
  $$,
  array[false],
  'authenticated users cannot forge activity-log inserts directly'
);

select results_eq(
  $$
    select has_table_privilege('authenticated', 'public.activity_logs', 'UPDATE')
      or has_table_privilege('authenticated', 'public.activity_logs', 'DELETE')
  $$,
  array[false],
  'authenticated users have no direct activity-log mutation grants'
);

select * from finish();
rollback;
