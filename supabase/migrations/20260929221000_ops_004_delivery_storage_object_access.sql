-- OPS-004 bounded unit: delivery Supabase Storage object access
-- Architecture Generation 1
-- Source of Truth: SOURCE_OF_TRUTH.md
--
-- Scope is intentionally limited to binary DELIVERY_EVIDENCE objects linked to
-- DELIVERY attachment metadata. Other module attachment/storage access remains
-- a later OPS-004 unit.
--
-- Security / workflow posture:
-- - ops-attachments is private; downloads remain subject to storage.objects RLS.
-- - Object access is metadata-first: an exact public.attachments row must already
--   authorize the bucket/path before the binary object can be read or uploaded.
-- - OWNER_ADMIN may read/upload DELIVERY_EVIDENCE objects for DELIVERY attachments.
-- - WAREHOUSE may read DELIVERY_EVIDENCE objects and may upload only self-attributed
--   DELIVERY_EVIDENCE objects for deliveries.
-- - SALES may read delivery evidence for operational follow-up but receives no upload
--   capability.
-- - ACCOUNTING and PRINTER_PRODUCTION gain no delivery object access.
-- - No authenticated UPDATE or DELETE policy is introduced, so direct upsert,
--   replacement, move, or delete remains unavailable in this bounded unit.
-- - service_role continues to bypass RLS for trusted backend orchestration.

begin;

insert into storage.buckets (id, name, public)
values ('ops-attachments', 'ops-attachments', false)
on conflict (id) do update
set public = false;

drop policy if exists ops_delivery_attachments_select
on storage.objects;

create policy ops_delivery_attachments_select
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
      and a.linked_entity_type = 'DELIVERY'
      and a.attachment_kind = 'DELIVERY_EVIDENCE'
      and exists (
        select 1
        from public.deliveries d
        where d.id = a.linked_entity_id
      )
      and (
        public.current_user_has_role('OWNER_ADMIN')
        or public.current_user_has_role('WAREHOUSE')
        or public.current_user_has_role('SALES')
      )
  )
);

drop policy if exists ops_delivery_attachments_insert
on storage.objects;

create policy ops_delivery_attachments_insert
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
      and a.linked_entity_type = 'DELIVERY'
      and a.attachment_kind = 'DELIVERY_EVIDENCE'
      and exists (
        select 1
        from public.deliveries d
        where d.id = a.linked_entity_id
      )
      and (
        public.current_user_has_role('OWNER_ADMIN')
        or (
          public.current_user_has_role('WAREHOUSE')
          and a.uploaded_by_user_id = (select auth.uid())
        )
      )
  )
);

commit;
