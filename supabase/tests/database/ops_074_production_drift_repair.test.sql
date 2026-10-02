begin;

create extension if not exists pgtap with schema extensions;

select plan(5);

select ok(
  to_regprocedure('private.valid_customer_payment_total(uuid)') is not null,
  'OPS-074 production drift repair restores receivable helper'
);

select is(
  has_function_privilege('anon','private.valid_customer_payment_total(uuid)','EXECUTE'),
  false,
  'anon cannot execute receivable helper'
);

select is(
  has_function_privilege('authenticated','private.valid_customer_payment_total(uuid)','EXECUTE'),
  true,
  'authenticated may execute receivable helper through bounded role checks'
);

select results_eq(
  $$select count(*)::bigint
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='private'
      and p.proname='valid_customer_payment_total'
      and p.prosecdef$$,
  array[1::bigint],
  'receivable helper remains SECURITY DEFINER in private schema'
);

select results_eq(
  $$select coalesce(c.reloptions @> array['security_invoker=true']::text[], false)
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname='public'
      and c.relname='production_print_job_queue'$$,
  array[true],
  'production print queue enforces security_invoker'
);

select * from finish();
rollback;
