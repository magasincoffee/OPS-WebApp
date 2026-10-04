-- OPS-004 bounded unit: customer-ledger-entry automatic activity capture
-- Architecture Generation 1
-- Source of Truth: SOURCE_OF_TRUTH.md
--
-- Scope is intentionally limited to automatic activity capture for the
-- append-only customer_ledger_entries receivables ledger. Other material
-- modules and attachment/storage access remain later bounded work within OPS-004.
--
-- Security posture:
-- - customer ledger entries are immutable after insertion, so only CREATE
--   events are captured;
-- - audit rows are written by a SECURITY DEFINER trigger function;
-- - actor identity is derived from auth.uid() and cannot be supplied by clients;
-- - the shared activity_logs table remains append-only and OWNER_ADMIN-readable.

begin;

create or replace function public.capture_customer_ledger_entry_activity()
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
  if tg_op <> 'INSERT' then
    raise exception 'Unsupported customer_ledger_entries activity operation: %', tg_op;
  end if;

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
    'CUSTOMER_LEDGER_ENTRY',
    new.id,
    'CUSTOMER_LEDGER_ENTRY_CREATED',
    v_actor_user_id,
    v_event_source,
    'Customer ledger entry recorded',
    null,
    to_jsonb(new),
    jsonb_build_object(
      'schema_name', tg_table_schema,
      'table_name', tg_table_name,
      'operation', tg_op,
      'entry_type', new.entry_type,
      'customer_id', new.customer_id,
      'sales_order_id', new.sales_order_id,
      'customer_payment_id', new.customer_payment_id
    )
  );

  return new;
end;
$$;

revoke all on function public.capture_customer_ledger_entry_activity()
from public, anon, authenticated;

drop trigger if exists customer_ledger_entries_capture_activity
on public.customer_ledger_entries;

create trigger customer_ledger_entries_capture_activity
after insert on public.customer_ledger_entries
for each row execute function public.capture_customer_ledger_entry_activity();

commit;
