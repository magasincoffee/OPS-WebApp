-- OPS-003 bounded unit: customer-finance RBAC policies
-- Architecture Generation 1
-- Source of Truth: SOURCE_OF_TRUTH.md
--
-- Scope is intentionally limited to customer payments, customer-ledger entries,
-- and a sanitized receivable follow-up projection for SALES.
-- Delivery, operational-task authorization and representative permission
-- verification remain later bounded units inside OPS-003.
--
-- Policy intent derived from SOT Section 5:
-- - OWNER_ADMIN and ACCOUNTING may read/record/update customer payments.
-- - OWNER_ADMIN and ACCOUNTING may read/append immutable customer-ledger entries.
-- - SALES receives receivable visibility for follow-up without direct access to
--   payment records or ledger entries.
-- - WAREHOUSE and PRINTER_PRODUCTION receive no customer-finance access.

begin;

revoke all on
  public.customer_payments,
  public.customer_ledger_entries
from anon;

revoke all on
  public.customer_payments,
  public.customer_ledger_entries
from authenticated;

grant select, insert, update on public.customer_payments to authenticated;
grant select, insert on public.customer_ledger_entries to authenticated;

grant all on
  public.customer_payments,
  public.customer_ledger_entries
to service_role;

create policy customer_payments_select_finance_roles
on public.customer_payments
for select
to authenticated
using (
  public.current_user_has_role('OWNER_ADMIN')
  or public.current_user_has_role('ACCOUNTING')
);

create policy customer_payments_insert_finance_roles
on public.customer_payments
for insert
to authenticated
with check (
  public.current_user_has_role('OWNER_ADMIN')
  or public.current_user_has_role('ACCOUNTING')
);

create policy customer_payments_update_finance_roles
on public.customer_payments
for update
to authenticated
using (
  public.current_user_has_role('OWNER_ADMIN')
  or public.current_user_has_role('ACCOUNTING')
)
with check (
  public.current_user_has_role('OWNER_ADMIN')
  or public.current_user_has_role('ACCOUNTING')
);

-- No DELETE grant/policy is provided for customer_payments. The schema already
-- models invalidation through status='VOIDED', preserving payment traceability.

create policy customer_ledger_entries_select_finance_roles
on public.customer_ledger_entries
for select
to authenticated
using (
  public.current_user_has_role('OWNER_ADMIN')
  or public.current_user_has_role('ACCOUNTING')
);

create policy customer_ledger_entries_insert_finance_roles
on public.customer_ledger_entries
for insert
to authenticated
with check (
  public.current_user_has_role('OWNER_ADMIN')
  or public.current_user_has_role('ACCOUNTING')
);

-- Ledger rows remain append-only. Existing database triggers reject UPDATE/DELETE,
-- and no authenticated UPDATE/DELETE privilege is granted here.

create or replace view public.sales_receivable_followup
with (security_barrier = true)
as
select
  so.id as sales_order_id,
  so.order_number,
  so.customer_id,
  c.display_name as customer_name,
  so.salesperson_user_id,
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
  so.currency_code,
  so.payment_status,
  so.order_status,
  so.order_date,
  so.requested_due_date
from public.sales_orders so
join public.sales_order_totals sot
  on sot.sales_order_id = so.id
join public.customers c
  on c.id = so.customer_id
left join public.customer_payments cp
  on cp.sales_order_id = so.id
where
  auth.role() = 'service_role'
  or public.current_user_has_role('OWNER_ADMIN')
  or public.current_user_has_role('ACCOUNTING')
  or public.current_user_has_role('SALES')
group by
  so.id,
  so.order_number,
  so.customer_id,
  c.display_name,
  so.salesperson_user_id,
  sot.total_amount,
  so.currency_code,
  so.payment_status,
  so.order_status,
  so.order_date,
  so.requested_due_date;

alter view public.sales_receivable_followup set (security_invoker = false);

revoke all on public.sales_receivable_followup from public, anon;
grant select on public.sales_receivable_followup to authenticated;
grant all on public.sales_receivable_followup to service_role;

commit;
