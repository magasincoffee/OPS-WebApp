-- OPS-004 bounded unit: print-job Supabase Storage object access
-- Architecture Generation 1
-- Source of Truth: SOURCE_OF_TRUTH.md
--
-- Scope is intentionally limited to binary objects linked to PRINT_JOB attachment
-- metadata. Other module attachment/storage access remains a later OPS-004 unit.
--
-- Security / workflow posture:
-- - ops-attachments is private; downloads remain subject to storage.objects RLS.
-- - Object access is metadata-first: an exact public.attachments row must already
--   authorize the bucket/path before the binary object can be read or uploaded.
-- - OWNER_ADMIN may read/upload binary objects only for PRINT_JOB attachments.
-- - Assigned PRINTER_PRODUCTION may read ARTWORK / PRODUCTION_EVIDENCE and may
--   upload only self-attributed PRODUCTION_EVIDENCE for its assigned print jobs.
-- - No authenticated UPDATE or DELETE policy is introduced, so direct upsert,
--   replacement, move, or delete remains unavailable in this bounded unit.
-- - service_role continues to bypass RLS for trusted backend orchestration.

begin;

insert into storage.buckets (id, name, public)
values ('ops-attachments', 'ops-attachments', false)
on conflict (id) do update
set public = false;

drop policy if exists ops_print_job_attachments_select
on storage.objects;

create policy ops_print_job_attachments_select
on storage.objects
for select
to authenticated
using (
  bucket_id = 'ops-attachments'
  and exists (
    select 1
    from public.attachments a
    where a.storage_bucket = storage.objects.bucket_id
      and a.storage_path = storage.objects.name
      and a.linked_entity_type = 'PRINT_JOB'
      and (
        public.current_user_has_role('OWNER_ADMIN')
        or (
          public.current_user_has_role('PRINTER_PRODUCTION')
          and a.attachment_kind in ('ARTWORK', 'PRODUCTION_EVIDENCE')
          and exists (
            select 1
            from public.print_jobs pj
            where pj.id = a.linked_entity_id
              and pj.assignee_user_id = (select auth.uid())
          )
        )
      )
  )
);

drop policy if exists ops_print_job_attachments_insert
on storage.objects;

create policy ops_print_job_attachments_insert
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'ops-attachments'
  and exists (
    select 1
    from public.attachments a
    where a.storage_bucket = storage.objects.bucket_id
      and a.storage_path = storage.objects.name
      and a.linked_entity_type = 'PRINT_JOB'
      and (
        public.current_user_has_role('OWNER_ADMIN')
        or (
          public.current_user_has_role('PRINTER_PRODUCTION')
          and a.attachment_kind = 'PRODUCTION_EVIDENCE'
          and a.uploaded_by_user_id = (select auth.uid())
          and exists (
            select 1
            from public.print_jobs pj
            where pj.id = a.linked_entity_id
              and pj.assignee_user_id = (select auth.uid())
          )
        )
      )
  )
);

commit;
