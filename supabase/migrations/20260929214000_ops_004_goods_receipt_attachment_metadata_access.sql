-- OPS-004 bounded unit: goods-receipt attachment metadata access
-- Architecture Generation 1
-- Source of Truth: SOURCE_OF_TRUTH.md
--
-- Scope is intentionally limited to DOCUMENT attachment metadata linked to
-- GOODS_RECEIPT. Supabase Storage object access remains a later bounded unit
-- within OPS-004.
--
-- Least-privilege intent:
-- - OWNER_ADMIN keeps the unrestricted attachment metadata policies from the
--   attachment foundation migration.
-- - WAREHOUSE and ACCOUNTING may read DOCUMENT metadata only for existing
--   goods receipts visible through purchasing/warehouse RBAC.
-- - WAREHOUSE may add only self-attributed DOCUMENT metadata in the private
--   ops-attachments bucket for an existing goods receipt.
-- - ACCOUNTING remains read-only for goods-receipt attachment metadata.
-- - SALES and PRINTER_PRODUCTION gain no goods-receipt attachment access.
-- - No authenticated UPDATE/DELETE access is added.

begin;

drop policy if exists attachments_select_goods_receipt_operational_roles
on public.attachments;

create policy attachments_select_goods_receipt_operational_roles
on public.attachments
for select
to authenticated
using (
  (
    (select public.current_user_has_role('WAREHOUSE'))
    or (select public.current_user_has_role('ACCOUNTING'))
  )
  and linked_entity_type = 'GOODS_RECEIPT'
  and attachment_kind = 'DOCUMENT'
  and storage_bucket = 'ops-attachments'
  and exists (
    select 1
    from public.goods_receipts gr
    where gr.id = attachments.linked_entity_id
  )
);

drop policy if exists attachments_insert_goods_receipt_warehouse_document
on public.attachments;

create policy attachments_insert_goods_receipt_warehouse_document
on public.attachments
for insert
to authenticated
with check (
  (select public.current_user_has_role('WAREHOUSE'))
  and linked_entity_type = 'GOODS_RECEIPT'
  and attachment_kind = 'DOCUMENT'
  and storage_bucket = 'ops-attachments'
  and uploaded_by_user_id = (select auth.uid())
  and exists (
    select 1
    from public.goods_receipts gr
    where gr.id = attachments.linked_entity_id
  )
);

commit;
