-- OPS-051: customer ledger and receivables
-- Architecture Generation 1
-- Source of Truth: SOURCE_OF_TRUTH.md
begin;

create or replace function private.guard_customer_ledger_entry_source()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,pg_temp
as $$
declare
  v_actor uuid:=auth.uid();
  v_customer_id uuid;
  v_source_amount numeric;
  v_source_status text;
begin
  if new.entry_type='ORDER_DEBIT' then
    select so.customer_id,sot.total_amount,so.order_status
    into v_customer_id,v_source_amount,v_source_status
    from public.sales_orders so
    join public.sales_order_totals sot on sot.sales_order_id=so.id
    where so.id=new.sales_order_id;

    if not found then
      raise exception 'Customer ledger source sales order % does not exist',new.sales_order_id;
    end if;
    if v_source_status='DRAFT' then
      raise exception 'Customer ledger ORDER_DEBIT requires a non-DRAFT sales order';
    end if;
  elsif new.entry_type='PAYMENT_CREDIT' then
    select cp.customer_id,cp.amount,cp.status
    into v_customer_id,v_source_amount,v_source_status
    from public.customer_payments cp
    where cp.id=new.customer_payment_id;

    if not found then
      raise exception 'Customer ledger source payment % does not exist',new.customer_payment_id;
    end if;
  else
    raise exception 'Unsupported customer ledger entry type %',new.entry_type;
  end if;

  if new.customer_id is distinct from v_customer_id then
    raise exception 'Customer ledger customer_id must match its source record';
  end if;
  if new.amount is distinct from v_source_amount then
    raise exception 'Customer ledger amount must match its authoritative source amount';
  end if;
  if v_actor is not null and new.created_by_user_id is distinct from v_actor then
    raise exception 'Customer ledger creator must match authenticated user';
  end if;

  return new;
end;
$$;
revoke all on function private.guard_customer_ledger_entry_source() from public,anon,authenticated;

drop trigger if exists customer_ledger_entries_guard_source on public.customer_ledger_entries;
create trigger customer_ledger_entries_guard_source
before insert on public.customer_ledger_entries
for each row execute function private.guard_customer_ledger_entry_source();

create or replace function private.append_sales_order_ledger_debit()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,pg_temp
as $$
declare
  v_total numeric;
begin
  if new.order_status='CONFIRMED' and old.order_status is distinct from new.order_status then
    select sot.total_amount into v_total
    from public.sales_order_totals sot
    where sot.sales_order_id=new.id;

    if coalesce(v_total,0)>0 then
      insert into public.customer_ledger_entries(
        customer_id,sales_order_id,entry_type,amount,occurred_at,created_by_user_id,note
      )
      values(
        new.customer_id,new.id,'ORDER_DEBIT',v_total,
        coalesce(new.confirmed_at,timezone('utc',now())),
        coalesce(auth.uid(),new.created_by_user_id),
        'Sales order confirmed debit'
      )
      on conflict do nothing;
    end if;
  end if;
  return new;
end;
$$;
revoke all on function private.append_sales_order_ledger_debit() from public,anon,authenticated;

drop trigger if exists sales_orders_append_customer_ledger_debit on public.sales_orders;
create trigger sales_orders_append_customer_ledger_debit
after update of order_status on public.sales_orders
for each row execute function private.append_sales_order_ledger_debit();

create or replace function private.append_customer_payment_ledger_credit()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,pg_temp
as $$
begin
  insert into public.customer_ledger_entries(
    customer_id,customer_payment_id,entry_type,amount,occurred_at,created_by_user_id,note
  )
  values(
    new.customer_id,new.id,'PAYMENT_CREDIT',new.amount,
    coalesce(new.payment_date::timestamp at time zone 'UTC',new.created_at),
    coalesce(auth.uid(),new.created_by_user_id),
    'Customer payment credit'
  )
  on conflict do nothing;
  return new;
end;
$$;
revoke all on function private.append_customer_payment_ledger_credit() from public,anon,authenticated;

drop trigger if exists customer_payments_append_customer_ledger_credit on public.customer_payments;
create trigger customer_payments_append_customer_ledger_credit
after insert on public.customer_payments
for each row execute function private.append_customer_payment_ledger_credit();

create or replace function private.refresh_sales_order_payment_status(p_sales_order_id uuid)
returns void
language plpgsql
security definer
set search_path=pg_catalog,pg_temp
as $$
declare
  v_total numeric;
  v_paid numeric;
  v_delivery_status text;
  v_current text;
  v_target text;
begin
  if p_sales_order_id is null then return; end if;

  select sot.total_amount,so.delivery_status,so.payment_status
  into v_total,v_delivery_status,v_current
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
  elsif v_delivery_status='COMPLETED' then
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

create or replace function private.sync_sales_order_payment_status_from_delivery()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,pg_temp
as $$
begin
  if new.delivery_status is distinct from old.delivery_status then
    perform private.refresh_sales_order_payment_status(new.id);
  end if;
  return new;
end;
$$;
revoke all on function private.sync_sales_order_payment_status_from_delivery() from public,anon,authenticated;

drop trigger if exists sales_orders_sync_payment_status_from_delivery on public.sales_orders;
create trigger sales_orders_sync_payment_status_from_delivery
after update of delivery_status on public.sales_orders
for each row execute function private.sync_sales_order_payment_status_from_delivery();

create or replace view public.sales_order_receivables
with (security_invoker=true)
as
select
  so.id as sales_order_id,
  so.customer_id,
  sot.total_amount as order_total_amount,
  coalesce(sum(cp.amount) filter (where cp.status='POSTED'),0::numeric) as valid_payment_amount,
  greatest(
    sot.total_amount-coalesce(sum(cp.amount) filter (where cp.status='POSTED'),0::numeric),
    0::numeric
  ) as receivable_amount,
  so.currency_code
from public.sales_orders so
join public.sales_order_totals sot on sot.sales_order_id=so.id
left join public.customer_payments cp on cp.sales_order_id=so.id
where so.order_status<>'CANCELLED'
group by so.id,so.customer_id,sot.total_amount,so.currency_code;

create or replace view public.sales_receivable_followup
with (security_barrier=true,security_invoker=true)
as
select
  so.id as sales_order_id,
  so.order_number,
  so.customer_id,
  c.display_name as customer_name,
  so.salesperson_user_id,
  sot.total_amount as order_total_amount,
  p.valid_payment_amount,
  greatest(sot.total_amount-p.valid_payment_amount,0::numeric) as receivable_amount,
  so.currency_code,
  so.payment_status,
  so.order_status,
  so.order_date,
  so.requested_due_date
from public.sales_orders so
join public.sales_order_totals sot on sot.sales_order_id=so.id
join public.customers c on c.id=so.customer_id
cross join lateral (
  select private.valid_customer_payment_total(so.id) as valid_payment_amount
) p
where so.order_status<>'CANCELLED';

alter view public.customer_ledger_balances set (security_invoker=true);
revoke all on public.customer_ledger_balances from public,anon,authenticated;
grant select on public.customer_ledger_balances to service_role;

create or replace view public.customer_ledger_balances_by_currency
with (security_invoker=true)
as
select
  cle.customer_id,
  c.display_name as customer_name,
  coalesce(order_so.currency_code,payment_so.currency_code) as currency_code,
  sum(
    case
      when cle.entry_type='ORDER_DEBIT' and order_so.order_status<>'CANCELLED' then cle.amount
      when cle.entry_type='PAYMENT_CREDIT' and cp.status='POSTED' then -cle.amount
      else 0::numeric
    end
  ) as balance_amount
from public.customer_ledger_entries cle
join public.customers c on c.id=cle.customer_id
left join public.sales_orders order_so on order_so.id=cle.sales_order_id
left join public.customer_payments cp on cp.id=cle.customer_payment_id
left join public.sales_orders payment_so on payment_so.id=cp.sales_order_id
where (
  public.current_user_has_role('OWNER_ADMIN')
  or public.current_user_has_role('ACCOUNTING')
)
and coalesce(order_so.currency_code,payment_so.currency_code) is not null
group by cle.customer_id,c.display_name,coalesce(order_so.currency_code,payment_so.currency_code);

revoke all on public.customer_ledger_balances_by_currency from public,anon;
grant select on public.customer_ledger_balances_by_currency to authenticated,service_role;

create or replace view public.customer_ledger_history
with (security_invoker=true)
as
select
  cle.id as entry_id,
  cle.customer_id,
  c.display_name as customer_name,
  cle.entry_type,
  cle.amount,
  case
    when cle.entry_type='ORDER_DEBIT' and order_so.order_status<>'CANCELLED' then cle.amount
    when cle.entry_type='PAYMENT_CREDIT' and cp.status='POSTED' then -cle.amount
    else 0::numeric
  end as effective_amount,
  coalesce(order_so.currency_code,payment_so.currency_code) as currency_code,
  cle.occurred_at,
  cle.created_by_user_id,
  cle.sales_order_id,
  order_so.order_number,
  cle.customer_payment_id,
  cp.reference as payment_reference,
  cp.status as payment_status,
  cle.note
from public.customer_ledger_entries cle
join public.customers c on c.id=cle.customer_id
left join public.sales_orders order_so on order_so.id=cle.sales_order_id
left join public.customer_payments cp on cp.id=cle.customer_payment_id
left join public.sales_orders payment_so on payment_so.id=cp.sales_order_id
where (
  public.current_user_has_role('OWNER_ADMIN')
  or public.current_user_has_role('ACCOUNTING')
);

revoke all on public.customer_ledger_history from public,anon;
grant select on public.customer_ledger_history to authenticated,service_role;

insert into public.customer_ledger_entries(
  customer_id,sales_order_id,entry_type,amount,occurred_at,created_by_user_id,note
)
select
  so.customer_id,so.id,'ORDER_DEBIT',sot.total_amount,
  coalesce(so.confirmed_at,so.created_at),
  so.created_by_user_id,
  'OPS-051 backfill: sales order debit'
from public.sales_orders so
join public.sales_order_totals sot on sot.sales_order_id=so.id
where so.order_status in ('CONFIRMED','COMPLETED')
  and sot.total_amount>0
on conflict do nothing;

insert into public.customer_ledger_entries(
  customer_id,customer_payment_id,entry_type,amount,occurred_at,created_by_user_id,note
)
select
  cp.customer_id,cp.id,'PAYMENT_CREDIT',cp.amount,
  coalesce(cp.payment_date::timestamp at time zone 'UTC',cp.created_at),
  cp.created_by_user_id,
  'OPS-051 backfill: customer payment credit'
from public.customer_payments cp
on conflict do nothing;

do $$
declare
  r record;
begin
  for r in
    select id
    from public.sales_orders
    where order_status in ('CONFIRMED','COMPLETED')
  loop
    perform private.refresh_sales_order_payment_status(r.id);
  end loop;
end;
$$;

commit;
