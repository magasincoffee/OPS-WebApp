-- OPS-074: replace direct production queue view access with a bounded RPC boundary
-- Architecture Generation 4
-- Source of Truth: SOURCE_OF_TRUTH.md
begin;

-- Keep the public view security-invoker for advisor compliance, but do not expose
-- the multi-table projection directly to normal authenticated users. The
-- PRINTER_PRODUCTION mobile surface is exposed only through the RPC below.
alter view public.production_print_job_queue
set (security_invoker = true);

revoke all on public.production_print_job_queue from public, anon, authenticated;
grant select on public.production_print_job_queue to service_role;

create or replace function public.production_mobile_work_queue()
returns table(
  print_job_id uuid,
  job_number text,
  order_number text,
  customer_name text,
  sku_code text,
  product_name text,
  product_type_snapshot text,
  quantity_base_units numeric,
  print_color_count integer,
  print_specification text,
  artwork_reference text,
  due_date date,
  status text,
  qc_state text,
  accepted_at timestamptz,
  started_at timestamptz,
  notes text
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_user_id uuid := (select auth.uid());
begin
  if v_user_id is null
     or not public.current_user_has_role('PRINTER_PRODUCTION') then
    raise exception 'Production mobile queue requires PRINTER_PRODUCTION role'
      using errcode = '42501';
  end if;

  return query
  select
    pj.id,
    pj.job_number,
    so.order_number,
    c.display_name,
    pv.sku_code,
    p.name,
    pj.product_type_snapshot,
    pj.quantity_base_units,
    pj.print_color_count,
    pj.print_specification,
    pj.artwork_reference,
    pj.due_date,
    pj.status,
    pj.qc_state,
    pj.accepted_at,
    pj.started_at,
    pj.notes
  from public.print_jobs pj
  join public.sales_orders so
    on so.id = pj.sales_order_id
  join public.customers c
    on c.id = pj.customer_id
  join public.product_variants pv
    on pv.id = pj.product_variant_id
  join public.products p
    on p.id = pv.product_id
  where pj.assignee_user_id = v_user_id
    and pj.status not in ('CANCELLED','COMPLETED')
  order by pj.due_date asc, pj.job_number asc;
end;
$$;

revoke all on function public.production_mobile_work_queue() from public, anon;
grant execute on function public.production_mobile_work_queue()
to authenticated, service_role;


-- Keep the legacy tracking RPC usable without reopening direct access to the
-- underlying queue view. SECURITY DEFINER is bounded by explicit role checks;
-- production users can only see jobs assigned to their own authenticated user.
create or replace function public.print_job_tracking(p_print_job_id uuid default null)
returns table(
  print_job_id uuid,job_number text,sales_order_id uuid,order_number text,sales_order_item_id uuid,
  customer_name text,product_variant_id uuid,sku_code text,product_name text,product_type_snapshot text,
  quantity_base_units numeric,print_color_count integer,print_specification text,artwork_reference text,
  due_date date,assignee_user_id uuid,status text,qc_state text,accepted_at timestamptz,
  started_at timestamptz,notes text
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_is_owner boolean := public.current_user_has_role('OWNER_ADMIN');
  v_is_printer boolean := public.current_user_has_role('PRINTER_PRODUCTION');
begin
  if v_user_id is null or not (v_is_owner or v_is_printer) then
    raise exception 'Print-job tracking requires OWNER_ADMIN or PRINTER_PRODUCTION role'
      using errcode = '42501';
  end if;

  return query
  select
    pj.id,
    pj.job_number,
    pj.sales_order_id,
    so.order_number,
    pj.sales_order_item_id,
    c.display_name,
    pj.product_variant_id,
    pv.sku_code,
    p.name,
    pj.product_type_snapshot,
    pj.quantity_base_units,
    pj.print_color_count,
    pj.print_specification,
    pj.artwork_reference,
    pj.due_date,
    pj.assignee_user_id,
    pj.status,
    pj.qc_state,
    pj.accepted_at,
    pj.started_at,
    pj.notes
  from public.print_jobs pj
  join public.sales_orders so
    on so.id = pj.sales_order_id
  join public.customers c
    on c.id = pj.customer_id
  join public.product_variants pv
    on pv.id = pj.product_variant_id
  join public.products p
    on p.id = pv.product_id
  where (p_print_job_id is null or pj.id = p_print_job_id)
    and (
      v_is_owner
      or (v_is_printer and pj.assignee_user_id = v_user_id)
    )
  order by pj.due_date asc, pj.job_number asc;
end;
$$;

revoke all on function public.print_job_tracking(uuid) from public, anon;
grant execute on function public.print_job_tracking(uuid)
to authenticated, service_role;

commit;
