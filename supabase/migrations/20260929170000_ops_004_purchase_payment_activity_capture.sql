-- OPS-004 bounded unit: purchase-payment automatic activity capture
-- Architecture Generation 1
-- Source of Truth: SOURCE_OF_TRUTH.md
--
-- Scope is intentionally limited to automatic activity capture for
-- purchase_payments. Other material modules and attachment/storage access
-- remain later bounded work within OPS-004.
--
-- Security posture:
-- - audit rows are written by a SECURITY DEFINER trigger function;
-- - actor identity is derived from auth.uid() and cannot be supplied by clients;
-- - the trigger function has a pinned search_path and no direct authenticated
--   EXECUTE privilege;
-- - the shared activity_logs table remains append-only and OWNER_ADMIN-readable.

begin;

create or replace function public.capture_purchase_payment_activity()
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
      'PURCHASE_PAYMENT',
      new.id,
      'PURCHASE_PAYMENT_CREATED',
      v_actor_user_id,
      v_event_source,
      'Purchase payment created',
      null,
      to_jsonb(new),
      jsonb_build_object(
        'schema_name', tg_table_schema,
        'table_name', tg_table_name,
        'operation', tg_op,
        'purchase_order_id', new.purchase_order_id
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
      'PURCHASE_PAYMENT',
      new.id,
      'PURCHASE_PAYMENT_UPDATED',
      v_actor_user_id,
      v_event_source,
      'Purchase payment updated',
      to_jsonb(old),
      to_jsonb(new),
      jsonb_build_object(
        'schema_name', tg_table_schema,
        'table_name', tg_table_name,
        'operation', tg_op,
        'purchase_order_id', new.purchase_order_id
      )
    );

    return new;
  elsif tg_op = 'DELETE' then
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
      'PURCHASE_PAYMENT',
      old.id,
      'PURCHASE_PAYMENT_DELETED',
      v_actor_user_id,
      v_event_source,
      'Purchase payment deleted',
      to_jsonb(old),
      null,
      jsonb_build_object(
        'schema_name', tg_table_schema,
        'table_name', tg_table_name,
        'operation', tg_op,
        'purchase_order_id', old.purchase_order_id
      )
    );

    return old;
  end if;

  raise exception 'Unsupported purchase_payments activity operation: %', tg_op;
end;
$$;

revoke all on function public.capture_purchase_payment_activity()
from public, anon, authenticated;

drop trigger if exists purchase_payments_capture_activity on public.purchase_payments;

create trigger purchase_payments_capture_activity
after insert or update or delete on public.purchase_payments
for each row execute function public.capture_purchase_payment_activity();

commit;
