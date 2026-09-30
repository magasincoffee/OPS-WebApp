-- OPS-004 completion unit: remaining attachment metadata and Storage access
-- Architecture Generation 1
-- Source of Truth: SOURCE_OF_TRUTH.md
--
-- This unit closes the remaining module-specific attachment/storage surface
-- declared by the OPS-004 attachment foundation:
-- - SUPPLIER binary object access (metadata access already exists);
-- - PRODUCT_VARIANT, QUOTATION, SALES_ORDER, TASK, and STOCKTAKE metadata/object access.
--
-- Least-privilege posture mirrors the established OPS-003 RBAC:
-- - attachment kinds are limited to GENERAL/DOCUMENT for these entities;
-- - read access follows each entity's existing business-role visibility;
-- - upload access follows entity mutation/ownership responsibilities;
-- - non-owner uploads must be self-attributed;
-- - storage access is metadata-first and bucket/path exact;
-- - no authenticated UPDATE/DELETE policy is introduced.

begin;

-- ---------------------------------------------------------------------------
-- Attachment metadata: PRODUCT_VARIANT
-- All V1 business roles may read product reference documents.
-- Product master mutation remains OWNER_ADMIN-only, so no extra INSERT policy.
-- ---------------------------------------------------------------------------

drop policy if exists attachments_select_product_variant_business_roles
on public.attachments;

create policy attachments_select_product_variant_business_roles
on public.attachments
for select
to authenticated
using (
  linked_entity_type = 'PRODUCT_VARIANT'
  and attachment_kind in ('GENERAL', 'DOCUMENT')
  and storage_bucket = 'ops-attachments'
  and (
    (select public.current_user_has_role('SALES'))
    or (select public.current_user_has_role('ACCOUNTING'))
    or (select public.current_user_has_role('WAREHOUSE'))
    or (select public.current_user_has_role('PRINTER_PRODUCTION'))
  )
  and exists (
    select 1
    from public.product_variants pv
    where pv.id = attachments.linked_entity_id
  )
);

-- ---------------------------------------------------------------------------
-- Attachment metadata: QUOTATION
-- SALES owns quotation workflow and may upload self-attributed documents.
-- ---------------------------------------------------------------------------

drop policy if exists attachments_select_quotation_sales
on public.attachments;

create policy attachments_select_quotation_sales
on public.attachments
for select
to authenticated
using (
  (select public.current_user_has_role('SALES'))
  and linked_entity_type = 'QUOTATION'
  and attachment_kind in ('GENERAL', 'DOCUMENT')
  and storage_bucket = 'ops-attachments'
  and exists (
    select 1
    from public.quotations q
    where q.id = attachments.linked_entity_id
  )
);

drop policy if exists attachments_insert_quotation_sales
on public.attachments;

create policy attachments_insert_quotation_sales
on public.attachments
for insert
to authenticated
with check (
  (select public.current_user_has_role('SALES'))
  and linked_entity_type = 'QUOTATION'
  and attachment_kind in ('GENERAL', 'DOCUMENT')
  and storage_bucket = 'ops-attachments'
  and uploaded_by_user_id = (select auth.uid())
  and exists (
    select 1
    from public.quotations q
    where q.id = attachments.linked_entity_id
  )
);

-- ---------------------------------------------------------------------------
-- Attachment metadata: SALES_ORDER
-- SALES may manage/upload documents; ACCOUNTING receives read-only visibility.
-- ---------------------------------------------------------------------------

drop policy if exists attachments_select_sales_order_business_roles
on public.attachments;

create policy attachments_select_sales_order_business_roles
on public.attachments
for select
to authenticated
using (
  (
    (select public.current_user_has_role('SALES'))
    or (select public.current_user_has_role('ACCOUNTING'))
  )
  and linked_entity_type = 'SALES_ORDER'
  and attachment_kind in ('GENERAL', 'DOCUMENT')
  and storage_bucket = 'ops-attachments'
  and exists (
    select 1
    from public.sales_orders so
    where so.id = attachments.linked_entity_id
  )
);

drop policy if exists attachments_insert_sales_order_sales
on public.attachments;

create policy attachments_insert_sales_order_sales
on public.attachments
for insert
to authenticated
with check (
  (select public.current_user_has_role('SALES'))
  and linked_entity_type = 'SALES_ORDER'
  and attachment_kind in ('GENERAL', 'DOCUMENT')
  and storage_bucket = 'ops-attachments'
  and uploaded_by_user_id = (select auth.uid())
  and exists (
    select 1
    from public.sales_orders so
    where so.id = attachments.linked_entity_id
  )
);

-- ---------------------------------------------------------------------------
-- Attachment metadata: TASK
-- Any locked operational role may read/upload documents only on its own task.
-- OWNER_ADMIN remains covered by the foundation owner policies.
-- ---------------------------------------------------------------------------

drop policy if exists attachments_select_assigned_task_operational_role
on public.attachments;

create policy attachments_select_assigned_task_operational_role
on public.attachments
for select
to authenticated
using (
  linked_entity_type = 'TASK'
  and attachment_kind in ('GENERAL', 'DOCUMENT')
  and storage_bucket = 'ops-attachments'
  and (
    (select public.current_user_has_role('SALES'))
    or (select public.current_user_has_role('ACCOUNTING'))
    or (select public.current_user_has_role('WAREHOUSE'))
    or (select public.current_user_has_role('PRINTER_PRODUCTION'))
  )
  and exists (
    select 1
    from public.tasks t
    where t.id = attachments.linked_entity_id
      and t.assignee_user_id = (select auth.uid())
  )
);

drop policy if exists attachments_insert_assigned_task_operational_role
on public.attachments;

create policy attachments_insert_assigned_task_operational_role
on public.attachments
for insert
to authenticated
with check (
  linked_entity_type = 'TASK'
  and attachment_kind in ('GENERAL', 'DOCUMENT')
  and storage_bucket = 'ops-attachments'
  and uploaded_by_user_id = (select auth.uid())
  and (
    (select public.current_user_has_role('SALES'))
    or (select public.current_user_has_role('ACCOUNTING'))
    or (select public.current_user_has_role('WAREHOUSE'))
    or (select public.current_user_has_role('PRINTER_PRODUCTION'))
  )
  and exists (
    select 1
    from public.tasks t
    where t.id = attachments.linked_entity_id
      and t.assignee_user_id = (select auth.uid())
  )
);

-- ---------------------------------------------------------------------------
-- Attachment metadata: STOCKTAKE
-- WAREHOUSE owns stocktake execution and may upload self-attributed documents.
-- ---------------------------------------------------------------------------

drop policy if exists attachments_select_stocktake_warehouse
on public.attachments;

create policy attachments_select_stocktake_warehouse
on public.attachments
for select
to authenticated
using (
  (select public.current_user_has_role('WAREHOUSE'))
  and linked_entity_type = 'STOCKTAKE'
  and attachment_kind in ('GENERAL', 'DOCUMENT')
  and storage_bucket = 'ops-attachments'
  and exists (
    select 1
    from public.stocktakes st
    where st.id = attachments.linked_entity_id
  )
);

drop policy if exists attachments_insert_stocktake_warehouse
on public.attachments;

create policy attachments_insert_stocktake_warehouse
on public.attachments
for insert
to authenticated
with check (
  (select public.current_user_has_role('WAREHOUSE'))
  and linked_entity_type = 'STOCKTAKE'
  and attachment_kind in ('GENERAL', 'DOCUMENT')
  and storage_bucket = 'ops-attachments'
  and uploaded_by_user_id = (select auth.uid())
  and exists (
    select 1
    from public.stocktakes st
    where st.id = attachments.linked_entity_id
  )
);

-- ---------------------------------------------------------------------------
-- Supabase Storage object policies.
-- ---------------------------------------------------------------------------

insert into storage.buckets (id, name, public)
values ('ops-attachments', 'ops-attachments', false)
on conflict (id) do update
set public = false;

-- SUPPLIER: OWNER upload, ACCOUNTING/WAREHOUSE read.
drop policy if exists ops_supplier_attachments_select on storage.objects;
create policy ops_supplier_attachments_select
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
      and a.linked_entity_type = 'SUPPLIER'
      and a.attachment_kind in ('GENERAL', 'DOCUMENT')
      and exists (
        select 1 from public.suppliers s where s.id = a.linked_entity_id
      )
      and (
        public.current_user_has_role('OWNER_ADMIN')
        or public.current_user_has_role('ACCOUNTING')
        or public.current_user_has_role('WAREHOUSE')
      )
  )
);

drop policy if exists ops_supplier_attachments_insert on storage.objects;
create policy ops_supplier_attachments_insert
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
      and a.linked_entity_type = 'SUPPLIER'
      and a.attachment_kind in ('GENERAL', 'DOCUMENT')
      and exists (
        select 1 from public.suppliers s where s.id = a.linked_entity_id
      )
      and public.current_user_has_role('OWNER_ADMIN')
  )
);

-- PRODUCT_VARIANT: all V1 roles read reference docs, OWNER uploads.
drop policy if exists ops_product_variant_attachments_select on storage.objects;
create policy ops_product_variant_attachments_select
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
      and a.linked_entity_type = 'PRODUCT_VARIANT'
      and a.attachment_kind in ('GENERAL', 'DOCUMENT')
      and exists (
        select 1 from public.product_variants pv where pv.id = a.linked_entity_id
      )
      and (
        public.current_user_has_role('OWNER_ADMIN')
        or public.current_user_has_role('SALES')
        or public.current_user_has_role('ACCOUNTING')
        or public.current_user_has_role('WAREHOUSE')
        or public.current_user_has_role('PRINTER_PRODUCTION')
      )
  )
);

drop policy if exists ops_product_variant_attachments_insert on storage.objects;
create policy ops_product_variant_attachments_insert
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
      and a.linked_entity_type = 'PRODUCT_VARIANT'
      and a.attachment_kind in ('GENERAL', 'DOCUMENT')
      and exists (
        select 1 from public.product_variants pv where pv.id = a.linked_entity_id
      )
      and public.current_user_has_role('OWNER_ADMIN')
  )
);

-- QUOTATION: OWNER/SALES read; SALES uploads only its self-attributed metadata.
drop policy if exists ops_quotation_attachments_select on storage.objects;
create policy ops_quotation_attachments_select
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
      and a.linked_entity_type = 'QUOTATION'
      and a.attachment_kind in ('GENERAL', 'DOCUMENT')
      and exists (
        select 1 from public.quotations q where q.id = a.linked_entity_id
      )
      and (
        public.current_user_has_role('OWNER_ADMIN')
        or public.current_user_has_role('SALES')
      )
  )
);

drop policy if exists ops_quotation_attachments_insert on storage.objects;
create policy ops_quotation_attachments_insert
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
      and a.linked_entity_type = 'QUOTATION'
      and a.attachment_kind in ('GENERAL', 'DOCUMENT')
      and exists (
        select 1 from public.quotations q where q.id = a.linked_entity_id
      )
      and (
        public.current_user_has_role('OWNER_ADMIN')
        or (
          public.current_user_has_role('SALES')
          and a.uploaded_by_user_id = (select auth.uid())
        )
      )
  )
);

-- SALES_ORDER: OWNER/SALES/ACCOUNTING read; SALES uploads self-attributed docs.
drop policy if exists ops_sales_order_attachments_select on storage.objects;
create policy ops_sales_order_attachments_select
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
      and a.linked_entity_type = 'SALES_ORDER'
      and a.attachment_kind in ('GENERAL', 'DOCUMENT')
      and exists (
        select 1 from public.sales_orders so where so.id = a.linked_entity_id
      )
      and (
        public.current_user_has_role('OWNER_ADMIN')
        or public.current_user_has_role('SALES')
        or public.current_user_has_role('ACCOUNTING')
      )
  )
);

drop policy if exists ops_sales_order_attachments_insert on storage.objects;
create policy ops_sales_order_attachments_insert
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
      and a.linked_entity_type = 'SALES_ORDER'
      and a.attachment_kind in ('GENERAL', 'DOCUMENT')
      and exists (
        select 1 from public.sales_orders so where so.id = a.linked_entity_id
      )
      and (
        public.current_user_has_role('OWNER_ADMIN')
        or (
          public.current_user_has_role('SALES')
          and a.uploaded_by_user_id = (select auth.uid())
        )
      )
  )
);

-- TASK: OWNER or assigned operational user reads/uploads its own task documents.
drop policy if exists ops_task_attachments_select on storage.objects;
create policy ops_task_attachments_select
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
      and a.linked_entity_type = 'TASK'
      and a.attachment_kind in ('GENERAL', 'DOCUMENT')
      and exists (
        select 1
        from public.tasks t
        where t.id = a.linked_entity_id
          and (
            public.current_user_has_role('OWNER_ADMIN')
            or (
              t.assignee_user_id = (select auth.uid())
              and (
                public.current_user_has_role('SALES')
                or public.current_user_has_role('ACCOUNTING')
                or public.current_user_has_role('WAREHOUSE')
                or public.current_user_has_role('PRINTER_PRODUCTION')
              )
            )
          )
      )
  )
);

drop policy if exists ops_task_attachments_insert on storage.objects;
create policy ops_task_attachments_insert
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
      and a.linked_entity_type = 'TASK'
      and a.attachment_kind in ('GENERAL', 'DOCUMENT')
      and exists (
        select 1
        from public.tasks t
        where t.id = a.linked_entity_id
          and (
            public.current_user_has_role('OWNER_ADMIN')
            or (
              t.assignee_user_id = (select auth.uid())
              and a.uploaded_by_user_id = (select auth.uid())
              and (
                public.current_user_has_role('SALES')
                or public.current_user_has_role('ACCOUNTING')
                or public.current_user_has_role('WAREHOUSE')
                or public.current_user_has_role('PRINTER_PRODUCTION')
              )
            )
          )
      )
  )
);

-- STOCKTAKE: OWNER/WAREHOUSE read; WAREHOUSE uploads self-attributed docs.
drop policy if exists ops_stocktake_attachments_select on storage.objects;
create policy ops_stocktake_attachments_select
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
      and a.linked_entity_type = 'STOCKTAKE'
      and a.attachment_kind in ('GENERAL', 'DOCUMENT')
      and exists (
        select 1 from public.stocktakes st where st.id = a.linked_entity_id
      )
      and (
        public.current_user_has_role('OWNER_ADMIN')
        or public.current_user_has_role('WAREHOUSE')
      )
  )
);

drop policy if exists ops_stocktake_attachments_insert on storage.objects;
create policy ops_stocktake_attachments_insert
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
      and a.linked_entity_type = 'STOCKTAKE'
      and a.attachment_kind in ('GENERAL', 'DOCUMENT')
      and exists (
        select 1 from public.stocktakes st where st.id = a.linked_entity_id
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
