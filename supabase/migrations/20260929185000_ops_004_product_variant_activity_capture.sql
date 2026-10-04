-- OPS-004 bounded unit: product-variant automatic activity capture
-- Architecture Generation 1
-- Source of Truth: SOURCE_OF_TRUTH.md
--
-- Scope is intentionally limited to automatic activity capture for the
-- product_variants entity. Product packaging, other material modules, and
-- attachment/storage access remain later bounded work within OPS-004.
--
-- Security posture:
-- - audit rows are written by a SECURITY DEFINER trigger function;
-- - actor identity is derived from auth.uid() and cannot be supplied by clients;
-- - the shared activity_logs table remains append-only and OWNER_ADMIN-readable.

begin;

create or replace function public.capture_product_variant_activity()
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
      'PRODUCT_VARIANT',
      new.id,
      'PRODUCT_VARIANT_CREATED',
      v_actor_user_id,
      v_event_source,
      'Product variant created',
      null,
      to_jsonb(new),
      jsonb_build_object(
        'schema_name', tg_table_schema,
        'table_name', tg_table_name,
        'operation', tg_op,
        'product_id', new.product_id,
        'sku_code', new.sku_code
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
      'PRODUCT_VARIANT',
      new.id,
      'PRODUCT_VARIANT_UPDATED',
      v_actor_user_id,
      v_event_source,
      'Product variant updated',
      to_jsonb(old),
      to_jsonb(new),
      jsonb_build_object(
        'schema_name', tg_table_schema,
        'table_name', tg_table_name,
        'operation', tg_op,
        'product_id', new.product_id,
        'sku_code', new.sku_code
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
      'PRODUCT_VARIANT',
      old.id,
      'PRODUCT_VARIANT_DELETED',
      v_actor_user_id,
      v_event_source,
      'Product variant deleted',
      to_jsonb(old),
      null,
      jsonb_build_object(
        'schema_name', tg_table_schema,
        'table_name', tg_table_name,
        'operation', tg_op,
        'product_id', old.product_id,
        'sku_code', old.sku_code
      )
    );

    return old;
  end if;

  raise exception 'Unsupported product_variants activity operation: %', tg_op;
end;
$$;

revoke all on function public.capture_product_variant_activity()
from public, anon, authenticated;

drop trigger if exists product_variants_capture_activity on public.product_variants;

create trigger product_variants_capture_activity
after insert or update or delete on public.product_variants
for each row execute function public.capture_product_variant_activity();

commit;
