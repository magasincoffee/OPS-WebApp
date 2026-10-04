-- OPS-074: production schema-drift repair for receivable helper
-- Architecture Generation 2
-- Source of Truth: SOURCE_OF_TRUTH.md
begin;

create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated;

create or replace function private.valid_customer_payment_total(p_sales_order_id uuid)
returns numeric
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_total numeric;
begin
  if not (
    public.current_user_has_role('OWNER_ADMIN')
    or public.current_user_has_role('ACCOUNTING')
    or public.current_user_has_role('SALES')
  ) then
    return null;
  end if;

  select coalesce(
    sum(cp.amount) filter (where cp.status = 'POSTED'),
    0::numeric
  )
  into v_total
  from public.customer_payments cp
  where cp.sales_order_id = p_sales_order_id;

  return v_total;
end;
$$;

revoke all on function private.valid_customer_payment_total(uuid)
from public, anon;

grant execute on function private.valid_customer_payment_total(uuid)
to authenticated;

commit;
