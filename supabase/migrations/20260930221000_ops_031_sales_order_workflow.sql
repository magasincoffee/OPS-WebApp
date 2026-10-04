-- OPS-031: sales-order workflow
-- Architecture Generation 1
-- Source of Truth: SOURCE_OF_TRUTH.md
begin;

alter table public.sales_orders
  add column if not exists confirmed_at timestamptz,
  add column if not exists cancelled_at timestamptz,
  add column if not exists completed_at timestamptz;

alter table public.sales_order_items
  add column if not exists pricing_rule_id uuid references public.pricing_rules(id) on delete restrict,
  add column if not exists price_tier_id uuid references public.price_tiers(id) on delete restrict;

create unique index if not exists sales_orders_one_per_source_quotation
  on public.sales_orders(source_quotation_id) where source_quotation_id is not null;
create unique index if not exists sales_order_items_one_per_source_quotation_item
  on public.sales_order_items(source_quotation_item_id) where source_quotation_item_id is not null;

alter view public.sales_order_totals set (security_invoker = true);

revoke insert, update, delete on public.sales_orders from authenticated;
revoke insert, update, delete on public.sales_order_items from authenticated;
grant select on public.sales_orders, public.sales_order_items to authenticated;

create or replace function private.guard_sales_order_workflow()
returns trigger language plpgsql security definer set search_path = pg_catalog, pg_temp
as $$
declare
  v_item_count integer;
  v_has_inventory boolean;
  v_has_downstream boolean;
begin
  if tg_op='DELETE' then
    if old.order_status<>'DRAFT' then raise exception 'Only DRAFT sales orders may be deleted'; end if;
    if old.source_quotation_id is not null then raise exception 'Sales orders converted from quotations cannot be deleted'; end if;
    return old;
  end if;

  if old.order_status<>'DRAFT' and (
    new.customer_id is distinct from old.customer_id
    or new.source_quotation_id is distinct from old.source_quotation_id
    or new.order_date is distinct from old.order_date
    or new.requested_due_date is distinct from old.requested_due_date
    or new.currency_code is distinct from old.currency_code
    or new.salesperson_user_id is distinct from old.salesperson_user_id
    or new.notes is distinct from old.notes
  ) then
    raise exception 'Sales-order header is locked after confirmation';
  end if;

  if new.order_status is distinct from old.order_status then
    if not (
      (old.order_status='DRAFT' and new.order_status in ('CONFIRMED','CANCELLED'))
      or (old.order_status='CONFIRMED' and new.order_status in ('CANCELLED','COMPLETED'))
    ) then
      raise exception 'Invalid sales-order status transition from % to %',old.order_status,new.order_status;
    end if;

    if new.order_status='CONFIRMED' then
      select count(*)::integer into v_item_count from public.sales_order_items where sales_order_id=new.id;
      if v_item_count=0 then raise exception 'Sales order must contain at least one item before confirmation'; end if;
      new.confirmed_at:=coalesce(new.confirmed_at,timezone('utc',now()));
    elsif new.order_status='CANCELLED' then
      select exists(
        select 1
        from public.sales_order_items soi
        left join public.inventory_reservations ir on ir.sales_order_item_id=soi.id
        left join public.inventory_movements im on im.sales_order_item_id=soi.id
        where soi.sales_order_id=new.id and (ir.id is not null or im.id is not null)
      ) into v_has_inventory;
      select
        exists(select 1 from public.print_jobs where sales_order_id=new.id)
        or exists(select 1 from public.deliveries where sales_order_id=new.id)
        or exists(select 1 from public.customer_payments where sales_order_id=new.id)
      into v_has_downstream;
      if v_has_inventory or v_has_downstream then
        raise exception 'Cannot cancel sales order after inventory or downstream operational activity exists';
      end if;
      new.cancelled_at:=coalesce(new.cancelled_at,timezone('utc',now()));
    elsif new.order_status='COMPLETED' then
      if new.warehouse_status<>'ISSUED' then raise exception 'Completed sales order requires warehouse status ISSUED'; end if;
      if new.print_status not in ('NOT_REQUIRED','COMPLETED') then raise exception 'Completed sales order requires print status NOT_REQUIRED or COMPLETED'; end if;
      if new.delivery_status<>'COMPLETED' then raise exception 'Completed sales order requires delivery status COMPLETED'; end if;
      if new.payment_status<>'PAID' then raise exception 'Completed sales order requires payment status PAID'; end if;
      new.completed_at:=coalesce(new.completed_at,timezone('utc',now()));
    end if;
  end if;
  return new;
end;
$$;
revoke all on function private.guard_sales_order_workflow() from public,anon,authenticated;
drop trigger if exists sales_orders_guard_workflow on public.sales_orders;
create trigger sales_orders_guard_workflow before update or delete on public.sales_orders
for each row execute function private.guard_sales_order_workflow();

create or replace function private.guard_sales_order_item_editability()
returns trigger language plpgsql security definer set search_path = pg_catalog, pg_temp
as $$
declare v_order_id uuid; v_status text;
begin
  v_order_id:=case when tg_op='DELETE' then old.sales_order_id else new.sales_order_id end;
  select order_status into v_status from public.sales_orders where id=v_order_id;
  if not found then raise exception 'Sales order % does not exist',v_order_id; end if;
  if v_status<>'DRAFT' then raise exception 'Sales-order items are editable only while the order is DRAFT'; end if;
  return case when tg_op='DELETE' then old else new end;
end;
$$;
revoke all on function private.guard_sales_order_item_editability() from public,anon,authenticated;
drop trigger if exists sales_order_items_guard_editability on public.sales_order_items;
create trigger sales_order_items_guard_editability before insert or update or delete on public.sales_order_items
for each row execute function private.guard_sales_order_item_editability();

create or replace function public.create_sales_order_draft(
  p_order_number text,p_customer_id uuid,p_requested_due_date date default null,
  p_currency_code text default 'VND',p_notes text default null
) returns uuid language plpgsql security definer set search_path=pg_catalog,pg_temp
as $$
declare v_user_id uuid:=(select auth.uid()); v_id uuid;
begin
  if v_user_id is null or not (public.current_user_has_role('OWNER_ADMIN') or public.current_user_has_role('SALES')) then
    raise exception 'Create sales order requires OWNER_ADMIN or SALES role' using errcode='42501';
  end if;
  if p_order_number is null or length(btrim(p_order_number))=0 then raise exception 'Sales-order number is required'; end if;
  if not exists(select 1 from public.customers where id=p_customer_id and is_active=true) then raise exception 'Active customer % does not exist',p_customer_id; end if;
  insert into public.sales_orders(
    order_number,customer_id,order_status,print_status,warehouse_status,payment_status,delivery_status,
    order_date,requested_due_date,currency_code,created_by_user_id,salesperson_user_id,notes
  ) values(
    btrim(p_order_number),p_customer_id,'DRAFT','NOT_REQUIRED','NOT_RESERVED','UNPAID','NOT_READY',
    current_date,p_requested_due_date,upper(coalesce(nullif(btrim(p_currency_code),''),'VND')),
    v_user_id,v_user_id,nullif(btrim(coalesce(p_notes,'')),'')
  ) returning id into v_id;
  return v_id;
end;
$$;
revoke all on function public.create_sales_order_draft(text,uuid,date,text,text) from public,anon;
grant execute on function public.create_sales_order_draft(text,uuid,date,text,text) to authenticated,service_role;

create or replace function public.convert_accepted_quotation_to_sales_order(
  p_quotation_id uuid,p_order_number text,p_requested_due_date date default null,p_notes text default null
) returns uuid language plpgsql security definer set search_path=pg_catalog,pg_temp
as $$
declare v_user_id uuid:=(select auth.uid()); v_quote public.quotations%rowtype; v_count integer; v_order_id uuid;
begin
  if v_user_id is null or not (public.current_user_has_role('OWNER_ADMIN') or public.current_user_has_role('SALES')) then
    raise exception 'Convert quotation requires OWNER_ADMIN or SALES role' using errcode='42501';
  end if;
  if p_order_number is null or length(btrim(p_order_number))=0 then raise exception 'Sales-order number is required'; end if;
  select * into v_quote from public.quotations where id=p_quotation_id for update;
  if not found then raise exception 'Quotation % does not exist',p_quotation_id; end if;
  if v_quote.status<>'ACCEPTED' then raise exception 'Only ACCEPTED quotations may be converted to sales orders'; end if;
  if exists(select 1 from public.sales_orders where source_quotation_id=p_quotation_id) then raise exception 'Quotation has already been converted to a sales order'; end if;
  select count(*)::integer into v_count from public.quotation_items where quotation_id=p_quotation_id;
  if v_count=0 then raise exception 'Accepted quotation must contain at least one item before conversion'; end if;

  insert into public.sales_orders(
    order_number,customer_id,source_quotation_id,order_status,print_status,warehouse_status,payment_status,
    delivery_status,order_date,requested_due_date,currency_code,created_by_user_id,salesperson_user_id,notes
  ) values(
    btrim(p_order_number),v_quote.customer_id,v_quote.id,'DRAFT','NOT_REQUIRED','NOT_RESERVED','UNPAID',
    'NOT_READY',current_date,p_requested_due_date,v_quote.currency_code,v_user_id,v_user_id,
    coalesce(nullif(btrim(coalesce(p_notes,'')),''),v_quote.notes)
  ) returning id into v_order_id;

  insert into public.sales_order_items(
    sales_order_id,source_quotation_item_id,product_variant_id,packaging_id,sale_unit,sale_quantity,
    units_per_sale_unit,unit_price_per_sale_unit,discount_amount,print_mode,print_color_count,
    print_specification,artwork_reference,requested_due_date,notes,pricing_rule_id,price_tier_id
  )
  select v_order_id,id,product_variant_id,packaging_id,sale_unit,sale_quantity,units_per_sale_unit,
    unit_price_per_sale_unit,discount_amount,print_mode,print_color_count,print_specification,
    artwork_reference,requested_due_date,notes,pricing_rule_id,price_tier_id
  from public.quotation_items where quotation_id=p_quotation_id order by created_at,id;

  update public.quotations set status='CONVERTED' where id=p_quotation_id;
  return v_order_id;
end;
$$;
revoke all on function public.convert_accepted_quotation_to_sales_order(uuid,text,date,text) from public,anon;
grant execute on function public.convert_accepted_quotation_to_sales_order(uuid,text,date,text) to authenticated,service_role;

create or replace function public.add_sales_order_item_priced(
  p_sales_order_id uuid,p_product_variant_id uuid,p_packaging_id uuid,p_sale_quantity numeric,
  p_discount_amount numeric default 0,p_print_mode text default 'PLAIN',p_print_color_count integer default null,
  p_print_specification text default null,p_artwork_reference text default null,p_requested_due_date date default null,p_notes text default null
) returns uuid language plpgsql security definer set search_path=pg_catalog,pg_temp
as $$
declare
  v_user_id uuid:=(select auth.uid()); v_status text; v_currency text; v_order_date date;
  v_sale_unit text; v_units numeric(18,6); v_base numeric(18,6); v_price_base numeric(18,6);
  v_rule uuid; v_tier uuid; v_unit_price numeric(18,6); v_subtotal numeric(18,6); v_id uuid;
begin
  if v_user_id is null or not (public.current_user_has_role('OWNER_ADMIN') or public.current_user_has_role('SALES')) then
    raise exception 'Add sales-order item requires OWNER_ADMIN or SALES role' using errcode='42501';
  end if;
  if p_sale_quantity is null or p_sale_quantity<=0 then raise exception 'Sale quantity must be positive'; end if;
  if coalesce(p_discount_amount,0)<0 then raise exception 'Discount amount cannot be negative'; end if;
  select order_status,currency_code,order_date into v_status,v_currency,v_order_date from public.sales_orders where id=p_sales_order_id for update;
  if not found then raise exception 'Sales order % does not exist',p_sales_order_id; end if;
  if v_status<>'DRAFT' then raise exception 'Sales-order items are editable only while the order is DRAFT'; end if;

  if p_packaging_id is null then
    select base_inventory_unit,1::numeric into v_sale_unit,v_units from public.product_variants where id=p_product_variant_id and is_active=true;
  else
    select pp.package_code,pp.units_per_package into v_sale_unit,v_units
    from public.product_packaging pp join public.product_variants pv on pv.id=pp.product_variant_id
    where pp.id=p_packaging_id and pp.product_variant_id=p_product_variant_id and pp.is_active=true and pv.is_active=true
      and pp.effective_from<=v_order_date and (pp.effective_to is null or pp.effective_to>=v_order_date);
  end if;
  if v_sale_unit is null or v_units is null then raise exception 'Active sale unit/package is not valid for this SKU'; end if;

  v_base:=p_sale_quantity*v_units;
  select pricing_rule_id,price_tier_id,selling_price_per_base_unit into v_rule,v_tier,v_price_base
  from private.resolve_quotation_price(p_product_variant_id,v_base,upper(p_print_mode),p_print_color_count,v_currency,v_order_date);
  v_unit_price:=round(v_price_base*v_units,6);
  v_subtotal:=p_sale_quantity*v_unit_price;
  if coalesce(p_discount_amount,0)>v_subtotal then raise exception 'Discount amount cannot exceed line subtotal'; end if;

  insert into public.sales_order_items(
    sales_order_id,product_variant_id,packaging_id,sale_unit,sale_quantity,units_per_sale_unit,
    unit_price_per_sale_unit,discount_amount,print_mode,print_color_count,print_specification,
    artwork_reference,requested_due_date,notes,pricing_rule_id,price_tier_id
  ) values(
    p_sales_order_id,p_product_variant_id,p_packaging_id,v_sale_unit,p_sale_quantity,v_units,
    v_unit_price,coalesce(p_discount_amount,0),upper(p_print_mode),p_print_color_count,
    nullif(btrim(coalesce(p_print_specification,'')),''),nullif(btrim(coalesce(p_artwork_reference,'')),''),
    p_requested_due_date,nullif(btrim(coalesce(p_notes,'')),''),v_rule,v_tier
  ) returning id into v_id;
  return v_id;
end;
$$;
revoke all on function public.add_sales_order_item_priced(uuid,uuid,uuid,numeric,numeric,text,integer,text,text,date,text) from public,anon;
grant execute on function public.add_sales_order_item_priced(uuid,uuid,uuid,numeric,numeric,text,integer,text,text,date,text) to authenticated,service_role;

create or replace function public.remove_sales_order_item(p_sales_order_item_id uuid)
returns uuid language plpgsql security definer set search_path=pg_catalog,pg_temp
as $$
declare v_user_id uuid:=(select auth.uid()); v_order_id uuid; v_status text;
begin
  if v_user_id is null or not (public.current_user_has_role('OWNER_ADMIN') or public.current_user_has_role('SALES')) then
    raise exception 'Remove sales-order item requires OWNER_ADMIN or SALES role' using errcode='42501';
  end if;
  select soi.sales_order_id,so.order_status into v_order_id,v_status
  from public.sales_order_items soi join public.sales_orders so on so.id=soi.sales_order_id
  where soi.id=p_sales_order_item_id for update of soi,so;
  if not found then raise exception 'Sales-order item % does not exist',p_sales_order_item_id; end if;
  if v_status<>'DRAFT' then raise exception 'Sales-order items are editable only while the order is DRAFT'; end if;
  delete from public.sales_order_items where id=p_sales_order_item_id;
  return v_order_id;
end;
$$;
revoke all on function public.remove_sales_order_item(uuid) from public,anon;
grant execute on function public.remove_sales_order_item(uuid) to authenticated,service_role;

create or replace function public.set_sales_order_status(p_sales_order_id uuid,p_status text)
returns uuid language plpgsql security definer set search_path=pg_catalog,pg_temp
as $$
declare v_user_id uuid:=(select auth.uid()); v_target text:=upper(btrim(coalesce(p_status,'')));
begin
  if v_user_id is null or not (public.current_user_has_role('OWNER_ADMIN') or public.current_user_has_role('SALES')) then
    raise exception 'Sales-order status change requires OWNER_ADMIN or SALES role' using errcode='42501';
  end if;
  if v_target not in ('CONFIRMED','CANCELLED','COMPLETED') then raise exception 'Unsupported sales-order status action %',v_target; end if;
  update public.sales_orders set order_status=v_target where id=p_sales_order_id;
  if not found then raise exception 'Sales order % does not exist',p_sales_order_id; end if;
  return p_sales_order_id;
end;
$$;
revoke all on function public.set_sales_order_status(uuid,text) from public,anon;
grant execute on function public.set_sales_order_status(uuid,text) to authenticated,service_role;

commit;
