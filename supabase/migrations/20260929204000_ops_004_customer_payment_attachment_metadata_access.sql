-- OPS-004 bounded unit: customer-payment attachment metadata access
-- Architecture Generation 1
-- Source of Truth: SOURCE_OF_TRUTH.md
--
-- Scope is intentionally limited to attachment metadata linked to CUSTOMER_PAYMENT.
-- Supabase Storage object access remains a later bounded unit in OPS-004.
--
-- Least-privilege intent:
-- - OWNER_ADMIN keeps the unrestricted attachment metadata policies from the
--   attachment foundation migration.
-- - ACCOUNTING may read only PAYMENT_EVIDENCE metadata linked to customer
--   payments that are visible through customer-finance RBAC.
-- - ACCOUNTING may add only self-attributed PAYMENT_EVIDENCE metadata in the
--   private ops-attachments bucket.
-- - SALES, WAREHOUSE, and PRINTER_PRODUCTION gain no payment-evidence access.
-- - No authenticated UPDATE/DELETE access is added.

begin;

drop policy if exists attachments_select_customer_payment_accounting
on public.attachments;

create policy attachments_select_customer_payment_accounting
on public.attachments
for select
to authenticated
using (
  (select public.current_user_has_role('ACCOUNTING'))
  and linked_entity_type = 'CUSTOMER_PAYMENT'
  and attachment_kind = 'PAYMENT_EVIDENCE'
  and storage_bucket = 'ops-attachments'
  and exists (
    select 1
    from public.customer_payments cp
    where cp.id = attachments.linked_entity_id
  )
);

drop policy if exists attachments_insert_customer_payment_accounting_evidence
on public.attachments;

create policy attachments_insert_customer_payment_accounting_evidence
on public.attachments
for insert
to authenticated
with check (
  (select public.current_user_has_role('ACCOUNTING'))
  and linked_entity_type = 'CUSTOMER_PAYMENT'
  and attachment_kind = 'PAYMENT_EVIDENCE'
  and storage_bucket = 'ops-attachments'
  and uploaded_by_user_id = (select auth.uid())
  and exists (
    select 1
    from public.customer_payments cp
    where cp.id = attachments.linked_entity_id
  )
);

commit;
