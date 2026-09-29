-- OPS-002 bounded unit: print-production database foundation
-- Architecture Generation 1
-- Source of Truth: SOURCE_OF_TRUTH.md
--
-- Scope is limited to print-job identity/specification, production/QC status
-- dimensions, production events, and database enforcement that only PRINTED
-- sales-order items can source print jobs. Workflow transitions, task queues,
-- auth/RBAC, attachments, general audit logging, and UI remain in later OPS tasks.

begin;

create table public.print_jobs (
  id uuid primary key default gen_random_uuid(),
  job_number text not null unique,
  sales_order_id uuid not null references public.sales_orders(id) on delete restrict,
  sales_order_item_id uuid not null references public.sales_order_items(id) on delete restrict,
  customer_id uuid not null references public.customers(id) on delete restrict,
  product_variant_id uuid not null references public.product_variants(id) on delete restrict,
  product_type_snapshot text,
  quantity_base_units numeric(18,6) not null,
  print_color_count integer not null,
  print_specification text,
  artwork_reference text,
  due_date date not null,
  assignee_user_id uuid,
  status text not null default 'WAITING',
  qc_state text not null default 'PENDING',
  completion_evidence_reference text,
  accepted_at timestamptz,
  started_at timestamptz,
  qc_completed_at timestamptz,
  completed_at timestamptz,
  created_by_user_id uuid,
  notes text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint print_jobs_number_not_blank
    check (length(btrim(job_number)) > 0),
  constraint print_jobs_quantity_positive
    check (quantity_base_units > 0),
  constraint print_jobs_color_count_positive
    check (print_color_count > 0),
  constraint print_jobs_status_valid
    check (
      status in (
        'WAITING',
        'ACCEPTED',
        'IN_PROGRESS',
        'WAITING_QC',
        'COMPLETED',
        'CANCELLED'
      )
    ),
  constraint print_jobs_qc_state_valid
    check (qc_state in ('PENDING', 'PASSED', 'FAILED')),
  constraint print_jobs_qc_timestamp_consistent
    check (
      (qc_state = 'PENDING' and qc_completed_at is null)
      or
      (qc_state in ('PASSED', 'FAILED') and qc_completed_at is not null)
    ),
  constraint print_jobs_completion_consistent
    check (
      (
        status = 'COMPLETED'
        and completed_at is not null
        and qc_state = 'PASSED'
        and qc_completed_at is not null
      )
      or
      (
        status <> 'COMPLETED'
        and completed_at is null
      )
    ),
  constraint print_jobs_timestamp_order_valid
    check (
      (accepted_at is null or accepted_at >= created_at)
      and (started_at is null or accepted_at is null or started_at >= accepted_at)
      and (qc_completed_at is null or started_at is null or qc_completed_at >= started_at)
      and (completed_at is null or qc_completed_at is null or completed_at >= qc_completed_at)
    )
);

create table public.print_job_events (
  id uuid primary key default gen_random_uuid(),
  print_job_id uuid not null references public.print_jobs(id) on delete cascade,
  event_type text not null,
  from_status text,
  to_status text,
  qc_state text,
  assignee_user_id uuid,
  evidence_reference text,
  note text,
  actor_user_id uuid,
  occurred_at timestamptz not null default timezone('utc', now()),
  created_at timestamptz not null default timezone('utc', now()),
  constraint print_job_events_type_not_blank
    check (length(btrim(event_type)) > 0),
  constraint print_job_events_from_status_valid
    check (
      from_status is null
      or from_status in (
        'WAITING',
        'ACCEPTED',
        'IN_PROGRESS',
        'WAITING_QC',
        'COMPLETED',
        'CANCELLED'
      )
    ),
  constraint print_job_events_to_status_valid
    check (
      to_status is null
      or to_status in (
        'WAITING',
        'ACCEPTED',
        'IN_PROGRESS',
        'WAITING_QC',
        'COMPLETED',
        'CANCELLED'
      )
    ),
  constraint print_job_events_qc_state_valid
    check (qc_state is null or qc_state in ('PENDING', 'PASSED', 'FAILED'))
);

create or replace function public.validate_print_job_source()
returns trigger
language plpgsql
as $$
declare
  source_order_id uuid;
  source_customer_id uuid;
  source_variant_id uuid;
  source_print_mode text;
begin
  select
    soi.sales_order_id,
    so.customer_id,
    soi.product_variant_id,
    soi.print_mode
  into
    source_order_id,
    source_customer_id,
    source_variant_id,
    source_print_mode
  from public.sales_order_items soi
  join public.sales_orders so
    on so.id = soi.sales_order_id
  where soi.id = new.sales_order_item_id;

  if source_order_id is null then
    raise exception
      'Print job source sales-order item % does not exist',
      new.sales_order_item_id;
  end if;

  if source_print_mode <> 'PRINTED' then
    raise exception
      'Plain/no-print sales-order item % cannot generate a print job',
      new.sales_order_item_id;
  end if;

  if new.sales_order_id <> source_order_id then
    raise exception
      'Print job sales_order_id must match its source sales-order item';
  end if;

  if new.customer_id <> source_customer_id then
    raise exception
      'Print job customer_id must match its source sales order';
  end if;

  if new.product_variant_id <> source_variant_id then
    raise exception
      'Print job product_variant_id must match its source sales-order item';
  end if;

  return new;
end;
$$;

create trigger print_jobs_validate_source
before insert or update of
  sales_order_id,
  sales_order_item_id,
  customer_id,
  product_variant_id
on public.print_jobs
for each row execute function public.validate_print_job_source();

create view public.print_job_queue as
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
  on p.id = pv.product_id;

create index print_jobs_sales_order_id_idx
  on public.print_jobs(sales_order_id);

create index print_jobs_sales_order_item_id_idx
  on public.print_jobs(sales_order_item_id);

create index print_jobs_customer_id_idx
  on public.print_jobs(customer_id);

create index print_jobs_product_variant_id_idx
  on public.print_jobs(product_variant_id);

create index print_jobs_queue_idx
  on public.print_jobs(status, due_date, assignee_user_id);

create index print_job_events_job_occurred_at_idx
  on public.print_job_events(print_job_id, occurred_at);

create trigger print_jobs_set_updated_at
before update on public.print_jobs
for each row execute function public.set_updated_at();

commit;
