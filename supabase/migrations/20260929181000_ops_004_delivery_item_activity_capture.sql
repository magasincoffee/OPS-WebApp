-- OPS-004 bounded unit: delivery-item automatic activity capture
-- Architecture Generation 1
-- Source of Truth: SOURCE_OF_TRUTH.md
--
-- Scope is intentionally limited to automatic activity capture for the
-- delivery_items entity. Other material modules and attachment/storage access
-- remain later bounded work within OPS-004.
--
-- Security posture:
-- - audit rows are written by a SECURITY DEFINER trigger function;
-- - actor identity is derived from auth.uid() and cannot be supplied by clients;
-- - the trigger function has a pinned search_path and no direct authenticated
--   EXECUTE privilege;
-- - authenticated roles still have no DELETE grant on delivery_items; delete
--   capture exists to preserve traceability for trusted/internal mutations;
-- - the shared activity_logs table remains append-only and OWNER_ADMIN-readable.

begin;

create or replace function public.capture_delivery_item_activity()
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
      'DELIVERY_ITEM',
      new.id,
      'DELIVERY_ITEM_CREATED',
      v_actor_user_id,
      v_event_source,
      'Delivery item created',
      null,
      to_jsonb(new),
      jsonb_build_object(
        'schema_name', tg_table_schema,
        'table_name', tg_table_name,
        'operation', tg_op,
        'delivery_id', new.delivery_id,
        'sales_order_item_id', new.sales_order_item_id,
        'product_variant_id', new.product_variant_id
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
      'DELIVERY_ITEM',
      new.id,
      'DELIVERY_ITEM_UPDATED',
      v_actor_user_id,
      v_event_source,
      'Delivery item updated',
      to_jsonb(old),
      to_jsonb(new),
      jsonb_build_object(
        'schema_name', tg_table_schema,
        'table_name', tg_table_name,
        'operation', tg_op,
        'delivery_id', new.delivery_id,
        'sales_order_item_id', new.sales_order_item_id,
        'product_variant_id', new.product_variant_id
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
      'DELIVERY_ITEM',
      old.id,
      'DELIVERY_ITEM_DELETED',
      v_actor_user_id,
      v_event_source,
      'Delivery item deleted',
      to_jsonb(old),
      null,
      jsonb_build_object(
        'schema_name', tg_table_schema,
        'table_name', tg_table_name,
        'operation', tg_op,
        'delivery_id', old.delivery_id,
        'sales_order_item_id', old.sales_order_item_id,
        'product_variant_id', old.product_variant_id
      )
    );

    return old;
  end if;

  raise exception 'Unsupported delivery_items activity operation: %', tg_op;
end;
$$;

revoke all on function public.capture_delivery_item_activity()
from public, anon, authenticated;

drop trigger if exists delivery_items_capture_activity on public.delivery_items;

create trigger delivery_items_capture_activity
after insert or update or delete on public.delivery_items
for each row execute function public.capture_delivery_item_activity();

commit;
