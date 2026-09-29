-- OPS-004 bounded unit: print-job attachment metadata access
-- Architecture Generation 1
-- Source of Truth: SOURCE_OF_TRUTH.md
--
-- Scope is intentionally limited to attachment metadata linked to PRINT_JOB.
-- Supabase Storage bucket/object policies remain a later bounded unit in OPS-004.
--
-- Least-privilege intent:
-- - OWNER_ADMIN keeps the unrestricted attachment metadata policies from the
--   attachment foundation migration.
-- - PRINTER_PRODUCTION may read only ARTWORK and PRODUCTION_EVIDENCE attached
--   to print jobs assigned to the current authenticated user.
-- - PRINTER_PRODUCTION may add only PRODUCTION_EVIDENCE for assigned jobs and
--   must attribute the upload metadata to auth.uid().
-- - Production users do not gain visibility into payment/document evidence or
--   attachments belonging to unassigned print jobs.

begin;

drop policy if exists attachments_select_assigned_print_production
on public.attachments;

create policy attachments_select_assigned_print_production
on public.attachments
for select
to authenticated
using (
  public.current_user_has_role('PRINTER_PRODUCTION')
  and linked_entity_type = 'PRINT_JOB'
  and attachment_kind in ('ARTWORK', 'PRODUCTION_EVIDENCE')
  and exists (
    select 1
    from public.print_jobs pj
    where pj.id = attachments.linked_entity_id
      and pj.assignee_user_id = auth.uid()
  )
);

drop policy if exists attachments_insert_assigned_print_production_evidence
on public.attachments;

create policy attachments_insert_assigned_print_production_evidence
on public.attachments
for insert
to authenticated
with check (
  public.current_user_has_role('PRINTER_PRODUCTION')
  and linked_entity_type = 'PRINT_JOB'
  and attachment_kind = 'PRODUCTION_EVIDENCE'
  and uploaded_by_user_id = auth.uid()
  and exists (
    select 1
    from public.print_jobs pj
    where pj.id = attachments.linked_entity_id
      and pj.assignee_user_id = auth.uid()
  )
);

commit;
