-- OPS-004 bounded unit: quotation automatic activity capture
-- Architecture Generation 1
-- Source of Truth: SOURCE_OF_TRUTH.md
--
-- Scope is intentionally limited to automatic activity capture for the
-- quotations entity. Quotation items, other material modules, and
-- attachment/storage access remain later bounded work within OPS-004.
--
-- Security posture:
-- - audit rows are written by a SECURITY DEFINER trigger function;
-- - actor identity is derived from auth.uid() and cannot be supplied by clients;
-- - the shared activity_logs table remains append-only and OWNER_ADMIN-readable.

begin;

create or replace function public.capture_quotation_activity()
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
      'QUOTATION',
      new.id,
      'QUOTATION_CREATED',
      v_actor_user_id,
      v_event_source,
      'Quotation created',
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
      'QUOTATION',
      new.id,
      'QUOTATION_UPDATED',
      v_actor_user_id,
      v_event_source,
      'Quotation updated',
      to_jsonb(old),
      to_jsonb(new),
      jsonb_build_object(
        'schema_name', tg_table_schema,
        'table_name', tg_table_name,
        'operation', tg_op
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
      'QUOTATION',
      old.id,
      'QUOTATION_DELETED',
      v_actor_user_id,
      v_event_source,
      'Quotation deleted',
      to_jsonb(old),
      null,
      jsonb_build_object(
        'schema_name', tg_table_schema,
        'table_name', tg_table_name,
        'operation', tg_op
      )
    );

    return old;
  end if;

  raise exception 'Unsupported quotations activity operation: %', tg_op;
end;
$$;

revoke all on function public.capture_quotation_activity()
from public, anon, authenticated;

drop trigger if exists quotations_capture_activity on public.quotations;

create trigger quotations_capture_activity
after insert or update or delete on public.quotations
for each row execute function public.capture_quotation_activity();

commit;
