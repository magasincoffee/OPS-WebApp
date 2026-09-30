-- OPS-042: QC and production completion evidence
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
  v_qc_rpc boolean := coalesce(current_setting('ops.print_job_qc_rpc',true),'off')='on';
begin
  if tg_op='INSERT' then
    if new.status<>'WAITING' then raise exception 'New print jobs must start in WAITING'; end if;
    if new.qc_state<>'PENDING' or new.qc_completed_at is not null or new.completed_at is not null
       or new.completion_evidence_reference is not null then
      raise exception 'QC and completion fields are workflow-managed';
    end if;
    if new.accepted_at is not null or new.started_at is not null then
      raise exception 'Print-job execution timestamps are workflow-managed';
    end if;
    if new.assignee_user_id is not null then
      select exists(
        select 1 from public.users u
        join public.user_roles ur on ur.user_id=u.id
        join public.roles r on r.id=ur.role_id
        where u.id=new.assignee_user_id and u.is_active=true and r.code='PRINTER_PRODUCTION'
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
    if coalesce(current_setting('ops.print_job_assignment_rpc',true),'off')<>'on' then
      raise exception 'Print-job assignment changes must use assign_print_job';
    end if;
    if new.assignee_user_id is not null then
      select exists(
        select 1 from public.users u
        join public.user_roles ur on ur.user_id=u.id
        join public.roles r on r.id=ur.role_id
        where u.id=new.assignee_user_id and u.is_active=true and r.code='PRINTER_PRODUCTION'
      ) into v_assignee_is_active_production;
      if not v_assignee_is_active_production then
        raise exception 'Print-job assignee must be an active PRINTER_PRODUCTION user';
      end if;
    end if;
  end if;

  if v_qc_rpc then
    if old.status<>'WAITING_QC' then
      raise exception 'QC may be submitted only for WAITING_QC print jobs';
    end if;
    if new.assignee_user_id is distinct from old.assignee_user_id then
      raise exception 'Print-job assignment remains locked during QC';
    end if;

    if new.status='COMPLETED' then
      if new.qc_state<>'PASSED'
         or new.qc_completed_at is null
         or new.completed_at is null
         or new.completion_evidence_reference is null
         or length(btrim(new.completion_evidence_reference))=0 then
        raise exception 'Completed print job requires PASSED QC and completion evidence';
      end if;
    elsif new.status='IN_PROGRESS' then
      if new.qc_state<>'FAILED'
         or new.qc_completed_at is null
         or new.completed_at is not null
         or new.completion_evidence_reference is null
         or length(btrim(new.completion_evidence_reference))=0 then
        raise exception 'Failed QC requires evidence and must return job to IN_PROGRESS';
      end if;
    else
      raise exception 'QC result must complete the job or return it to IN_PROGRESS';
    end if;
    return new;
  end if;

  if new.qc_state is distinct from old.qc_state
     or new.qc_completed_at is distinct from old.qc_completed_at
     or new.completed_at is distinct from old.completed_at
     or new.completion_evidence_reference is distinct from old.completion_evidence_reference then
    raise exception 'QC and completion fields must use submit_print_job_qc';
  end if;

  if new.status is not distinct from old.status then
    if new.accepted_at is distinct from old.accepted_at or new.started_at is distinct from old.started_at then
      raise exception 'Print-job execution timestamps are workflow-managed';
    end if;
    return new;
  end if;

  if new.status='COMPLETED' then
    raise exception 'Print-job completion must use submit_print_job_qc';
  end if;

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

create or replace function public.create_print_job_evidence_attachment(
  p_print_job_id uuid,
  p_storage_path text,
  p_original_file_name text,
  p_media_type text default null,
  p_size_bytes bigint default null
)
returns uuid
language plpgsql
security invoker
set search_path=public,pg_temp
as $$
declare
  v_user_id uuid:=(select auth.uid());
  v_status text;
  v_assignee uuid;
  v_attachment_id uuid;
  v_expected_prefix text:='print-jobs/'||p_print_job_id::text||'/';
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode='42501';
  end if;

  select pj.status,pj.assignee_user_id
  into v_status,v_assignee
  from public.print_jobs pj
  where pj.id=p_print_job_id;

  if not found then
    raise exception 'Print job % does not exist or is not visible',p_print_job_id;
  end if;

  if not (
    public.current_user_has_role('OWNER_ADMIN')
    or (public.current_user_has_role('PRINTER_PRODUCTION') and v_assignee=v_user_id)
  ) then
    raise exception 'Production evidence requires OWNER_ADMIN or assigned PRINTER_PRODUCTION role'
      using errcode='42501';
  end if;

  if v_status not in ('IN_PROGRESS','WAITING_QC') then
    raise exception 'Production evidence may be added only while job is IN_PROGRESS or WAITING_QC';
  end if;

  if p_storage_path is null
     or left(p_storage_path,length(v_expected_prefix))<>v_expected_prefix
     or length(btrim(coalesce(p_original_file_name,'')))=0 then
    raise exception 'Invalid production evidence attachment path or file name';
  end if;

  if p_size_bytes is not null and p_size_bytes<0 then
    raise exception 'Evidence size cannot be negative';
  end if;

  insert into public.attachments(
    linked_entity_type,linked_entity_id,attachment_kind,storage_bucket,storage_path,
    original_file_name,media_type,size_bytes,metadata,uploaded_by_user_id
  )
  values(
    'PRINT_JOB',p_print_job_id,'PRODUCTION_EVIDENCE','ops-attachments',p_storage_path,
    p_original_file_name,nullif(btrim(coalesce(p_media_type,'')),''),
    p_size_bytes,jsonb_build_object('purpose','PRINT_QC'),v_user_id
  )
  returning id into v_attachment_id;

  return v_attachment_id;
end;
$$;
revoke all on function public.create_print_job_evidence_attachment(uuid,text,text,text,bigint) from public,anon;
grant execute on function public.create_print_job_evidence_attachment(uuid,text,text,text,bigint)
to authenticated,service_role;

create or replace function public.submit_print_job_qc(
  p_print_job_id uuid,
  p_result text,
  p_evidence_attachment_id uuid,
  p_note text default null
)
returns uuid
language plpgsql
security invoker
set search_path=public,pg_temp
as $$
declare
  v_user_id uuid:=(select auth.uid());
  v_status text;
  v_assignee uuid;
  v_result text:=upper(btrim(coalesce(p_result,'')));
  v_evidence_reference text;
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode='42501';
  end if;

  if v_result not in ('PASSED','FAILED') then
    raise exception 'QC result must be PASSED or FAILED';
  end if;

  select pj.status,pj.assignee_user_id
  into v_status,v_assignee
  from public.print_jobs pj
  where pj.id=p_print_job_id
  for update;

  if not found then
    raise exception 'Print job % does not exist or is not visible',p_print_job_id;
  end if;

  if not (
    public.current_user_has_role('OWNER_ADMIN')
    or (public.current_user_has_role('PRINTER_PRODUCTION') and v_assignee=v_user_id)
  ) then
    raise exception 'QC submission requires OWNER_ADMIN or assigned PRINTER_PRODUCTION role'
      using errcode='42501';
  end if;

  if v_status<>'WAITING_QC' then
    raise exception 'QC may be submitted only for WAITING_QC print jobs';
  end if;

  select a.id::text
  into v_evidence_reference
  from public.attachments a
  where a.id=p_evidence_attachment_id
    and a.linked_entity_type='PRINT_JOB'
    and a.linked_entity_id=p_print_job_id
    and a.attachment_kind='PRODUCTION_EVIDENCE'
    and (
      public.current_user_has_role('OWNER_ADMIN')
      or a.uploaded_by_user_id=v_user_id
    );

  if v_evidence_reference is null then
    raise exception 'QC requires a valid production evidence attachment for this print job';
  end if;

  perform set_config('ops.print_job_qc_rpc','on',true);

  if v_result='PASSED' then
    update public.print_jobs
    set status='COMPLETED',
        qc_state='PASSED',
        qc_completed_at=timezone('utc',now()),
        completed_at=timezone('utc',now()),
        completion_evidence_reference=v_evidence_reference
    where id=p_print_job_id;
  else
    update public.print_jobs
    set status='IN_PROGRESS',
        qc_state='FAILED',
        qc_completed_at=timezone('utc',now()),
        completed_at=null,
        completion_evidence_reference=v_evidence_reference
    where id=p_print_job_id;
  end if;

  perform set_config('ops.print_job_qc_rpc','off',true);

  insert into public.print_job_events(
    print_job_id,event_type,from_status,to_status,qc_state,assignee_user_id,
    evidence_reference,actor_user_id,note
  )
  select
    pj.id,
    case when v_result='PASSED' then 'QC_PASSED_COMPLETED' else 'QC_FAILED_REWORK' end,
    'WAITING_QC',
    pj.status,
    v_result,
    pj.assignee_user_id,
    v_evidence_reference,
    v_user_id,
    nullif(btrim(coalesce(p_note,'')),'')
  from public.print_jobs pj
  where pj.id=p_print_job_id;

  return p_print_job_id;
end;
$$;
revoke all on function public.submit_print_job_qc(uuid,text,uuid,text) from public,anon;
grant execute on function public.submit_print_job_qc(uuid,text,uuid,text)
to authenticated,service_role;

create or replace function public.production_mobile_work_queue()
returns table(
  print_job_id uuid,job_number text,order_number text,customer_name text,sku_code text,
  product_name text,product_type_snapshot text,quantity_base_units numeric,
  print_color_count integer,print_specification text,artwork_reference text,due_date date,
  status text,qc_state text,accepted_at timestamptz,started_at timestamptz,notes text
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
  select q.print_job_id,q.job_number,q.order_number,q.customer_name,q.sku_code,q.product_name,
         q.product_type_snapshot,q.quantity_base_units,q.print_color_count,q.print_specification,
         q.artwork_reference,q.due_date,q.status,q.qc_state,q.accepted_at,q.started_at,q.notes
  from public.production_print_job_queue q
  where q.assignee_user_id=v_user_id
    and q.status not in ('CANCELLED','COMPLETED')
  order by q.due_date asc,q.job_number asc;
end;
$$;
revoke all on function public.production_mobile_work_queue() from public,anon;
grant execute on function public.production_mobile_work_queue() to authenticated,service_role;

commit;
