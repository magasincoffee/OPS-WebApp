begin;

create extension if not exists pgtap with schema extensions;

select plan(7);

select has_table(
  'public',
  'attachments',
  'OPS-004 creates the attachments metadata table'
);

select has_column(
  'public',
  'attachments',
  'linked_entity_type',
  'attachments records linked entity type'
);

select has_column(
  'public',
  'attachments',
  'storage_path',
  'attachments records the Supabase Storage object path'
);

select has_column(
  'public',
  'attachments',
  'uploaded_by_user_id',
  'attachments records the uploading OPS user when available'
);

select results_eq(
  $$
    select c.relrowsecurity
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'attachments'
      and c.relkind in ('r', 'p')
  $$,
  array[true],
  'RLS is enabled on attachments'
);

select results_eq(
  $$
    select has_table_privilege('authenticated', 'public.attachments', 'UPDATE')
  $$,
  array[false],
  'authenticated users have no direct UPDATE grant on attachment metadata'
);

select results_eq(
  $$
    select has_table_privilege('authenticated', 'public.attachments', 'DELETE')
  $$,
  array[false],
  'authenticated users have no direct DELETE grant on attachment metadata'
);

select * from finish();
rollback;
