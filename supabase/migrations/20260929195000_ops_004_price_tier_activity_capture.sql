-- OPS-004 bounded unit: price-tier automatic activity capture
-- Architecture Generation 1
-- Source of Truth: SOURCE_OF_TRUTH.md
--
-- Scope is intentionally limited to automatic activity capture for
-- price_tiers. Other material modules and attachment/storage access remain
-- later bounded work within OPS-004.
--
-- Security posture:
-- - audit rows are written by a SECURITY DEFINER trigger function;
-- - actor identity is derived from auth.uid() and cannot be supplied by clients;
-- - the shared activity_logs table remains append-only and OWNER_ADMIN-readable.

begin;

create or replace function public.capture_price_tier_activity()
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
      'PRICE_TIER',
      new.id,
      'PRICE_TIER_CREATED',
      v_actor_user_id,
      v_event_source,
      'Price tier created',
      null,
      to_jsonb(new),
      jsonb_build_object(
        'schema_name', tg_table_schema,
        'table_name', tg_table_name,
        'operation', tg_op,
        'pricing_rule_id', new.pricing_rule_id,
        'min_quantity_base_units', new.min_quantity_base_units,
        'max_quantity_base_units', new.max_quantity_base_units,
        'fixed_selling_price_per_base_unit', new.fixed_selling_price_per_base_unit,
        'markup_percent', new.markup_percent,
        'margin_percent', new.margin_percent,
        'print_cost_per_base_unit', new.print_cost_per_base_unit
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
      'PRICE_TIER',
      new.id,
      'PRICE_TIER_UPDATED',
      v_actor_user_id,
      v_event_source,
      'Price tier updated',
      to_jsonb(old),
      to_jsonb(new),
      jsonb_build_object(
        'schema_name', tg_table_schema,
        'table_name', tg_table_name,
        'operation', tg_op,
        'pricing_rule_id', new.pricing_rule_id,
        'min_quantity_base_units', new.min_quantity_base_units,
        'max_quantity_base_units', new.max_quantity_base_units,
        'fixed_selling_price_per_base_unit', new.fixed_selling_price_per_base_unit,
        'markup_percent', new.markup_percent,
        'margin_percent', new.margin_percent,
        'print_cost_per_base_unit', new.print_cost_per_base_unit
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
      'PRICE_TIER',
      old.id,
      'PRICE_TIER_DELETED',
      v_actor_user_id,
      v_event_source,
      'Price tier deleted',
      to_jsonb(old),
      null,
      jsonb_build_object(
        'schema_name', tg_table_schema,
        'table_name', tg_table_name,
        'operation', tg_op,
        'pricing_rule_id', old.pricing_rule_id,
        'min_quantity_base_units', old.min_quantity_base_units,
        'max_quantity_base_units', old.max_quantity_base_units,
        'fixed_selling_price_per_base_unit', old.fixed_selling_price_per_base_unit,
        'markup_percent', old.markup_percent,
        'margin_percent', old.margin_percent,
        'print_cost_per_base_unit', old.print_cost_per_base_unit
      )
    );

    return old;
  end if;

  raise exception 'Unsupported price_tiers activity operation: %', tg_op;
end;
$$;

revoke all on function public.capture_price_tier_activity()
from public, anon, authenticated;

drop trigger if exists price_tiers_capture_activity
on public.price_tiers;

create trigger price_tiers_capture_activity
after insert or update or delete on public.price_tiers
for each row execute function public.capture_price_tier_activity();

commit;
