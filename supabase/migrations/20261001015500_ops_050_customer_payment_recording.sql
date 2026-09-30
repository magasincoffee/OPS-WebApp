-- OPS-050: customer payment recording
-- Architecture Generation 1
-- Source of Truth: SOURCE_OF_TRUTH.md
begin;

create or replace function private.guard_customer_payment_workflow()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,pg_temp
as $$
declare
  v_actor uuid := auth.uid();
  v_order_status text;
  v_order_customer uuid;
  v_order_total numeric;
  v_existing_paid numeric;
begin
  if tg_op='INSERT' then
    if new.status<>'POSTED' or new.voided_at is not null or new.voided_by_user_id is not null then
      raise exception 'New customer payments must start POSTED and not voided';
    end if;
    if v_actor is not null and new.created_by_user_id is distinct from v_actor then
      raise exception 'Customer payment creator must match authenticated user';
    end if;

    if new.sales_order_id is not null then
      select so.order_status,so.customer_id,sot.total_amount
      into v_order_status,v_order_customer,v_order_total
      from public.sales_orders so
      join public.sales_order_totals sot on sot.sales_order_id=so.id
      where so.id=new.sales_order_id
      for update of so;

      if not found then
        raise exception 'Customer payment source sales order % does not exist',new.sales_order_id;
      end if;
      if v_order_status<>'CONFIRMED' then
        raise exception 'Customer payments may be recorded only against CONFIRMED sales orders';
      end if;
      if new.customer_id<>v_order_customer then
        raise exception 'Customer payment customer_id must match its linked sales order';
      end if;

      select coalesce(sum(cp.amount),0::numeric)
      into v_existing_paid
      from public.customer_payments cp
      where cp.sales_order_id=new.sales_order_id
        and cp.status='POSTED';

      if v_existing_paid+new.amount>v_order_total then
        raise exception 'Customer payment exceeds outstanding sales-order amount';
      end if;
    end if;
    return new;
  end if;

  if new.id is distinct from old.id
     or new.customer_id is distinct from old.customer_id
     or new.sales_order_id is distinct from old.sales_order_id
     or new.amount is distinct from old.amount
     or new.payment_date is distinct from old.payment_date
     or new.payment_method is distinct from old.payment_method
     or new.reference is distinct from old.reference
     or new.created_by_user_id is distinct from old.created_by_user_id
     or new.created_at is distinct from old.created_at then
    raise exception 'Posted customer payment financial fields are immutable';
  end if;

  if old.status='POSTED' and new.status='VOIDED' then
    if new.voided_at is null then
      raise exception 'Voided customer payment requires voided_at';
    end if;
    if v_actor is not null and new.voided_by_user_id is distinct from v_actor then
      raise exception 'Customer payment void actor must match authenticated user';
    end if;
    return new;
  end if;

  if new.status is distinct from old.status
     or new.voided_at is distinct from old.voided_at
     or new.voided_by_user_id is distinct from old.voided_by_user_id then
    raise exception 'Invalid customer payment lifecycle transition';
  end if;

  return new;
end;
$$;
revoke all on function private.guard_customer_payment_workflow() from public,anon,authenticated;

drop trigger if exists customer_payments_guard_workflow on public.customer_payments;
create trigger customer_payments_guard_workflow
before insert or update on public.customer_payments
for each row execute function private.guard_customer_payment_workflow();

create or replace function private.refresh_sales_order_payment_status(p_sales_order_id uuid)
returns void
language plpgsql
security definer
set search_path=pg_catalog,pg_temp
as $$
declare
  v_total numeric;
  v_paid numeric;
  v_current text;
  v_target text;
begin
  if p_sales_order_id is null then return; end if;

  select sot.total_amount,so.payment_status
  into v_total,v_current
  from public.sales_orders so
  join public.sales_order_totals sot on sot.sales_order_id=so.id
  where so.id=p_sales_order_id;

  if not found then return; end if;

  select coalesce(sum(cp.amount),0::numeric)
  into v_paid
  from public.customer_payments cp
  where cp.sales_order_id=p_sales_order_id
    and cp.status='POSTED';

  if v_total<=0 or v_paid>=v_total then
    v_target:='PAID';
  elsif v_current='RECEIVABLE' then
    v_target:='RECEIVABLE';
  elsif v_paid>0 then
    v_target:='PARTIALLY_PAID';
  else
    v_target:='UNPAID';
  end if;

  if v_target is distinct from v_current then
    update public.sales_orders
    set payment_status=v_target
    where id=p_sales_order_id;
  end if;
end;
$$;
revoke all on function private.refresh_sales_order_payment_status(uuid) from public,anon,authenticated;

create or replace function private.sync_sales_order_payment_status_from_payments()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,pg_temp
as $$
begin
  perform private.refresh_sales_order_payment_status(coalesce(new.sales_order_id,old.sales_order_id));
  return coalesce(new,old);
end;
$$;
revoke all on function private.sync_sales_order_payment_status_from_payments() from public,anon,authenticated;

drop trigger if exists customer_payments_sync_sales_order_status on public.customer_payments;
create trigger customer_payments_sync_sales_order_status
after insert or update of status on public.customer_payments
for each row execute function private.sync_sales_order_payment_status_from_payments();

create or replace function public.record_customer_payment(
  p_sales_order_id uuid,
  p_amount numeric,
  p_payment_date date,
  p_payment_method text,
  p_reference text default null,
  p_note text default null
)
returns uuid
language plpgsql
security invoker
set search_path=public,pg_temp
as $$
declare
  v_user_id uuid:=auth.uid();
  v_customer_id uuid;
  v_order_status text;
  v_id uuid;
begin
  if v_user_id is null or not (
    public.current_user_has_role('OWNER_ADMIN')
    or public.current_user_has_role('ACCOUNTING')
  ) then
    raise exception 'Customer payment recording requires OWNER_ADMIN or ACCOUNTING role'
      using errcode='42501';
  end if;

  if p_amount is null or p_amount<=0 then
    raise exception 'Customer payment amount must be positive';
  end if;
  if p_payment_date is null then
    raise exception 'Customer payment date is required';
  end if;
  if length(btrim(coalesce(p_payment_method,'')))=0 then
    raise exception 'Customer payment method is required';
  end if;

  select so.customer_id,so.order_status
  into v_customer_id,v_order_status
  from public.sales_orders so
  where so.id=p_sales_order_id
  for update;

  if not found then raise exception 'Sales order % does not exist',p_sales_order_id; end if;
  if v_order_status<>'CONFIRMED' then
    raise exception 'Customer payments may be recorded only against CONFIRMED sales orders';
  end if;

  insert into public.customer_payments(
    customer_id,sales_order_id,amount,payment_date,payment_method,status,
    reference,note,created_by_user_id
  )
  values(
    v_customer_id,p_sales_order_id,p_amount,p_payment_date,btrim(p_payment_method),'POSTED',
    nullif(btrim(coalesce(p_reference,'')),''),
    nullif(btrim(coalesce(p_note,'')),''),
    v_user_id
  )
  returning id into v_id;

  return v_id;
end;
$$;
revoke all on function public.record_customer_payment(uuid,numeric,date,text,text,text) from public,anon;
grant execute on function public.record_customer_payment(uuid,numeric,date,text,text,text)
to authenticated,service_role;

create or replace function public.void_customer_payment(p_customer_payment_id uuid)
returns uuid
language plpgsql
security invoker
set search_path=public,pg_temp
as $$
declare
  v_user_id uuid:=auth.uid();
  v_status text;
begin
  if v_user_id is null or not (
    public.current_user_has_role('OWNER_ADMIN')
    or public.current_user_has_role('ACCOUNTING')
  ) then
    raise exception 'Customer payment void requires OWNER_ADMIN or ACCOUNTING role'
      using errcode='42501';
  end if;

  select cp.status into v_status
  from public.customer_payments cp
  where cp.id=p_customer_payment_id
  for update;

  if not found then raise exception 'Customer payment % does not exist',p_customer_payment_id; end if;
  if v_status<>'POSTED' then raise exception 'Only POSTED customer payments may be voided'; end if;

  update public.customer_payments
  set status='VOIDED',
      voided_by_user_id=v_user_id,
      voided_at=timezone('utc',now())
  where id=p_customer_payment_id;

  return p_customer_payment_id;
end;
$$;
revoke all on function public.void_customer_payment(uuid) from public,anon;
grant execute on function public.void_customer_payment(uuid) to authenticated,service_role;

create or replace function public.create_customer_payment_evidence_attachment(
  p_customer_payment_id uuid,
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
  v_user_id uuid:=auth.uid();
  v_attachment_id uuid;
  v_expected_prefix text:='customer-payments/'||p_customer_payment_id::text||'/';
begin
  if v_user_id is null or not (
    public.current_user_has_role('OWNER_ADMIN')
    or public.current_user_has_role('ACCOUNTING')
  ) then
    raise exception 'Customer payment evidence requires OWNER_ADMIN or ACCOUNTING role'
      using errcode='42501';
  end if;

  if not exists(select 1 from public.customer_payments where id=p_customer_payment_id) then
    raise exception 'Customer payment % does not exist or is not visible',p_customer_payment_id;
  end if;

  if p_storage_path is null
     or left(p_storage_path,length(v_expected_prefix))<>v_expected_prefix
     or length(btrim(coalesce(p_original_file_name,'')))=0 then
    raise exception 'Invalid customer payment evidence path or file name';
  end if;
  if p_size_bytes is not null and p_size_bytes<0 then
    raise exception 'Evidence size cannot be negative';
  end if;

  insert into public.attachments(
    linked_entity_type,linked_entity_id,attachment_kind,storage_bucket,storage_path,
    original_file_name,media_type,size_bytes,metadata,uploaded_by_user_id
  )
  values(
    'CUSTOMER_PAYMENT',p_customer_payment_id,'PAYMENT_EVIDENCE','ops-attachments',p_storage_path,
    p_original_file_name,nullif(btrim(coalesce(p_media_type,'')),''),
    p_size_bytes,jsonb_build_object('purpose','CUSTOMER_PAYMENT'),v_user_id
  )
  returning id into v_attachment_id;

  return v_attachment_id;
end;
$$;
revoke all on function public.create_customer_payment_evidence_attachment(uuid,text,text,text,bigint) from public,anon;
grant execute on function public.create_customer_payment_evidence_attachment(uuid,text,text,text,bigint)
to authenticated,service_role;

commit;
