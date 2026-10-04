-- OPS-004 bounded unit: purchase-order attachment metadata access
-- Architecture Generation 1
-- Source of Truth: SOURCE_OF_TRUTH.md
--
-- Scope is intentionally limited to attachment metadata linked to PURCHASE_ORDER.
-- Supabase Storage object access remains a later bounded unit within OPS-004.
--
-- Least-privilege intent:
-- - OWNER_ADMIN keeps the unrestricted attachment metadata policies from the
--   attachment foundation migration, including controlled metadata creation.
-- - ACCOUNTING may read only DOCUMENT and PAYMENT_EVIDENCE metadata linked to
--   purchase orders already visible through purchasing RBAC.
-- - ACCOUNTING receives no attachment metadata INSERT/UPDATE/DELETE capability
--   in this bounded unit because purchase-order mutation remains OWNER_ADMIN-only.
-- - SALES, WAREHOUSE, and PRINTER_PRODUCTION gain no purchase-order attachment
--   metadata access.

begin;

drop policy if exists attachments_select_purchase_order_accounting
on public.attachments;

create policy attachments_select_purchase_order_accounting
on public.attachments
for select
to authenticated
using (
  (select public.current_user_has_role('ACCOUNTING'))
  and linked_entity_type = 'PURCHASE_ORDER'
  and attachment_kind in ('DOCUMENT', 'PAYMENT_EVIDENCE')
  and storage_bucket = 'ops-attachments'
  and exists (
    select 1
    from public.purchase_orders po
    where po.id = attachments.linked_entity_id
  )
);

commit;
