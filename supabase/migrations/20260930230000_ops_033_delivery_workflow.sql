-- OPS-033: delivery workflow
-- Architecture Generation 1
-- Source of Truth: SOURCE_OF_TRUTH.md
begin;

create unique index if not exists deliveries_one_active_per_sales_order
  on public.deliveries(sales_order_id)
  where status <> 'CANCELLED';

alter view public.delivery_order_status set (security_invoker = true);

create or replace function private.refresh_sales_order_delivery_status(p_sales_order_id uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  v_status text;
begin
  select d.status
  into v_status
  from public.deliveries d
  where d.sales_order_id=p_sales_order_id
    and d.status<>'CANCELLED'
  order by d.created_at desc,d.id desc
  limit 1;

  v_status:=coalesce(v_status,'NOT_READY');

  update public.sales_orders
  set delivery_status=v_status
  where id=p_sales_order_id
    and delivery_status is distinct from v_status;
end;
$$;
revoke all on function private.refresh_sales_order_delivery_status(uuid) from public,anon,authenticated;

create or replace function private.guard_delivery_workflow()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  v_order_status text;
  v_warehouse_status text;
  v_print_status text;
  v_order_line_count integer;
  v_manifest_line_count integer;
  v_manifest_invalid boolean;
begin
  if tg_op='INSERT' then
    if new.status<>'NOT_READY' then
      raise exception 'New deliveries must start in NOT_READY';
    end if;

    select so.order_status
    into v_order_status
    from public.sales_orders so
    where so.id=new.sales_order_id;

    if not found then
      raise exception 'Sales order % does not exist',new.sales_order_id;
    end if;
    if v_order_status<>'CONFIRMED' then
      raise exception 'Deliveries may be created only for CONFIRMED sales orders';
    end if;

    if (select auth.uid()) is not null then
      new.created_by_user_id:=(select auth.uid());
    end if;
    return new;
  end if;

  if new.sales_order_id is distinct from old.sales_order_id
     or new.delivery_number is distinct from old.delivery_number
     or new.created_by_user_id is distinct from old.created_by_user_id then
    raise exception 'Delivery source, number, and creator are immutable';
  end if;

  if old.status in ('DISPATCHED','COMPLETED','CANCELLED') and (
    new.consignee_name is distinct from old.consignee_name
    or new.consignee_phone is distinct from old.consignee_phone
    or new.consignee_address is distinct from old.consignee_address
    or new.parcel_info is distinct from old.parcel_info
    or new.carrier_note is distinct from old.carrier_note
    or new.delivery_reference is distinct from old.delivery_reference
    or new.notes is distinct from old.notes
  ) then
    raise exception 'Delivery operational details are locked after dispatch or cancellation';
  end if;

  if new.status is distinct from old.status then
    if not (
      (old.status='NOT_READY' and new.status in ('READY_TO_SHIP','CANCELLED'))
      or (old.status='READY_TO_SHIP' and new.status in ('DISPATCHED','CANCELLED'))
      or (old.status='DISPATCHED' and new.status='COMPLETED')
    ) then
      raise exception 'Invalid delivery status transition from % to %',old.status,new.status;
    end if;

    select so.order_status,so.warehouse_status,so.print_status
    into v_order_status,v_warehouse_status,v_print_status
    from public.sales_orders so
    where so.id=new.sales_order_id
    for update;

    if new.status='READY_TO_SHIP' then
      if v_order_status<>'CONFIRMED' then
        raise exception 'Delivery readiness requires a CONFIRMED sales order';
      end if;
      if v_warehouse_status<>'ISSUED' then
        raise exception 'Delivery readiness requires warehouse status ISSUED';
      end if;
      if v_print_status not in ('NOT_REQUIRED','COMPLETED') then
        raise exception 'Delivery readiness requires print status NOT_REQUIRED or COMPLETED';
      end if;
      if new.parcel_info is null or length(btrim(new.parcel_info))=0 then
        raise exception 'Delivery readiness requires parcel/package information';
      end if;

      select count(*)::integer
      into v_order_line_count
      from public.sales_order_items soi
      where soi.sales_order_id=new.sales_order_id;

      select count(*)::integer
      into v_manifest_line_count
      from public.delivery_items di
      where di.delivery_id=new.id;

      select exists(
        select 1
        from public.sales_order_items soi
        left join public.delivery_items di
          on di.delivery_id=new.id
         and di.sales_order_item_id=soi.id
        where soi.sales_order_id=new.sales_order_id
          and (di.id is null or di.quantity_base_units is distinct from soi.base_quantity)
      )
      into v_manifest_invalid;

      if v_order_line_count=0
         or v_manifest_line_count<>v_order_line_count
         or v_manifest_invalid then
        raise exception 'Delivery manifest must exactly cover every sales-order line before readiness';
      end if;

      new.ready_at:=coalesce(new.ready_at,timezone('utc',now()));
      new.dispatch_date:=null;
      new.completed_at:=null;
    elsif new.status='DISPATCHED' then
      if new.parcel_info is null or length(btrim(new.parcel_info))=0 then
        raise exception 'Dispatch requires parcel/package information';
      end if;
      if coalesce(length(btrim(new.carrier_note)),0)=0
         and coalesce(length(btrim(new.delivery_reference)),0)=0 then
        raise exception 'Dispatch requires a carrier/chành xe note or delivery reference';
      end if;
      new.dispatch_date:=coalesce(new.dispatch_date,current_date);
      if new.dispatch_date>current_date then
        raise exception 'Dispatch date cannot be in the future';
      end if;
      new.completed_at:=null;
    elsif new.status='COMPLETED' then
      new.completed_at:=coalesce(new.completed_at,timezone('utc',now()));
    elsif new.status='CANCELLED' then
      new.dispatch_date:=null;
      new.completed_at:=null;
    end if;
  end if;

  return new;
end;
$$;
revoke all on function private.guard_delivery_workflow() from public,anon,authenticated;

drop trigger if exists deliveries_guard_workflow on public.deliveries;
create trigger deliveries_guard_workflow
before insert or update on public.deliveries
for each row execute function private.guard_delivery_workflow();

create or replace function private.guard_delivery_item_workflow()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  v_delivery_id uuid;
  v_status text;
  v_source_quantity numeric(18,6);
begin
  v_delivery_id:=case when tg_op='DELETE' then old.delivery_id else new.delivery_id end;

  select d.status
  into v_status
  from public.deliveries d
  where d.id=v_delivery_id;

  if not found then
    raise exception 'Delivery % does not exist',v_delivery_id;
  end if;
  if v_status<>'NOT_READY' then
    raise exception 'Delivery manifest is editable only while delivery is NOT_READY';
  end if;

  if tg_op<>'DELETE' then
    select soi.base_quantity
    into v_source_quantity
    from public.sales_order_items soi
    where soi.id=new.sales_order_item_id;

    if not found then
      raise exception 'Delivery source sales-order item % does not exist',new.sales_order_item_id;
    end if;
    if new.quantity_base_units>v_source_quantity then
      raise exception 'Delivery item quantity cannot exceed its sales-order item quantity';
    end if;
  end if;

  return case when tg_op='DELETE' then old else new end;
end;
$$;
revoke all on function private.guard_delivery_item_workflow() from public,anon,authenticated;

drop trigger if exists delivery_items_guard_workflow on public.delivery_items;
create trigger delivery_items_guard_workflow
before insert or update or delete on public.delivery_items
for each row execute function private.guard_delivery_item_workflow();

create or replace function private.sync_sales_order_delivery_status()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
begin
  perform private.refresh_sales_order_delivery_status(
    case when tg_op='DELETE' then old.sales_order_id else new.sales_order_id end
  );
  return case when tg_op='DELETE' then old else new end;
end;
$$;
revoke all on function private.sync_sales_order_delivery_status() from public,anon,authenticated;

drop trigger if exists deliveries_sync_sales_order_delivery_status on public.deliveries;
create trigger deliveries_sync_sales_order_delivery_status
after insert or update or delete on public.deliveries
for each row execute function private.sync_sales_order_delivery_status();

create or replace function public.delivery_work_queue()
returns table(
  sales_order_id uuid,
  order_number text,
  customer_name text,
  requested_due_date date,
  warehouse_status text,
  print_status text,
  ready_eligible boolean,
  line_count integer
)
language plpgsql
stable
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  v_user_id uuid:=(select auth.uid());
begin
  if v_user_id is null or not (
    public.current_user_has_role('OWNER_ADMIN')
    or public.current_user_has_role('WAREHOUSE')
    or public.current_user_has_role('SALES')
  ) then
    raise exception 'Delivery work queue requires OWNER_ADMIN, WAREHOUSE, or SALES role'
      using errcode='42501';
  end if;

  return query
  select
    so.id,
    so.order_number,
    c.display_name,
    so.requested_due_date,
    so.warehouse_status,
    so.print_status,
    (so.warehouse_status='ISSUED' and so.print_status in ('NOT_REQUIRED','COMPLETED')),
    count(soi.id)::integer
  from public.sales_orders so
  join public.customers c on c.id=so.customer_id
  join public.sales_order_items soi on soi.sales_order_id=so.id
  where so.order_status='CONFIRMED'
    and not exists(
      select 1 from public.deliveries d
      where d.sales_order_id=so.id and d.status<>'CANCELLED'
    )
  group by so.id,so.order_number,c.display_name,so.requested_due_date,so.warehouse_status,so.print_status
  order by so.requested_due_date asc nulls last,so.order_number asc;
end;
$$;
revoke all on function public.delivery_work_queue() from public,anon;
grant execute on function public.delivery_work_queue() to authenticated,service_role;

create or replace function public.delivery_tracking(p_delivery_id uuid default null)
returns table(
  delivery_id uuid,
  delivery_number text,
  sales_order_id uuid,
  order_number text,
  customer_name text,
  status text,
  warehouse_status text,
  print_status text,
  order_delivery_status text,
  consignee_name text,
  consignee_phone text,
  consignee_address text,
  parcel_info text,
  carrier_note text,
  delivery_reference text,
  ready_at timestamptz,
  dispatch_date date,
  completed_at timestamptz,
  notes text
)
language plpgsql
stable
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  v_user_id uuid:=(select auth.uid());
begin
  if v_user_id is null or not (
    public.current_user_has_role('OWNER_ADMIN')
    or public.current_user_has_role('WAREHOUSE')
    or public.current_user_has_role('SALES')
  ) then
    raise exception 'Delivery tracking requires OWNER_ADMIN, WAREHOUSE, or SALES role'
      using errcode='42501';
  end if;

  return query
  select
    d.id,d.delivery_number,d.sales_order_id,so.order_number,c.display_name,d.status,
    so.warehouse_status,so.print_status,so.delivery_status,
    d.consignee_name,d.consignee_phone,d.consignee_address,d.parcel_info,
    d.carrier_note,d.delivery_reference,d.ready_at,d.dispatch_date,d.completed_at,d.notes
  from public.deliveries d
  join public.sales_orders so on so.id=d.sales_order_id
  join public.customers c on c.id=so.customer_id
  where p_delivery_id is null or d.id=p_delivery_id
  order by d.created_at desc,d.id desc;
end;
$$;
revoke all on function public.delivery_tracking(uuid) from public,anon;
grant execute on function public.delivery_tracking(uuid) to authenticated,service_role;

create or replace function public.delivery_manifest(p_delivery_id uuid)
returns table(
  delivery_item_id uuid,
  sales_order_item_id uuid,
  product_variant_id uuid,
  sku_code text,
  product_name text,
  quantity_base_units numeric,
  base_inventory_unit text
)
language plpgsql
stable
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  v_user_id uuid:=(select auth.uid());
begin
  if v_user_id is null or not (
    public.current_user_has_role('OWNER_ADMIN')
    or public.current_user_has_role('WAREHOUSE')
    or public.current_user_has_role('SALES')
  ) then
    raise exception 'Delivery manifest requires OWNER_ADMIN, WAREHOUSE, or SALES role'
      using errcode='42501';
  end if;

  return query
  select
    di.id,di.sales_order_item_id,di.product_variant_id,pv.sku_code,p.name,
    di.quantity_base_units,pv.base_inventory_unit
  from public.delivery_items di
  join public.product_variants pv on pv.id=di.product_variant_id
  join public.products p on p.id=pv.product_id
  where di.delivery_id=p_delivery_id
  order by pv.sku_code,di.id;
end;
$$;
revoke all on function public.delivery_manifest(uuid) from public,anon;
grant execute on function public.delivery_manifest(uuid) to authenticated,service_role;

create or replace function public.create_delivery(
  p_delivery_number text,
  p_sales_order_id uuid,
  p_consignee_name text,
  p_consignee_phone text default null,
  p_consignee_address text default null,
  p_parcel_info text default null,
  p_carrier_note text default null,
  p_delivery_reference text default null,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  v_user_id uuid:=(select auth.uid());
  v_order_status text;
  v_line_count integer;
  v_delivery_id uuid;
begin
  if v_user_id is null or not (
    public.current_user_has_role('OWNER_ADMIN')
    or public.current_user_has_role('WAREHOUSE')
  ) then
    raise exception 'Create delivery requires OWNER_ADMIN or WAREHOUSE role'
      using errcode='42501';
  end if;
  if p_delivery_number is null or length(btrim(p_delivery_number))=0 then
    raise exception 'Delivery number is required';
  end if;
  if p_consignee_name is null or length(btrim(p_consignee_name))=0 then
    raise exception 'Consignee name is required';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_sales_order_id::text,33));

  select so.order_status
  into v_order_status
  from public.sales_orders so
  where so.id=p_sales_order_id
  for update;

  if not found then raise exception 'Sales order % does not exist',p_sales_order_id; end if;
  if v_order_status<>'CONFIRMED' then
    raise exception 'Deliveries may be created only for CONFIRMED sales orders';
  end if;
  if exists(select 1 from public.deliveries where sales_order_id=p_sales_order_id and status<>'CANCELLED') then
    raise exception 'Sales order already has an active delivery';
  end if;

  select count(*)::integer into v_line_count
  from public.sales_order_items where sales_order_id=p_sales_order_id;
  if v_line_count=0 then raise exception 'Sales order must contain at least one item before delivery creation'; end if;

  insert into public.deliveries(
    delivery_number,sales_order_id,status,consignee_name,consignee_phone,
    consignee_address,parcel_info,carrier_note,delivery_reference,
    created_by_user_id,notes
  )
  values(
    btrim(p_delivery_number),p_sales_order_id,'NOT_READY',btrim(p_consignee_name),
    nullif(btrim(coalesce(p_consignee_phone,'')),''),
    nullif(btrim(coalesce(p_consignee_address,'')),''),
    nullif(btrim(coalesce(p_parcel_info,'')),''),
    nullif(btrim(coalesce(p_carrier_note,'')),''),
    nullif(btrim(coalesce(p_delivery_reference,'')),''),
    v_user_id,nullif(btrim(coalesce(p_notes,'')),'')
  )
  returning id into v_delivery_id;

  insert into public.delivery_items(
    delivery_id,sales_order_item_id,product_variant_id,quantity_base_units,notes
  )
  select v_delivery_id,soi.id,soi.product_variant_id,soi.base_quantity,'Full-order delivery manifest'
  from public.sales_order_items soi
  where soi.sales_order_id=p_sales_order_id
  order by soi.created_at,soi.id;

  return v_delivery_id;
end;
$$;
revoke all on function public.create_delivery(text,uuid,text,text,text,text,text,text,text) from public,anon;
grant execute on function public.create_delivery(text,uuid,text,text,text,text,text,text,text) to authenticated,service_role;

create or replace function public.update_delivery_details(
  p_delivery_id uuid,
  p_consignee_name text,
  p_consignee_phone text default null,
  p_consignee_address text default null,
  p_parcel_info text default null,
  p_carrier_note text default null,
  p_delivery_reference text default null,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  v_user_id uuid:=(select auth.uid());
begin
  if v_user_id is null or not (
    public.current_user_has_role('OWNER_ADMIN')
    or public.current_user_has_role('WAREHOUSE')
  ) then
    raise exception 'Update delivery requires OWNER_ADMIN or WAREHOUSE role'
      using errcode='42501';
  end if;
  if p_consignee_name is null or length(btrim(p_consignee_name))=0 then
    raise exception 'Consignee name is required';
  end if;

  update public.deliveries
  set consignee_name=btrim(p_consignee_name),
      consignee_phone=nullif(btrim(coalesce(p_consignee_phone,'')),''),
      consignee_address=nullif(btrim(coalesce(p_consignee_address,'')),''),
      parcel_info=nullif(btrim(coalesce(p_parcel_info,'')),''),
      carrier_note=nullif(btrim(coalesce(p_carrier_note,'')),''),
      delivery_reference=nullif(btrim(coalesce(p_delivery_reference,'')),''),
      notes=nullif(btrim(coalesce(p_notes,'')),'')
  where id=p_delivery_id
    and status in ('NOT_READY','READY_TO_SHIP');

  if not found then raise exception 'Delivery details are editable only before dispatch'; end if;
  return p_delivery_id;
end;
$$;
revoke all on function public.update_delivery_details(uuid,text,text,text,text,text,text,text) from public,anon;
grant execute on function public.update_delivery_details(uuid,text,text,text,text,text,text,text) to authenticated,service_role;

create or replace function public.set_delivery_status(
  p_delivery_id uuid,
  p_status text,
  p_dispatch_date date default null
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  v_user_id uuid:=(select auth.uid());
  v_target text:=upper(btrim(coalesce(p_status,'')));
begin
  if v_user_id is null or not (
    public.current_user_has_role('OWNER_ADMIN')
    or public.current_user_has_role('WAREHOUSE')
  ) then
    raise exception 'Delivery status change requires OWNER_ADMIN or WAREHOUSE role'
      using errcode='42501';
  end if;
  if v_target not in ('READY_TO_SHIP','DISPATCHED','COMPLETED','CANCELLED') then
    raise exception 'Unsupported delivery status action %',v_target;
  end if;

  update public.deliveries
  set status=v_target,
      dispatch_date=case when v_target='DISPATCHED' then coalesce(p_dispatch_date,current_date) else dispatch_date end
  where id=p_delivery_id;

  if not found then raise exception 'Delivery % does not exist',p_delivery_id; end if;
  return p_delivery_id;
end;
$$;
revoke all on function public.set_delivery_status(uuid,text,date) from public,anon;
grant execute on function public.set_delivery_status(uuid,text,date) to authenticated,service_role;

commit;
