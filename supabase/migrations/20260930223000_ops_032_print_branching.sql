-- OPS-032: canonical printed vs no-print branching
-- Architecture Generation 1
-- Source of Truth: SOURCE_OF_TRUTH.md
begin;

create or replace function private.guard_sales_order_workflow()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  v_item_count integer;
  v_printed_count integer;
  v_missing_print_due_count integer;
  v_has_inventory boolean;
  v_has_downstream boolean;
begin
  if tg_op = 'DELETE' then
    if old.order_status <> 'DRAFT' then
      raise exception 'Only DRAFT sales orders may be deleted';
    end if;
    if old.source_quotation_id is not null then
      raise exception 'Sales orders converted from quotations cannot be deleted';
    end if;
    return old;
  end if;

  if old.order_status <> 'DRAFT' and (
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
      (old.order_status = 'DRAFT' and new.order_status in ('CONFIRMED','CANCELLED'))
      or (old.order_status = 'CONFIRMED' and new.order_status in ('CANCELLED','COMPLETED'))
    ) then
      raise exception 'Invalid sales-order status transition from % to %', old.order_status, new.order_status;
    end if;

    if new.order_status = 'CONFIRMED' then
      select
        count(*)::integer,
        count(*) filter (where soi.print_mode = 'PRINTED')::integer,
        count(*) filter (
          where soi.print_mode = 'PRINTED'
            and coalesce(soi.requested_due_date, new.requested_due_date) is null
        )::integer
      into v_item_count, v_printed_count, v_missing_print_due_count
      from public.sales_order_items soi
      where soi.sales_order_id = new.id;

      if v_item_count = 0 then
        raise exception 'Sales order must contain at least one item before confirmation';
      end if;

      if v_printed_count > 0 then
        if v_missing_print_due_count > 0 then
          raise exception 'Printed sales-order items require a requested due date on the line or sales order';
        end if;
        new.print_status := 'WAITING';
      else
        new.print_status := 'NOT_REQUIRED';
      end if;

      new.confirmed_at := coalesce(new.confirmed_at, timezone('utc', now()));
    elsif new.order_status = 'CANCELLED' then
      select exists(
        select 1
        from public.sales_order_items soi
        left join public.inventory_reservations ir on ir.sales_order_item_id = soi.id
        left join public.inventory_movements im on im.sales_order_item_id = soi.id
        where soi.sales_order_id = new.id
          and (ir.id is not null or im.id is not null)
      ) into v_has_inventory;

      select
        exists(select 1 from public.print_jobs pj where pj.sales_order_id = new.id)
        or exists(select 1 from public.deliveries d where d.sales_order_id = new.id)
        or exists(select 1 from public.customer_payments cp where cp.sales_order_id = new.id)
      into v_has_downstream;

      if v_has_inventory or v_has_downstream then
        raise exception 'Cannot cancel sales order after inventory or downstream operational activity exists';
      end if;

      new.cancelled_at := coalesce(new.cancelled_at, timezone('utc', now()));
    elsif new.order_status = 'COMPLETED' then
      if new.warehouse_status <> 'ISSUED' then
        raise exception 'Completed sales order requires warehouse status ISSUED';
      end if;
      if new.print_status not in ('NOT_REQUIRED','COMPLETED') then
        raise exception 'Completed sales order requires print status NOT_REQUIRED or COMPLETED';
      end if;
      if new.delivery_status <> 'COMPLETED' then
        raise exception 'Completed sales order requires delivery status COMPLETED';
      end if;
      if new.payment_status <> 'PAID' then
        raise exception 'Completed sales order requires payment status PAID';
      end if;
      new.completed_at := coalesce(new.completed_at, timezone('utc', now()));
    end if;
  end if;

  return new;
end;
$$;

revoke all on function private.guard_sales_order_workflow()
from public, anon, authenticated;

create or replace function public.validate_print_job_source()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  source_order_id uuid;
  source_order_status text;
  source_print_status text;
  source_customer_id uuid;
  source_variant_id uuid;
  source_print_mode text;
begin
  select
    soi.sales_order_id,
    so.order_status,
    so.print_status,
    so.customer_id,
    soi.product_variant_id,
    soi.print_mode
  into
    source_order_id,
    source_order_status,
    source_print_status,
    source_customer_id,
    source_variant_id,
    source_print_mode
  from public.sales_order_items soi
  join public.sales_orders so on so.id = soi.sales_order_id
  where soi.id = new.sales_order_item_id;

  if source_order_id is null then
    raise exception 'Print job source sales-order item % does not exist', new.sales_order_item_id;
  end if;

  if source_order_status <> 'CONFIRMED' then
    raise exception 'Print job source sales order must be CONFIRMED';
  end if;

  if source_print_mode <> 'PRINTED' then
    raise exception 'Plain/no-print sales-order item cannot generate a print job';
  end if;

  if source_print_status not in ('WAITING','IN_PROGRESS','WAITING_QC') then
    raise exception 'Print job source sales order is not in an active print branch';
  end if;

  if new.sales_order_id <> source_order_id then
    raise exception 'Print job sales_order_id must match its source sales-order item';
  end if;

  if new.customer_id <> source_customer_id then
    raise exception 'Print job customer_id must match its source sales order';
  end if;

  if new.product_variant_id <> source_variant_id then
    raise exception 'Print job product_variant_id must match its source sales-order item';
  end if;

  return new;
end;
$$;

create or replace view public.sales_order_print_requirements
with (security_invoker = true)
as
select
  so.id as sales_order_id,
  so.order_number,
  soi.id as sales_order_item_id,
  so.customer_id,
  c.display_name as customer_name,
  soi.product_variant_id,
  pv.sku_code,
  p.name as product_name,
  p.product_type as product_type_snapshot,
  soi.base_quantity as quantity_base_units,
  soi.print_color_count,
  soi.print_specification,
  soi.artwork_reference,
  coalesce(soi.requested_due_date, so.requested_due_date) as due_date,
  so.print_status
from public.sales_orders so
join public.sales_order_items soi on soi.sales_order_id = so.id
join public.customers c on c.id = so.customer_id
join public.product_variants pv on pv.id = soi.product_variant_id
join public.products p on p.id = pv.product_id
where so.order_status = 'CONFIRMED'
  and soi.print_mode = 'PRINTED';

revoke all on public.sales_order_print_requirements from public, anon;
grant select on public.sales_order_print_requirements to authenticated, service_role;

commit;
