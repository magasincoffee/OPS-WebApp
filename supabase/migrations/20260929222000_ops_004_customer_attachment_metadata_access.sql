-- OPS-004 bounded unit: customer attachment metadata access
-- Architecture Generation 1
-- Source of Truth: SOURCE_OF_TRUTH.md
--
-- Scope is intentionally limited to GENERAL/DOCUMENT attachment metadata
-- linked to CUSTOMER. Supabase Storage object access remains a later bounded
-- unit within OPS-004.
--
-- Least-privilege intent:
-- - OWNER_ADMIN keeps the unrestricted attachment metadata policies from the
--   attachment foundation migration.
-- - SALES and ACCOUNTING may read GENERAL/DOCUMENT metadata only for existing
--   customers visible through customer RBAC.
-- - SALES may add only self-attributed GENERAL/DOCUMENT metadata in the
--   private ops-attachments bucket for an existing customer.
-- - ACCOUNTING remains read-only for customer attachment metadata.
-- - WAREHOUSE and PRINTER_PRODUCTION gain no customer attachment access.
-- - No authenticated UPDATE/DELETE access is added.

begin;

drop policy if exists attachments_select_customer_business_roles
on public.attachments;

create policy attachments_select_customer_business_roles
on public.attachments
for select
to authenticated
using (
  (
    (select public.current_user_has_role('SALES'))
    or (select public.current_user_has_role('ACCOUNTING'))
  )
  and linked_entity_type = 'CUSTOMER'
  and attachment_kind in ('GENERAL', 'DOCUMENT')
  and storage_bucket = 'ops-attachments'
  and exists (
    select 1
    from public.customers c
    where c.id = attachments.linked_entity_id
  )
);

drop policy if exists attachments_insert_customer_sales_documents
on public.attachments;

create policy attachments_insert_customer_sales_documents
on public.attachments
for insert
to authenticated
with check (
  (select public.current_user_has_role('SALES'))
  and linked_entity_type = 'CUSTOMER'
  and attachment_kind in ('GENERAL', 'DOCUMENT')
  and storage_bucket = 'ops-attachments'
  and uploaded_by_user_id = (select auth.uid())
  and exists (
    select 1
    from public.customers c
    where c.id = attachments.linked_entity_id
  )
);

commit;
