-- OPS-003 bounded unit: print-production RBAC policies
-- Architecture Generation 1
-- Source of Truth: SOURCE_OF_TRUTH.md
--
-- Scope is intentionally limited to print_jobs, print_job_events, and a
-- non-financial production queue projection.
-- Customer-finance, delivery, operational-task authorization and representative
-- permission verification remain later bounded units inside OPS-003.
--
-- Policy intent derived from SOT Section 5:
-- - OWNER_ADMIN: full access to production records.
-- - PRINTER_PRODUCTION: read/update only jobs assigned to the current user and
--   read/append events only for those assigned jobs.
-- - Production users may change production/QC execution fields, but cannot
--   rewrite source order/customer/product/specification/assignment data.
-- - SALES, ACCOUNTING, and WAREHOUSE receive no direct production-table access.
-- - A sanitized queue view exposes order/customer/product identity required to
--   perform production without exposing selling price, cost, margin, debt, or
--   other financial fields.

begin;

revoke all on public.print_jobs, public.print_job_events from anon;
revoke all on public.print_jobs, public.print_job_events from authenticated;

grant select, insert, update, delete on
  public.print_jobs,
  public.print_job_events
to authenticated;

grant all on public.print_jobs, public.print_job_events to service_role;

create policy print_jobs_select_owner_or_assigned_production
on public.print_jobs
for select
to authenticated
using (
  public.current_user_has_role('OWNER_ADMIN')
  or (
    public.current_user_has_role('PRINTER_PRODUCTION')
    and assignee_user_id = auth.uid()
  )
);

create policy print_jobs_insert_owner_admin
on public.print_jobs
for insert
to authenticated
with check (public.current_user_has_role('OWNER_ADMIN'));

create policy print_jobs_update_owner_or_assigned_production
on public.print_jobs
for update
to authenticated
using (
  public.current_user_has_role('OWNER_ADMIN')
  or (
    public.current_user_has_role('PRINTER_PRODUCTION')
    and assignee_user_id = auth.uid()
  )
)
with check (
  public.current_user_has_role('OWNER_ADMIN')
  or (
    public.current_user_has_role('PRINTER_PRODUCTION')
    and assignee_user_id = auth.uid()
  )
);

create policy print_jobs_delete_owner_admin
on public.print_jobs
for delete
to authenticated
using (public.current_user_has_role('OWNER_ADMIN'));

create policy print_job_events_select_owner_or_assigned_production
on public.print_job_events
for select
to authenticated
using (
  public.current_user_has_role('OWNER_ADMIN')
  or (
    public.current_user_has_role('PRINTER_PRODUCTION')
    and exists (
      select 1
      from public.print_jobs pj
      where pj.id = print_job_events.print_job_id
        and pj.assignee_user_id = auth.uid()
    )
  )
);

create policy print_job_events_insert_owner_or_assigned_production
on public.print_job_events
for insert
to authenticated
with check (
  public.current_user_has_role('OWNER_ADMIN')
  or (
    public.current_user_has_role('PRINTER_PRODUCTION')
    and actor_user_id = auth.uid()
    and exists (
      select 1
      from public.print_jobs pj
      where pj.id = print_job_events.print_job_id
        and pj.assignee_user_id = auth.uid()
    )
  )
);

create policy print_job_events_update_owner_admin
on public.print_job_events
for update
to authenticated
using (public.current_user_has_role('OWNER_ADMIN'))
with check (public.current_user_has_role('OWNER_ADMIN'));

create policy print_job_events_delete_owner_admin
on public.print_job_events
for delete
to authenticated
using (public.current_user_has_role('OWNER_ADMIN'));

create or replace function public.guard_print_job_production_update()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if auth.role() = 'service_role'
     or public.current_user_has_role('OWNER_ADMIN') then
    return new;
  end if;

  if public.current_user_has_role('PRINTER_PRODUCTION') then
    if new.id is distinct from old.id
       or new.job_number is distinct from old.job_number
       or new.sales_order_id is distinct from old.sales_order_id
       or new.sales_order_item_id is distinct from old.sales_order_item_id
       or new.customer_id is distinct from old.customer_id
       or new.product_variant_id is distinct from old.product_variant_id
       or new.product_type_snapshot is distinct from old.product_type_snapshot
       or new.quantity_base_units is distinct from old.quantity_base_units
       or new.print_color_count is distinct from old.print_color_count
       or new.print_specification is distinct from old.print_specification
       or new.artwork_reference is distinct from old.artwork_reference
       or new.due_date is distinct from old.due_date
       or new.assignee_user_id is distinct from old.assignee_user_id
       or new.created_by_user_id is distinct from old.created_by_user_id
       or new.created_at is distinct from old.created_at then
      raise exception
        'PRINTER_PRODUCTION may update only production/QC execution fields on assigned print jobs';
    end if;
  end if;

  return new;
end;
$$;

revoke all on function public.guard_print_job_production_update()
from public, anon, authenticated;

drop trigger if exists print_jobs_guard_production_update on public.print_jobs;
create trigger print_jobs_guard_production_update
before update on public.print_jobs
for each row execute function public.guard_print_job_production_update();

create or replace view public.production_print_job_queue
with (security_barrier = true)
as
select
  pj.id as print_job_id,
  pj.job_number,
  pj.sales_order_id,
  so.order_number,
  pj.sales_order_item_id,
  pj.customer_id,
  c.display_name as customer_name,
  pj.product_variant_id,
  pv.sku_code,
  p.name as product_name,
  pj.product_type_snapshot,
  pj.quantity_base_units,
  pj.print_color_count,
  pj.print_specification,
  pj.artwork_reference,
  pj.due_date,
  pj.assignee_user_id,
  pj.status,
  pj.qc_state,
  pj.completion_evidence_reference,
  pj.accepted_at,
  pj.started_at,
  pj.qc_completed_at,
  pj.completed_at,
  pj.notes,
  pj.created_at,
  pj.updated_at
from public.print_jobs pj
join public.sales_orders so
  on so.id = pj.sales_order_id
join public.customers c
  on c.id = pj.customer_id
join public.product_variants pv
  on pv.id = pj.product_variant_id
join public.products p
  on p.id = pv.product_id
where
  public.current_user_has_role('OWNER_ADMIN')
  or (
    public.current_user_has_role('PRINTER_PRODUCTION')
    and pj.assignee_user_id = auth.uid()
  );

alter view public.production_print_job_queue set (security_invoker = false);

revoke all on public.production_print_job_queue from public, anon;
grant select on public.production_print_job_queue to authenticated;
grant all on public.production_print_job_queue to service_role;

commit;
