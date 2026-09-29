-- OPS-002 bounded unit: customer payments and receivables database foundation
-- Architecture Generation 1
-- Source of Truth: SOURCE_OF_TRUTH.md
--
-- Scope is limited to customer payments, customer-ledger entries, receivable
-- derivation, and source-integrity guards. Payment workflow/UI, auth/RBAC,
-- attachments, audit logging, and operational accounting remain in later OPS tasks.

begin;

create table public.customer_payments (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers(id) on delete restrict,
  sales_order_id uuid references public.sales_orders(id) on delete restrict,
  amount numeric(18,6) not null,
  payment_date date not null default current_date,
  payment_method text not null,
  status text not null default 'POSTED',
  reference text,
  note text,
  evidence_reference text,
  created_by_user_id uuid,
  voided_by_user_id uuid,
  voided_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint customer_payments_amount_positive
    check (amount > 0),
  constraint customer_payments_method_not_blank
    check (length(btrim(payment_method)) > 0),
  constraint customer_payments_status_valid
    check (status in ('POSTED', 'VOIDED')),
  constraint customer_payments_void_state_valid
    check (
      (status = 'POSTED' and voided_at is null and voided_by_user_id is null)
      or
      (status = 'VOIDED' and voided_at is not null)
    )
);

create table public.customer_ledger_entries (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers(id) on delete restrict,
  sales_order_id uuid references public.sales_orders(id) on delete restrict,
  customer_payment_id uuid references public.customer_payments(id) on delete restrict,
  entry_type text not null,
  amount numeric(18,6) not null,
  occurred_at timestamptz not null default timezone('utc', now()),
  created_by_user_id uuid,
  note text,
  created_at timestamptz not null default timezone('utc', now()),
  constraint customer_ledger_entries_type_valid
    check (entry_type in ('ORDER_DEBIT', 'PAYMENT_CREDIT')),
  constraint customer_ledger_entries_amount_positive
    check (amount > 0),
  constraint customer_ledger_entries_source_valid
    check (
      (
        entry_type = 'ORDER_DEBIT'
        and sales_order_id is not null
        and customer_payment_id is null
      )
      or
      (
        entry_type = 'PAYMENT_CREDIT'
        and sales_order_id is null
        and customer_payment_id is not null
      )
    )
);

create unique index customer_ledger_one_order_debit
  on public.customer_ledger_entries(sales_order_id)
  where entry_type = 'ORDER_DEBIT';

create unique index customer_ledger_one_payment_credit
  on public.customer_ledger_entries(customer_payment_id)
  where entry_type = 'PAYMENT_CREDIT';

create or replace function public.validate_customer_payment_source()
returns trigger
language plpgsql
as $$
declare
  source_customer_id uuid;
begin
  if new.sales_order_id is null then
    return new;
  end if;

  select so.customer_id
  into source_customer_id
  from public.sales_orders so
  where so.id = new.sales_order_id;

  if source_customer_id is null then
    raise exception
      'Customer payment source sales order % does not exist',
      new.sales_order_id;
  end if;

  if new.customer_id <> source_customer_id then
    raise exception
      'Customer payment customer_id must match its linked sales order';
  end if;

  return new;
end;
$$;

create trigger customer_payments_validate_source
before insert or update of customer_id, sales_order_id
on public.customer_payments
for each row execute function public.validate_customer_payment_source();

create or replace function public.validate_customer_ledger_source()
returns trigger
language plpgsql
as $$
declare
  source_customer_id uuid;
begin
  if new.entry_type = 'ORDER_DEBIT' then
    select so.customer_id
    into source_customer_id
    from public.sales_orders so
    where so.id = new.sales_order_id;

    if source_customer_id is null then
      raise exception
        'Customer ledger source sales order % does not exist',
        new.sales_order_id;
    end if;
  elsif new.entry_type = 'PAYMENT_CREDIT' then
    select cp.customer_id
    into source_customer_id
    from public.customer_payments cp
    where cp.id = new.customer_payment_id;

    if source_customer_id is null then
      raise exception
        'Customer ledger source payment % does not exist',
        new.customer_payment_id;
    end if;
  end if;

  if new.customer_id <> source_customer_id then
    raise exception
      'Customer ledger customer_id must match its source record';
  end if;

  return new;
end;
$$;

create trigger customer_ledger_entries_validate_source
before insert on public.customer_ledger_entries
for each row execute function public.validate_customer_ledger_source();

create or replace function public.prevent_customer_ledger_entry_mutation()
returns trigger
language plpgsql
as $$
begin
  raise exception
    'Customer ledger entries are immutable; create a new source-backed entry instead';
end;
$$;

create trigger customer_ledger_entries_prevent_update
before update on public.customer_ledger_entries
for each row execute function public.prevent_customer_ledger_entry_mutation();

create trigger customer_ledger_entries_prevent_delete
before delete on public.customer_ledger_entries
for each row execute function public.prevent_customer_ledger_entry_mutation();

create view public.sales_order_receivables as
select
  so.id as sales_order_id,
  so.customer_id,
  sot.total_amount as order_total_amount,
  coalesce(
    sum(cp.amount) filter (where cp.status = 'POSTED'),
    0::numeric
  ) as valid_payment_amount,
  sot.total_amount
    - coalesce(
        sum(cp.amount) filter (where cp.status = 'POSTED'),
        0::numeric
      ) as receivable_amount,
  so.currency_code
from public.sales_orders so
join public.sales_order_totals sot
  on sot.sales_order_id = so.id
left join public.customer_payments cp
  on cp.sales_order_id = so.id
group by
  so.id,
  so.customer_id,
  sot.total_amount,
  so.currency_code;

create view public.customer_ledger_balances as
select
  c.id as customer_id,
  coalesce(
    sum(
      case
        when cle.entry_type = 'ORDER_DEBIT'
          then cle.amount
        when cle.entry_type = 'PAYMENT_CREDIT'
          and cp.status = 'POSTED'
          then -cle.amount
        else 0::numeric
      end
    ),
    0::numeric
  ) as balance_amount
from public.customers c
left join public.customer_ledger_entries cle
  on cle.customer_id = c.id
left join public.customer_payments cp
  on cp.id = cle.customer_payment_id
group by c.id;

create index customer_payments_customer_id_idx
  on public.customer_payments(customer_id);

create index customer_payments_sales_order_id_idx
  on public.customer_payments(sales_order_id);

create index customer_payments_payment_date_idx
  on public.customer_payments(payment_date);

create index customer_payments_status_idx
  on public.customer_payments(status);

create index customer_ledger_entries_customer_occurred_at_idx
  on public.customer_ledger_entries(customer_id, occurred_at);

create trigger customer_payments_set_updated_at
before update on public.customer_payments
for each row execute function public.set_updated_at();

commit;
