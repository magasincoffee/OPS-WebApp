-- OPS-024: stocktake / adjustments / low-stock
-- Architecture Generation 1
-- Source of Truth: SOURCE_OF_TRUTH.md

begin;

alter table public.stocktakes
  drop constraint if exists stocktakes_status_not_blank;

alter table public.stocktakes
  add constraint stocktakes_status_valid
  check (status in ('DRAFT', 'COUNTED', 'POSTED'));

revoke insert, update, delete on public.stocktakes from authenticated;
revoke insert, update, delete on public.stocktake_items from authenticated;
grant select on public.stocktakes, public.stocktake_items to authenticated;

create or replace function private.guard_stocktake_adjustment_source()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  v_stocktake_number text;
  v_stocktake_status text;
  v_product_variant_id uuid;
  v_variance numeric(18,6);
begin
  if new.movement_type <> 'STOCKTAKE_ADJUSTMENT' then
    return new;
  end if;

  select st.stocktake_number, st.status, sti.product_variant_id, sti.variance_quantity
  into v_stocktake_number, v_stocktake_status, v_product_variant_id, v_variance
  from public.stocktake_items sti
  join public.stocktakes st on st.id = sti.stocktake_id
  where sti.id = new.stocktake_item_id;

  if not found then
    raise exception 'Stocktake item % does not exist', new.stocktake_item_id;
  end if;
  if v_stocktake_status <> 'COUNTED' then
    raise exception 'Stocktake adjustments may only post from COUNTED stocktakes';
  end if;
  if v_variance is null or v_variance = 0 then
    raise exception 'Stocktake adjustment requires a non-zero counted variance';
  end if;
  if new.product_variant_id is distinct from v_product_variant_id then
    raise exception 'Stocktake adjustment SKU must match its stocktake item';
  end if;
  if new.quantity_delta_base_units is distinct from v_variance then
    raise exception 'Stocktake adjustment quantity must equal the counted variance';
  end if;

  if (select auth.uid()) is not null then
    new.created_by_user_id := (select auth.uid());
  end if;
  new.reason := coalesce(nullif(btrim(new.reason), ''), 'Stocktake variance ' || v_stocktake_number);
  new.reference := coalesce(nullif(btrim(new.reference), ''), 'STOCKTAKE:' || v_stocktake_number);
  return new;
end;
$$;

revoke all on function private.guard_stocktake_adjustment_source()
from public, anon, authenticated;

drop trigger if exists inventory_movements_guard_stocktake_source
on public.inventory_movements;
create trigger inventory_movements_guard_stocktake_source
before insert on public.inventory_movements
for each row execute function private.guard_stocktake_adjustment_source();

create or replace function private.guard_manual_adjustment_actor()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
begin
  if new.movement_type not in ('ADJUSTMENT_IN', 'ADJUSTMENT_OUT') then
    return new;
  end if;

  if not (
    public.current_user_has_role('OWNER_ADMIN')
    or public.current_user_has_role('WAREHOUSE')
    or (select auth.uid()) is null
  ) then
    raise exception 'Inventory adjustment requires OWNER_ADMIN or WAREHOUSE role'
      using errcode = '42501';
  end if;

  if (select auth.uid()) is not null then
    new.created_by_user_id := (select auth.uid());
  end if;
  new.reference := coalesce(nullif(btrim(new.reference), ''), 'MANUAL_ADJUSTMENT');
  return new;
end;
$$;

revoke all on function private.guard_manual_adjustment_actor()
from public, anon, authenticated;

drop trigger if exists inventory_movements_guard_manual_adjustment_actor
on public.inventory_movements;
create trigger inventory_movements_guard_manual_adjustment_actor
before insert on public.inventory_movements
for each row execute function private.guard_manual_adjustment_actor();

create or replace view public.inventory_low_stock
with (security_invoker = true)
as
select
  pv.id as product_variant_id,
  pv.sku_code,
  pv.variant_name,
  pv.base_inventory_unit,
  pv.minimum_stock_quantity,
  p.name as product_name,
  stock.on_hand_quantity,
  stock.reserved_quantity,
  stock.available_quantity,
  greatest(pv.minimum_stock_quantity - stock.available_quantity, 0::numeric) as shortage_quantity
from public.product_variants pv
join public.products p on p.id = pv.product_id
join public.inventory_stock_snapshot stock on stock.product_variant_id = pv.id
where pv.is_active = true
  and stock.available_quantity <= pv.minimum_stock_quantity;

revoke all on public.inventory_low_stock from public, anon;
grant select on public.inventory_low_stock to authenticated, service_role;

create or replace function public.create_stocktake(
  p_stocktake_number text,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_stocktake_id uuid;
begin
  if not (
    public.current_user_has_role('OWNER_ADMIN')
    or public.current_user_has_role('WAREHOUSE')
  ) then
    raise exception 'Create stocktake requires OWNER_ADMIN or WAREHOUSE role'
      using errcode = '42501';
  end if;
  if p_stocktake_number is null or length(btrim(p_stocktake_number)) = 0 then
    raise exception 'Stocktake number is required';
  end if;

  insert into public.stocktakes (
    stocktake_number, stocktake_date, status, created_by_user_id, notes
  )
  values (
    btrim(p_stocktake_number), current_date, 'DRAFT', v_user_id,
    nullif(btrim(coalesce(p_notes, '')), '')
  )
  returning id into v_stocktake_id;

  insert into public.stocktake_items (
    stocktake_id, product_variant_id, system_on_hand_quantity
  )
  select
    v_stocktake_id,
    pv.id,
    coalesce(stock.on_hand_quantity, 0::numeric)
  from public.product_variants pv
  left join public.inventory_stock_snapshot stock
    on stock.product_variant_id = pv.id
  where pv.is_active = true
  order by pv.sku_code;

  return v_stocktake_id;
end;
$$;

revoke all on function public.create_stocktake(text, text) from public, anon;
grant execute on function public.create_stocktake(text, text) to authenticated, service_role;

create or replace function public.set_stocktake_count(
  p_stocktake_item_id uuid,
  p_counted_on_hand_quantity numeric,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  v_stocktake_id uuid;
  v_status text;
begin
  if not (
    public.current_user_has_role('OWNER_ADMIN')
    or public.current_user_has_role('WAREHOUSE')
  ) then
    raise exception 'Count stocktake requires OWNER_ADMIN or WAREHOUSE role'
      using errcode = '42501';
  end if;
  if p_counted_on_hand_quantity is null or p_counted_on_hand_quantity < 0 then
    raise exception 'Counted quantity must be zero or greater';
  end if;

  select sti.stocktake_id, st.status
  into v_stocktake_id, v_status
  from public.stocktake_items sti
  join public.stocktakes st on st.id = sti.stocktake_id
  where sti.id = p_stocktake_item_id
  for update of sti, st;

  if not found then
    raise exception 'Stocktake item % does not exist', p_stocktake_item_id;
  end if;
  if v_status <> 'DRAFT' then
    raise exception 'Only DRAFT stocktakes may be counted';
  end if;

  update public.stocktake_items
  set counted_on_hand_quantity = p_counted_on_hand_quantity,
      notes = case when p_notes is null then notes else nullif(btrim(p_notes), '') end
  where id = p_stocktake_item_id;

  return v_stocktake_id;
end;
$$;

revoke all on function public.set_stocktake_count(uuid, numeric, text) from public, anon;
grant execute on function public.set_stocktake_count(uuid, numeric, text) to authenticated, service_role;

create or replace function public.finalize_stocktake(p_stocktake_id uuid)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  v_status text;
  v_total integer;
  v_uncounted integer;
begin
  if not (
    public.current_user_has_role('OWNER_ADMIN')
    or public.current_user_has_role('WAREHOUSE')
  ) then
    raise exception 'Finalize stocktake requires OWNER_ADMIN or WAREHOUSE role'
      using errcode = '42501';
  end if;

  select status into v_status
  from public.stocktakes
  where id = p_stocktake_id
  for update;

  if not found then
    raise exception 'Stocktake % does not exist', p_stocktake_id;
  end if;
  if v_status <> 'DRAFT' then
    raise exception 'Only DRAFT stocktakes may be finalized';
  end if;

  select count(*)::integer,
         count(*) filter (where counted_on_hand_quantity is null)::integer
  into v_total, v_uncounted
  from public.stocktake_items
  where stocktake_id = p_stocktake_id;

  if v_total = 0 then
    raise exception 'Stocktake must contain at least one SKU';
  end if;
  if v_uncounted > 0 then
    raise exception 'All stocktake items must be counted before finalizing';
  end if;

  update public.stocktakes
  set status='COUNTED', counted_at=timezone('utc', now())
  where id=p_stocktake_id;

  return p_stocktake_id;
end;
$$;

revoke all on function public.finalize_stocktake(uuid) from public, anon;
grant execute on function public.finalize_stocktake(uuid) to authenticated, service_role;

create or replace function public.post_stocktake(p_stocktake_id uuid)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_status text;
  v_stocktake_number text;
  v_current_on_hand numeric(18,6);
  v_item record;
begin
  if not (
    public.current_user_has_role('OWNER_ADMIN')
    or public.current_user_has_role('WAREHOUSE')
  ) then
    raise exception 'Post stocktake requires OWNER_ADMIN or WAREHOUSE role'
      using errcode = '42501';
  end if;

  select status, stocktake_number
  into v_status, v_stocktake_number
  from public.stocktakes
  where id=p_stocktake_id
  for update;

  if not found then
    raise exception 'Stocktake % does not exist', p_stocktake_id;
  end if;
  if v_status <> 'COUNTED' then
    raise exception 'Only COUNTED stocktakes may be posted';
  end if;

  for v_item in
    select id, product_variant_id, system_on_hand_quantity,
           counted_on_hand_quantity, variance_quantity
    from public.stocktake_items
    where stocktake_id=p_stocktake_id
    order by product_variant_id
  loop
    if v_item.counted_on_hand_quantity is null then
      raise exception 'Stocktake item % has not been counted', v_item.id;
    end if;

    perform pg_advisory_xact_lock(hashtextextended(v_item.product_variant_id::text, 24));

    select coalesce(stock.on_hand_quantity, 0::numeric)
    into v_current_on_hand
    from public.inventory_stock_snapshot stock
    where stock.product_variant_id=v_item.product_variant_id;

    if v_current_on_hand is distinct from v_item.system_on_hand_quantity then
      raise exception
        'Inventory changed after stocktake snapshot for product variant %; recreate the stocktake before posting',
        v_item.product_variant_id;
    end if;

    if v_item.variance_quantity <> 0 then
      insert into public.inventory_movements (
        product_variant_id, movement_type, quantity_delta_base_units,
        stocktake_item_id, reason, reference, created_by_user_id
      )
      values (
        v_item.product_variant_id, 'STOCKTAKE_ADJUSTMENT', v_item.variance_quantity,
        v_item.id, 'Stocktake variance ' || v_stocktake_number,
        'STOCKTAKE:' || v_stocktake_number, v_user_id
      );
    end if;
  end loop;

  update public.stocktakes
  set status='POSTED',
      posted_at=timezone('utc', now()),
      posted_by_user_id=v_user_id
  where id=p_stocktake_id;

  return p_stocktake_id;
end;
$$;

revoke all on function public.post_stocktake(uuid) from public, anon;
grant execute on function public.post_stocktake(uuid) to authenticated, service_role;

create or replace function public.adjust_inventory(
  p_product_variant_id uuid,
  p_quantity_delta numeric,
  p_reason text
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_movement_id uuid;
  v_movement_type text;
begin
  if not (
    public.current_user_has_role('OWNER_ADMIN')
    or public.current_user_has_role('WAREHOUSE')
  ) then
    raise exception 'Adjust inventory requires OWNER_ADMIN or WAREHOUSE role'
      using errcode = '42501';
  end if;
  if p_quantity_delta is null or p_quantity_delta = 0 then
    raise exception 'Adjustment quantity must be non-zero';
  end if;
  if p_reason is null or length(btrim(p_reason)) = 0 then
    raise exception 'Adjustment reason is required';
  end if;
  if not exists (
    select 1 from public.product_variants pv
    where pv.id=p_product_variant_id and pv.is_active=true
  ) then
    raise exception 'Active product variant % does not exist', p_product_variant_id;
  end if;

  v_movement_type := case when p_quantity_delta > 0 then 'ADJUSTMENT_IN' else 'ADJUSTMENT_OUT' end;

  insert into public.inventory_movements (
    product_variant_id, movement_type, quantity_delta_base_units,
    reason, reference, created_by_user_id
  )
  values (
    p_product_variant_id, v_movement_type, p_quantity_delta,
    btrim(p_reason), 'MANUAL_ADJUSTMENT', v_user_id
  )
  returning id into v_movement_id;

  return v_movement_id;
end;
$$;

revoke all on function public.adjust_inventory(uuid, numeric, text) from public, anon;
grant execute on function public.adjust_inventory(uuid, numeric, text) to authenticated, service_role;

commit;
