-- OPS-004 bounded unit: purchase-order Supabase Storage object access
-- Architecture Generation 1
-- Source of Truth: SOURCE_OF_TRUTH.md
--
-- Scope is intentionally limited to binary DOCUMENT / PAYMENT_EVIDENCE objects
-- linked to PURCHASE_ORDER attachment metadata. Other module attachment/storage
-- access remains a later OPS-004 unit.
--
-- Security / workflow posture:
-- - ops-attachments is private; downloads remain subject to storage.objects RLS.
-- - Object access is metadata-first: an exact public.attachments row must already
--   authorize the bucket/path before the binary object can be read or uploaded.
-- - OWNER_ADMIN may read/upload DOCUMENT / PAYMENT_EVIDENCE objects for
--   PURCHASE_ORDER attachments.
-- - ACCOUNTING may read those purchase-order objects but receives no upload
--   capability because purchase-order attachment mutation remains OWNER_ADMIN-only.
-- - SALES, WAREHOUSE, and PRINTER_PRODUCTION gain no purchase-order object access.
-- - No authenticated UPDATE or DELETE policy is introduced, so direct upsert,
--   replacement, move, or delete remains unavailable in this bounded unit.
-- - service_role continues to bypass RLS for trusted backend orchestration.

begin;

insert into storage.buckets (id, name, public)
values ('ops-attachments', 'ops-attachments', false)
on conflict (id) do update
set public = false;

drop policy if exists ops_purchase_order_attachments_select
on storage.objects;

create policy ops_purchase_order_attachments_select
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
      and a.linked_entity_type = 'PURCHASE_ORDER'
      and a.attachment_kind in ('DOCUMENT', 'PAYMENT_EVIDENCE')
      and exists (
        select 1
        from public.purchase_orders po
        where po.id = a.linked_entity_id
      )
      and (
        public.current_user_has_role('OWNER_ADMIN')
        or public.current_user_has_role('ACCOUNTING')
      )
  )
);

drop policy if exists ops_purchase_order_attachments_insert
on storage.objects;

create policy ops_purchase_order_attachments_insert
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
      and a.linked_entity_type = 'PURCHASE_ORDER'
      and a.attachment_kind in ('DOCUMENT', 'PAYMENT_EVIDENCE')
      and exists (
        select 1
        from public.purchase_orders po
        where po.id = a.linked_entity_id
      )
      and public.current_user_has_role('OWNER_ADMIN')
  )
);

commit;
