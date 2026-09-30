-- OPS-010: customer-module activity-history visibility
-- Architecture Generation 1
-- Source of Truth: SOURCE_OF_TRUTH.md
--
-- Customer profile activity history is required by SOT Section 4.2.
-- OWNER_ADMIN already has global audit-log visibility from OPS-004.
-- This policy gives SALES and ACCOUNTING read-only access only to CUSTOMER
-- activity rows for customer records they can already read.
-- It does not grant access to other audit entities or any audit mutation.

begin;

drop policy if exists activity_logs_select_customer_business_roles
on public.activity_logs;

create policy activity_logs_select_customer_business_roles
on public.activity_logs
for select
to authenticated
using (
  linked_entity_type = 'CUSTOMER'
  and (
    (select public.current_user_has_role('SALES'))
    or (select public.current_user_has_role('ACCOUNTING'))
  )
  and exists (
    select 1
    from public.customers c
    where c.id = activity_logs.linked_entity_id
  )
);

commit;
