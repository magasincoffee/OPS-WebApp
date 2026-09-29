-- OPS-004 bounded unit: product-packaging automatic activity capture
-- Architecture Generation 1
-- Source of Truth: SOURCE_OF_TRUTH.md
--
-- Scope is intentionally limited to automatic activity capture for the
-- product_packaging entity. Other material modules and attachment/storage
-- access remain later bounded work within OPS-004.
--
-- Security posture:
-- - audit rows are written by a SECURITY DEFINER trigger function;
-- - actor identity is derived from auth.uid() and cannot be supplied by clients;
-- - the shared activity_logs table remains append-only and OWNER_ADMIN-readable.

begin;

create or replace function public.capture_product_packaging_activity()
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
      'PRODUCT_PACKAGING',
      new.id,
      'PRODUCT_PACKAGING_CREATED',
      v_actor_user_id,
      v_event_source,
      'Product packaging created',
      null,
      to_jsonb(new),
      jsonb_build_object(
        'schema_name', tg_table_schema,
        'table_name', tg_table_name,
        'operation', tg_op,
        'product_variant_id', new.product_variant_id,
        'package_code', new.package_code
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
      'PRODUCT_PACKAGING',
      new.id,
      'PRODUCT_PACKAGING_UPDATED',
      v_actor_user_id,
      v_event_source,
      'Product packaging updated',
      to_jsonb(old),
      to_jsonb(new),
      jsonb_build_object(
        'schema_name', tg_table_schema,
        'table_name', tg_table_name,
        'operation', tg_op,
        'product_variant_id', new.product_variant_id,
        'package_code', new.package_code
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
      'PRODUCT_PACKAGING',
      old.id,
      'PRODUCT_PACKAGING_DELETED',
      v_actor_user_id,
      v_event_source,
      'Product packaging deleted',
      to_jsonb(old),
      null,
      jsonb_build_object(
        'schema_name', tg_table_schema,
        'table_name', tg_table_name,
        'operation', tg_op,
        'product_variant_id', old.product_variant_id,
        'package_code', old.package_code
      )
    );

    return old;
  end if;

  raise exception 'Unsupported product_packaging activity operation: %', tg_op;
end;
$$;

revoke all on function public.capture_product_packaging_activity()
from public, anon, authenticated;

drop trigger if exists product_packaging_capture_activity on public.product_packaging;

create trigger product_packaging_capture_activity
after insert or update or delete on public.product_packaging
for each row execute function public.capture_product_packaging_activity();

commit;
