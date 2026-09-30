-- OPS-040: print-job workflow
-- Architecture Generation 1
-- Source of Truth: SOURCE_OF_TRUTH.md
begin;

create unique index if not exists print_jobs_one_active_per_sales_order_item
  on public.print_jobs(sales_order_item_id)
  where status <> 'CANCELLED';

create or replace function public.validate_print_job_source()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  v_sales_order_id uuid;
  v_order_status text;
  v_order_print_status text;
  v_customer_id uuid;
  v_product_variant_id uuid;
  v_product_type text;
  v_base_quantity numeric(18,6);
  v_print_mode text;
  v_print_color_count integer;
  v_print_specification text;
  v_artwork_reference text;
  v_due_date date;
begin
  select soi.sales_order_id,so.order_status,so.print_status,so.customer_id,
         soi.product_variant_id,p.product_type,soi.base_quantity,soi.print_mode,
         soi.print_color_count,soi.print_specification,soi.artwork_reference,
         coalesce(soi.requested_due_date,so.requested_due_date)
  into v_sales_order_id,v_order_status,v_order_print_status,v_customer_id,
       v_product_variant_id,v_product_type,v_base_quantity,v_print_mode,
       v_print_color_count,v_print_specification,v_artwork_reference,v_due_date
  from public.sales_order_items soi
  join public.sales_orders so on so.id=soi.sales_order_id
  join public.product_variants pv on pv.id=soi.product_variant_id
  join public.products p on p.id=pv.product_id
  where soi.id=new.sales_order_item_id;

  if not found then raise exception 'Print job source sales-order item % does not exist',new.sales_order_item_id; end if;
  if v_order_status<>'CONFIRMED' then raise exception 'Print job source sales order must be CONFIRMED'; end if;
  if v_print_mode<>'PRINTED' then raise exception 'Plain/no-print sales-order item cannot generate a print job'; end if;
  if v_order_print_status not in ('WAITING','IN_PROGRESS','WAITING_QC') then
    raise exception 'Print job source sales order is not in an active print branch';
  end if;

  if new.sales_order_id is distinct from v_sales_order_id then raise exception 'Print job sales_order_id must match its source sales-order item'; end if;
  if new.customer_id is distinct from v_customer_id then raise exception 'Print job customer_id must match its source sales order'; end if;
  if new.product_variant_id is distinct from v_product_variant_id then raise exception 'Print job product_variant_id must match its source sales-order item'; end if;
  if new.product_type_snapshot is distinct from v_product_type then raise exception 'Print job product type snapshot must match its source sales-order item'; end if;
  if new.quantity_base_units is distinct from v_base_quantity then raise exception 'Print job quantity must match its source sales-order item'; end if;
  if new.print_color_count is distinct from v_print_color_count then raise exception 'Print job color count must match its source sales-order item'; end if;
  if new.print_specification is distinct from v_print_specification then raise exception 'Print job specification must match its source sales-order item'; end if;
  if new.artwork_reference is distinct from v_artwork_reference then raise exception 'Print job artwork reference must match its source sales-order item'; end if;
  if new.due_date is distinct from v_due_date then raise exception 'Print job due date must match its source sales-order item/order'; end if;
  return new;
end;
$$;
revoke all on function public.validate_print_job_source() from public,anon,authenticated;

drop trigger if exists print_jobs_validate_source on public.print_jobs;
create trigger print_jobs_validate_source
before insert or update of sales_order_id,sales_order_item_id,customer_id,product_variant_id,
  product_type_snapshot,quantity_base_units,print_color_count,print_specification,artwork_reference,due_date
on public.print_jobs
for each row execute function public.validate_print_job_source();

create or replace function private.guard_print_job_workflow()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,pg_temp
as $$
begin
  if tg_op='INSERT' then
    if new.status<>'WAITING' then raise exception 'New print jobs must start in WAITING'; end if;
    if new.qc_state<>'PENDING' or new.qc_completed_at is not null or new.completed_at is not null
       or new.completion_evidence_reference is not null then
      raise exception 'QC and completion fields are reserved for OPS-042';
    end if;
    if new.accepted_at is not null or new.started_at is not null then
      raise exception 'Print-job execution timestamps are workflow-managed';
    end if;
    return new;
  end if;

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
     or new.created_by_user_id is distinct from old.created_by_user_id
     or new.created_at is distinct from old.created_at then
    raise exception 'Print-job source and specification snapshots are immutable';
  end if;

  if new.assignee_user_id is distinct from old.assignee_user_id then
    raise exception 'Print-job assignment is reserved for OPS-041';
  end if;

  if new.qc_state is distinct from old.qc_state
     or new.qc_completed_at is distinct from old.qc_completed_at
     or new.completed_at is distinct from old.completed_at
     or new.completion_evidence_reference is distinct from old.completion_evidence_reference then
    raise exception 'QC and completion fields are reserved for OPS-042';
  end if;

  if new.status is not distinct from old.status then
    if new.accepted_at is distinct from old.accepted_at or new.started_at is distinct from old.started_at then
      raise exception 'Print-job execution timestamps are workflow-managed';
    end if;
    return new;
  end if;

  if new.status='COMPLETED' then raise exception 'Print-job completion is reserved for OPS-042 QC workflow'; end if;

  if not (
    (old.status='WAITING' and new.status in ('ACCEPTED','CANCELLED'))
    or (old.status='ACCEPTED' and new.status in ('IN_PROGRESS','CANCELLED'))
    or (old.status='IN_PROGRESS' and new.status in ('WAITING_QC','CANCELLED'))
  ) then
    raise exception 'Invalid print-job status transition from % to %',old.status,new.status;
  end if;

  if new.status='ACCEPTED' then
    new.accepted_at:=coalesce(old.accepted_at,timezone('utc',now()));
    new.started_at:=null;
  elsif new.status='IN_PROGRESS' then
    new.accepted_at:=coalesce(old.accepted_at,timezone('utc',now()));
    new.started_at:=coalesce(old.started_at,timezone('utc',now()));
  end if;
  return new;
end;
$$;
revoke all on function private.guard_print_job_workflow() from public,anon,authenticated;

drop trigger if exists print_jobs_guard_workflow on public.print_jobs;
create trigger print_jobs_guard_workflow
before insert or update on public.print_jobs
for each row execute function private.guard_print_job_workflow();

create or replace function private.refresh_sales_order_print_status(p_sales_order_id uuid)
returns void
language plpgsql
security definer
set search_path=pg_catalog,pg_temp
as $$
declare
  v_required_count integer;
  v_covered_count integer;
  v_completed_count integer;
  v_waiting_qc_or_completed_count integer;
  v_progressed_count integer;
  v_status text;
begin
  select count(*)::integer into v_required_count
  from public.sales_order_items soi
  where soi.sales_order_id=p_sales_order_id and soi.print_mode='PRINTED';

  if v_required_count=0 then
    v_status:='NOT_REQUIRED';
  else
    select count(*)::integer,
           count(*) filter(where pj.status='COMPLETED')::integer,
           count(*) filter(where pj.status in ('WAITING_QC','COMPLETED'))::integer,
           count(*) filter(where pj.status in ('ACCEPTED','IN_PROGRESS','WAITING_QC','COMPLETED'))::integer
    into v_covered_count,v_completed_count,v_waiting_qc_or_completed_count,v_progressed_count
    from public.print_jobs pj
    where pj.sales_order_id=p_sales_order_id and pj.status<>'CANCELLED';

    if v_covered_count<v_required_count then v_status:='WAITING';
    elsif v_completed_count=v_required_count then v_status:='COMPLETED';
    elsif v_waiting_qc_or_completed_count=v_required_count then v_status:='WAITING_QC';
    elsif v_progressed_count>0 then v_status:='IN_PROGRESS';
    else v_status:='WAITING';
    end if;
  end if;

  update public.sales_orders set print_status=v_status
  where id=p_sales_order_id and print_status is distinct from v_status;
end;
$$;
revoke all on function private.refresh_sales_order_print_status(uuid) from public,anon,authenticated;

create or replace function private.sync_sales_order_print_status_from_jobs()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,pg_temp
as $$
declare v_sales_order_id uuid;
begin
  v_sales_order_id:=case when tg_op='DELETE' then old.sales_order_id else new.sales_order_id end;
  if v_sales_order_id is not null then perform private.refresh_sales_order_print_status(v_sales_order_id); end if;
  return case when tg_op='DELETE' then old else new end;
end;
$$;
revoke all on function private.sync_sales_order_print_status_from_jobs() from public,anon,authenticated;

drop trigger if exists print_jobs_sync_sales_order_print_status on public.print_jobs;
create trigger print_jobs_sync_sales_order_print_status
after insert or update of status or delete on public.print_jobs
for each row execute function private.sync_sales_order_print_status_from_jobs();

create or replace function public.print_job_requirement_queue()
returns table(
  sales_order_item_id uuid,sales_order_id uuid,order_number text,customer_name text,
  product_variant_id uuid,sku_code text,product_name text,product_type_snapshot text,
  quantity_base_units numeric,print_color_count integer,print_specification text,
  artwork_reference text,due_date date,order_print_status text
)
language plpgsql
stable
security invoker
set search_path=public,pg_temp
as $$
begin
  if not public.current_user_has_role('OWNER_ADMIN') then
    raise exception 'Print-job requirement queue requires OWNER_ADMIN role' using errcode='42501';
  end if;

  return query
  select req.sales_order_item_id,req.sales_order_id,req.order_number,req.customer_name,
         req.product_variant_id,req.sku_code,req.product_name,req.product_type_snapshot,
         req.quantity_base_units,req.print_color_count,req.print_specification,
         req.artwork_reference,req.due_date,req.print_status
  from public.sales_order_print_requirements req
  where not exists(
    select 1 from public.print_jobs pj
    where pj.sales_order_item_id=req.sales_order_item_id and pj.status<>'CANCELLED'
  )
  order by req.due_date,req.order_number,req.sku_code;
end;
$$;
revoke all on function public.print_job_requirement_queue() from public,anon;
grant execute on function public.print_job_requirement_queue() to authenticated,service_role;

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
security invoker
set search_path=public,pg_temp
as $$
begin
  if not (public.current_user_has_role('OWNER_ADMIN') or public.current_user_has_role('PRINTER_PRODUCTION')) then
    raise exception 'Print-job tracking requires OWNER_ADMIN or PRINTER_PRODUCTION role' using errcode='42501';
  end if;

  return query
  select q.print_job_id,q.job_number,q.sales_order_id,q.order_number,q.sales_order_item_id,
         q.customer_name,q.product_variant_id,q.sku_code,q.product_name,q.product_type_snapshot,
         q.quantity_base_units,q.print_color_count,q.print_specification,q.artwork_reference,
         q.due_date,q.assignee_user_id,q.status,q.qc_state,q.accepted_at,q.started_at,q.notes
  from public.production_print_job_queue q
  where p_print_job_id is null or q.print_job_id=p_print_job_id
  order by q.due_date,q.job_number;
end;
$$;
revoke all on function public.print_job_tracking(uuid) from public,anon;
grant execute on function public.print_job_tracking(uuid) to authenticated,service_role;

create or replace function public.create_print_job_from_requirement(
  p_job_number text,p_sales_order_item_id uuid,p_notes text default null
)
returns uuid
language plpgsql
security invoker
set search_path=public,pg_temp
as $$
declare
  v_user_id uuid:=(select auth.uid());
  v_job_id uuid;
  v_req record;
begin
  if v_user_id is null or not public.current_user_has_role('OWNER_ADMIN') then
    raise exception 'Create print job requires OWNER_ADMIN role' using errcode='42501';
  end if;
  if p_job_number is null or length(btrim(p_job_number))=0 then raise exception 'Print job number is required'; end if;

  perform pg_advisory_xact_lock(hashtextextended(p_sales_order_item_id::text,40));

  select * into v_req
  from public.sales_order_print_requirements req
  where req.sales_order_item_id=p_sales_order_item_id;
  if not found then raise exception 'Active PRINTED requirement % does not exist',p_sales_order_item_id; end if;

  if exists(select 1 from public.print_jobs pj where pj.sales_order_item_id=p_sales_order_item_id and pj.status<>'CANCELLED') then
    raise exception 'Sales-order item already has an active print job';
  end if;
  if exists(select 1 from public.print_jobs pj where pj.job_number=btrim(p_job_number)) then
    raise exception 'Print job number already exists';
  end if;

  insert into public.print_jobs(
    job_number,sales_order_id,sales_order_item_id,customer_id,product_variant_id,
    product_type_snapshot,quantity_base_units,print_color_count,print_specification,
    artwork_reference,due_date,status,qc_state,created_by_user_id,notes
  )
  values(
    btrim(p_job_number),v_req.sales_order_id,v_req.sales_order_item_id,v_req.customer_id,
    v_req.product_variant_id,v_req.product_type_snapshot,v_req.quantity_base_units,
    v_req.print_color_count,v_req.print_specification,v_req.artwork_reference,v_req.due_date,
    'WAITING','PENDING',v_user_id,nullif(btrim(coalesce(p_notes,'')),'')
  )
  returning id into v_job_id;

  insert into public.print_job_events(
    print_job_id,event_type,from_status,to_status,qc_state,actor_user_id,note
  )
  values(
    v_job_id,'PRINT_JOB_CREATED',null,'WAITING','PENDING',v_user_id,
    'Materialized from confirmed PRINTED sales-order requirement'
  );

  return v_job_id;
end;
$$;
revoke all on function public.create_print_job_from_requirement(text,uuid,text) from public,anon;
grant execute on function public.create_print_job_from_requirement(text,uuid,text) to authenticated,service_role;

create or replace function public.set_print_job_status(
  p_print_job_id uuid,p_status text,p_note text default null
)
returns uuid
language plpgsql
security invoker
set search_path=public,pg_temp
as $$
declare
  v_user_id uuid:=(select auth.uid());
  v_current_status text;
  v_assignee_user_id uuid;
  v_target text:=upper(btrim(coalesce(p_status,'')));
begin
  if v_user_id is null then raise exception 'Authentication required' using errcode='42501'; end if;
  if v_target='COMPLETED' then raise exception 'Print-job completion is reserved for OPS-042 QC workflow'; end if;
  if v_target not in ('ACCEPTED','IN_PROGRESS','WAITING_QC','CANCELLED') then
    raise exception 'Unsupported print-job status action %',v_target;
  end if;

  select pj.status,pj.assignee_user_id into v_current_status,v_assignee_user_id
  from public.print_jobs pj where pj.id=p_print_job_id for update;
  if not found then raise exception 'Print job % does not exist or is not visible',p_print_job_id; end if;

  if not (
    public.current_user_has_role('OWNER_ADMIN')
    or (public.current_user_has_role('PRINTER_PRODUCTION') and v_assignee_user_id=v_user_id)
  ) then
    raise exception 'Print-job status change requires OWNER_ADMIN or assigned PRINTER_PRODUCTION role' using errcode='42501';
  end if;

  if v_target=v_current_status then raise exception 'Print job is already in status %',v_target; end if;

  update public.print_jobs set status=v_target where id=p_print_job_id;

  insert into public.print_job_events(
    print_job_id,event_type,from_status,to_status,qc_state,assignee_user_id,actor_user_id,note
  )
  select pj.id,'STATUS_CHANGED',v_current_status,v_target,pj.qc_state,pj.assignee_user_id,
         v_user_id,nullif(btrim(coalesce(p_note,'')),'')
  from public.print_jobs pj where pj.id=p_print_job_id;

  return p_print_job_id;
end;
$$;
revoke all on function public.set_print_job_status(uuid,text,text) from public,anon;
grant execute on function public.set_print_job_status(uuid,text,text) to authenticated,service_role;

commit;
