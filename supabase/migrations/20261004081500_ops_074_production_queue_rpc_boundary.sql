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
    and pj.status <> 'CANCELLED'
  order by pj.due_date asc, pj.job_number asc;
end;
$$;

revoke all on function public.production_mobile_work_queue() from public, anon;
grant execute on function public.production_mobile_work_queue()
to authenticated, service_role;

commit;
