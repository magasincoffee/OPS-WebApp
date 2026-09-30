-- OPS-041: production assignment and mobile work queue
-- Architecture Generation 1
-- Source of Truth: SOURCE_OF_TRUTH.md
begin;

create or replace function private.guard_print_job_workflow()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,pg_temp
as $$
declare
  v_assignee_is_active_production boolean;
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

    if new.assignee_user_id is not null then
      select exists(
        select 1
        from public.users u
        join public.user_roles ur on ur.user_id=u.id
        join public.roles r on r.id=ur.role_id
        where u.id=new.assignee_user_id
          and u.is_active=true
          and r.code='PRINTER_PRODUCTION'
      ) into v_assignee_is_active_production;

      if not v_assignee_is_active_production then
        raise exception 'Print-job assignee must be an active PRINTER_PRODUCTION user';
      end if;
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
    if old.status<>'WAITING' then
      raise exception 'Print-job assignment is locked unless job is WAITING';
    end if;

    if new.assignee_user_id is not null then
      select exists(
        select 1
        from public.users u
        join public.user_roles ur on ur.user_id=u.id
        join public.roles r on r.id=ur.role_id
        where u.id=new.assignee_user_id
          and u.is_active=true
          and r.code='PRINTER_PRODUCTION'
      ) into v_assignee_is_active_production;

      if not v_assignee_is_active_production then
        raise exception 'Print-job assignee must be an active PRINTER_PRODUCTION user';
      end if;
    end if;
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
    if new.assignee_user_id is null then
      raise exception 'Print job must be assigned before it can be ACCEPTED';
    end if;
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

create or replace function public.production_assignee_directory()
returns table(
  user_id uuid,
  display_name text
)
language plpgsql
stable
security invoker
set search_path=public,pg_temp
as $$
begin
  if not public.current_user_has_role('OWNER_ADMIN') then
    raise exception 'Production assignee directory requires OWNER_ADMIN role'
      using errcode='42501';
  end if;

  return query
  select u.id,u.display_name
  from public.users u
  join public.user_roles ur on ur.user_id=u.id
  join public.roles r on r.id=ur.role_id
  where u.is_active=true
    and r.code='PRINTER_PRODUCTION'
  order by coalesce(u.display_name,u.id::text),u.id;
end;
$$;
revoke all on function public.production_assignee_directory() from public,anon;
grant execute on function public.production_assignee_directory() to authenticated,service_role;

create or replace function public.assign_print_job(
  p_print_job_id uuid,
  p_assignee_user_id uuid,
  p_note text default null
)
returns uuid
language plpgsql
security invoker
set search_path=public,pg_temp
as $$
declare
  v_user_id uuid:=(select auth.uid());
  v_old_assignee uuid;
  v_status text;
begin
  if v_user_id is null or not public.current_user_has_role('OWNER_ADMIN') then
    raise exception 'Print-job assignment requires OWNER_ADMIN role'
      using errcode='42501';
  end if;

  select pj.assignee_user_id,pj.status
  into v_old_assignee,v_status
  from public.print_jobs pj
  where pj.id=p_print_job_id
  for update;

  if not found then raise exception 'Print job % does not exist',p_print_job_id; end if;
  if v_status<>'WAITING' then raise exception 'Print-job assignment is locked unless job is WAITING'; end if;
  if p_assignee_user_id is not distinct from v_old_assignee then
    raise exception 'Print-job assignee is unchanged';
  end if;

  update public.print_jobs
  set assignee_user_id=p_assignee_user_id
  where id=p_print_job_id;

  insert into public.print_job_events(
    print_job_id,event_type,from_status,to_status,qc_state,assignee_user_id,actor_user_id,note
  )
  select
    pj.id,
    'ASSIGNMENT_CHANGED',
    pj.status,
    pj.status,
    pj.qc_state,
    pj.assignee_user_id,
    v_user_id,
    coalesce(
      nullif(btrim(coalesce(p_note,'')),''),
      case
        when pj.assignee_user_id is null then 'Print job unassigned'
        when v_old_assignee is null then 'Print job assigned'
        else 'Print job reassigned'
      end
    )
  from public.print_jobs pj
  where pj.id=p_print_job_id;

  return p_print_job_id;
end;
$$;
revoke all on function public.assign_print_job(uuid,uuid,text) from public,anon;
grant execute on function public.assign_print_job(uuid,uuid,text) to authenticated,service_role;

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
security invoker
set search_path=public,pg_temp
as $$
declare
  v_user_id uuid:=(select auth.uid());
begin
  if v_user_id is null or not public.current_user_has_role('PRINTER_PRODUCTION') then
    raise exception 'Production mobile queue requires PRINTER_PRODUCTION role'
      using errcode='42501';
  end if;

  return query
  select
    q.print_job_id,q.job_number,q.order_number,q.customer_name,q.sku_code,q.product_name,
    q.product_type_snapshot,q.quantity_base_units,q.print_color_count,q.print_specification,
    q.artwork_reference,q.due_date,q.status,q.qc_state,q.accepted_at,q.started_at,q.notes
  from public.production_print_job_queue q
  where q.assignee_user_id=v_user_id
    and q.status<>'CANCELLED'
  order by q.due_date asc,q.job_number asc;
end;
$$;
revoke all on function public.production_mobile_work_queue() from public,anon;
grant execute on function public.production_mobile_work_queue() to authenticated,service_role;

commit;
