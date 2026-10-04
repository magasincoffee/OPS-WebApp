-- OPS-004 bounded unit: pricing-rule automatic activity capture
-- Architecture Generation 1
-- Source of Truth: SOURCE_OF_TRUTH.md
--
-- Scope is intentionally limited to automatic activity capture for
-- pricing_rules. Price tiers, other material modules, and attachment/storage
-- access remain later bounded work within OPS-004.
--
-- Security posture:
-- - audit rows are written by a SECURITY DEFINER trigger function;
-- - actor identity is derived from auth.uid() and cannot be supplied by clients;
-- - the shared activity_logs table remains append-only and OWNER_ADMIN-readable.

begin;

create or replace function public.capture_pricing_rule_activity()
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
      'PRICING_RULE',
      new.id,
      'PRICING_RULE_CREATED',
      v_actor_user_id,
      v_event_source,
      'Pricing rule created',
      null,
      to_jsonb(new),
      jsonb_build_object(
        'schema_name', tg_table_schema,
        'table_name', tg_table_name,
        'operation', tg_op,
        'product_variant_id', new.product_variant_id,
        'product_type', new.product_type,
        'print_mode', new.print_mode,
        'currency_code', new.currency_code,
        'priority', new.priority,
        'effective_from', new.effective_from,
        'effective_to', new.effective_to,
        'is_active', new.is_active
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
      'PRICING_RULE',
      new.id,
      'PRICING_RULE_UPDATED',
      v_actor_user_id,
      v_event_source,
      'Pricing rule updated',
      to_jsonb(old),
      to_jsonb(new),
      jsonb_build_object(
        'schema_name', tg_table_schema,
        'table_name', tg_table_name,
        'operation', tg_op,
        'product_variant_id', new.product_variant_id,
        'product_type', new.product_type,
        'print_mode', new.print_mode,
        'currency_code', new.currency_code,
        'priority', new.priority,
        'effective_from', new.effective_from,
        'effective_to', new.effective_to,
        'is_active', new.is_active
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
      'PRICING_RULE',
      old.id,
      'PRICING_RULE_DELETED',
      v_actor_user_id,
      v_event_source,
      'Pricing rule deleted',
      to_jsonb(old),
      null,
      jsonb_build_object(
        'schema_name', tg_table_schema,
        'table_name', tg_table_name,
        'operation', tg_op,
        'product_variant_id', old.product_variant_id,
        'product_type', old.product_type,
        'print_mode', old.print_mode,
        'currency_code', old.currency_code,
        'priority', old.priority,
        'effective_from', old.effective_from,
        'effective_to', old.effective_to,
        'is_active', old.is_active
      )
    );

    return old;
  end if;

  raise exception 'Unsupported pricing_rules activity operation: %', tg_op;
end;
$$;

revoke all on function public.capture_pricing_rule_activity()
from public, anon, authenticated;

drop trigger if exists pricing_rules_capture_activity
on public.pricing_rules;

create trigger pricing_rules_capture_activity
after insert or update or delete on public.pricing_rules
for each row execute function public.capture_pricing_rule_activity();

commit;
