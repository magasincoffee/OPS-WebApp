-- OPS-004 bounded unit: supplier attachment metadata access
-- Architecture Generation 1
-- Source of Truth: SOURCE_OF_TRUTH.md
--
-- Scope is intentionally limited to GENERAL/DOCUMENT attachment metadata
-- linked to SUPPLIER. Supabase Storage object access remains a later bounded
-- unit within OPS-004.
--
-- Least-privilege intent:
-- - OWNER_ADMIN keeps the unrestricted attachment metadata policies from the
--   attachment foundation migration.
-- - ACCOUNTING and WAREHOUSE may read GENERAL/DOCUMENT metadata only for
--   existing suppliers visible through supplier RBAC.
-- - Supplier mutation remains OWNER_ADMIN-only, so no business-role attachment
--   metadata INSERT policy is added in this bounded unit.
-- - SALES and PRINTER_PRODUCTION gain no supplier attachment access.
-- - No authenticated UPDATE/DELETE access is added.

begin;

drop policy if exists attachments_select_supplier_operational_roles
on public.attachments;

create policy attachments_select_supplier_operational_roles
on public.attachments
for select
to authenticated
using (
  (
    (select public.current_user_has_role('ACCOUNTING'))
    or (select public.current_user_has_role('WAREHOUSE'))
  )
  and linked_entity_type = 'SUPPLIER'
  and attachment_kind in ('GENERAL', 'DOCUMENT')
  and storage_bucket = 'ops-attachments'
  and exists (
    select 1
    from public.suppliers s
    where s.id = attachments.linked_entity_id
  )
);

commit;
