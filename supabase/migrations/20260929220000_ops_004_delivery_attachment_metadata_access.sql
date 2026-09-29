-- OPS-004 bounded unit: delivery attachment metadata access
-- Architecture Generation 1
-- Source of Truth: SOURCE_OF_TRUTH.md
--
-- Scope is intentionally limited to DELIVERY_EVIDENCE attachment metadata
-- linked to DELIVERY. Supabase Storage object access remains a later bounded
-- unit within OPS-004.
--
-- Least-privilege intent:
-- - OWNER_ADMIN keeps the unrestricted attachment metadata policies from the
--   attachment foundation migration.
-- - WAREHOUSE and SALES may read DELIVERY_EVIDENCE metadata only for existing
--   deliveries visible through delivery RBAC.
-- - WAREHOUSE may add only self-attributed DELIVERY_EVIDENCE metadata in the
--   private ops-attachments bucket for an existing delivery.
-- - SALES remains read-only for delivery attachment metadata.
-- - ACCOUNTING and PRINTER_PRODUCTION gain no delivery attachment access.
-- - No authenticated UPDATE/DELETE access is added.

begin;

drop policy if exists attachments_select_delivery_operational_roles
on public.attachments;

create policy attachments_select_delivery_operational_roles
on public.attachments
for select
to authenticated
using (
  (
    (select public.current_user_has_role('WAREHOUSE'))
    or (select public.current_user_has_role('SALES'))
  )
  and linked_entity_type = 'DELIVERY'
  and attachment_kind = 'DELIVERY_EVIDENCE'
  and storage_bucket = 'ops-attachments'
  and exists (
    select 1
    from public.deliveries d
    where d.id = attachments.linked_entity_id
  )
);

drop policy if exists attachments_insert_delivery_warehouse_evidence
on public.attachments;

create policy attachments_insert_delivery_warehouse_evidence
on public.attachments
for insert
to authenticated
with check (
  (select public.current_user_has_role('WAREHOUSE'))
  and linked_entity_type = 'DELIVERY'
  and attachment_kind = 'DELIVERY_EVIDENCE'
  and storage_bucket = 'ops-attachments'
  and uploaded_by_user_id = (select auth.uid())
  and exists (
    select 1
    from public.deliveries d
    where d.id = attachments.linked_entity_id
  )
);

commit;
