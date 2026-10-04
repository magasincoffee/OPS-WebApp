-- OPS-004 bounded unit: sales-order-item artwork attachment metadata access
-- Architecture Generation 1
-- Source of Truth: SOURCE_OF_TRUTH.md
--
-- Scope is intentionally limited to ARTWORK attachment metadata linked to
-- SALES_ORDER_ITEM. Supabase Storage object access remains a later bounded unit
-- within OPS-004.
--
-- Least-privilege intent:
-- - OWNER_ADMIN keeps the unrestricted attachment metadata policies from the
--   attachment foundation migration.
-- - SALES may read ARTWORK metadata for sales-order items visible through the
--   existing sales RBAC policy.
-- - SALES may add only self-attributed ARTWORK metadata in the private
--   ops-attachments bucket for an existing sales-order item.
-- - ACCOUNTING, WAREHOUSE, and PRINTER_PRODUCTION gain no direct sales-order
--   artwork metadata access in this bounded unit.
-- - No authenticated UPDATE/DELETE access is added.

begin;

drop policy if exists attachments_select_sales_order_item_sales
on public.attachments;

create policy attachments_select_sales_order_item_sales
on public.attachments
for select
to authenticated
using (
  (select public.current_user_has_role('SALES'))
  and linked_entity_type = 'SALES_ORDER_ITEM'
  and attachment_kind = 'ARTWORK'
  and storage_bucket = 'ops-attachments'
  and exists (
    select 1
    from public.sales_order_items soi
    where soi.id = attachments.linked_entity_id
  )
);

drop policy if exists attachments_insert_sales_order_item_sales_artwork
on public.attachments;

create policy attachments_insert_sales_order_item_sales_artwork
on public.attachments
for insert
to authenticated
with check (
  (select public.current_user_has_role('SALES'))
  and linked_entity_type = 'SALES_ORDER_ITEM'
  and attachment_kind = 'ARTWORK'
  and storage_bucket = 'ops-attachments'
  and uploaded_by_user_id = (select auth.uid())
  and exists (
    select 1
    from public.sales_order_items soi
    where soi.id = attachments.linked_entity_id
  )
);

commit;
