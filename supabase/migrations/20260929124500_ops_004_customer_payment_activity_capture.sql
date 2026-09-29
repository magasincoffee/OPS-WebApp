-- OPS-004 bounded unit: customer-payment automatic activity capture
-- Architecture Generation 1
-- Source of Truth: SOURCE_OF_TRUTH.md
--
-- Scope is intentionally limited to automatic activity capture for the
-- customer_payments entity. Other material modules and attachment/storage
-- access remain later bounded work within OPS-004.
--
-- Security posture:
-- - audit rows are written by a SECURITY DEFINER trigger function;
-- - actor identity is derived from auth.uid() and cannot be supplied by clients;
-- - payment deletion is not an authenticated business mutation, so this unit
--   captures the allowed CREATE/UPDATE lifecycle, including VOID updates;
-- - the shared activity_logs table remains append-only and OWNER_ADMIN-readable.

begin;

create or replace function public.capture_customer_payment_activity()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor_user_id uuid := auth.uid();
  v_event_source text := case
    when v_actor_user_id is null then 'SYSTEM'
    else 'USER'
  end;
begin
  if tg_op = 'INSERT' then
    insert into public.activity_logs (
      linked_entity_type,
      linked_entity_id,
      action_type,
      actor_user_id,
      event_source,
      change_summary,
      before_data,
      after_data,
      metadata
    )
    values (
      'CUSTOMER_PAYMENT',
      new.id,
      'CUSTOMER_PAYMENT_CREATED',
      v_actor_user_id,
      v_event_source,
      'Customer payment created',
      null,
      to_jsonb(new),
      jsonb_build_object(
        'schema_name', tg_table_schema,
        'table_name', tg_table_name,
        'operation', tg_op
      )
    );

    return new;
  elsif tg_op = 'UPDATE' then
    insert into public.activity_logs (
      linked_entity_type,
      linked_entity_id,
      action_type,
      actor_user_id,
      event_source,
      change_summary,
      before_data,
      after_data,
      metadata
    )
    values (
      'CUSTOMER_PAYMENT',
      new.id,
      'CUSTOMER_PAYMENT_UPDATED',
      v_actor_user_id,
      v_event_source,
      'Customer payment updated',
      to_jsonb(old),
      to_jsonb(new),
      jsonb_build_object(
        'schema_name', tg_table_schema,
        'table_name', tg_table_name,
        'operation', tg_op
      )
    );

    return new;
  end if;

  raise exception 'Unsupported customer_payments activity operation: %', tg_op;
end;
$$;

revoke all on function public.capture_customer_payment_activity()
from public, anon, authenticated;

drop trigger if exists customer_payments_capture_activity on public.customer_payments;

create trigger customer_payments_capture_activity
after insert or update on public.customer_payments
for each row execute function public.capture_customer_payment_activity();

commit;
