-- OPS-004 bounded unit: inventory-movement automatic activity capture
-- Architecture Generation 1
-- Source of Truth: SOURCE_OF_TRUTH.md
--
-- Scope is intentionally limited to automatic activity capture for the
-- append-only inventory_movements ledger. Other material modules and
-- attachment/storage access remain later bounded work within OPS-004.
--
-- Security posture:
-- - inventory movements are immutable after insertion, so only CREATE events
--   are captured;
-- - audit rows are written by a SECURITY DEFINER trigger function;
-- - actor identity is derived from auth.uid() and cannot be supplied by clients;
-- - the shared activity_logs table remains append-only and OWNER_ADMIN-readable.

begin;

create or replace function public.capture_inventory_movement_activity()
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
    raise exception 'Unsupported inventory_movements activity operation: %', tg_op;
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
    'INVENTORY_MOVEMENT',
    new.id,
    'INVENTORY_MOVEMENT_CREATED',
    v_actor_user_id,
    v_event_source,
    'Inventory movement recorded',
    null,
    to_jsonb(new),
    jsonb_build_object(
      'schema_name', tg_table_schema,
      'table_name', tg_table_name,
      'operation', tg_op,
      'movement_type', new.movement_type,
      'product_variant_id', new.product_variant_id,
      'inventory_reservation_id', new.inventory_reservation_id,
      'goods_receipt_item_id', new.goods_receipt_item_id,
      'sales_order_item_id', new.sales_order_item_id
    )
  );

  return new;
end;
$$;

revoke all on function public.capture_inventory_movement_activity()
from public, anon, authenticated;

drop trigger if exists inventory_movements_capture_activity
on public.inventory_movements;

create trigger inventory_movements_capture_activity
after insert on public.inventory_movements
for each row execute function public.capture_inventory_movement_activity();

commit;
