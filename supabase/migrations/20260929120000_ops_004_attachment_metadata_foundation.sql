-- OPS-004 bounded unit: attachment metadata foundation
-- Architecture Generation 1
-- Source of Truth: SOURCE_OF_TRUTH.md
--
-- Scope is intentionally limited to attachment metadata. The binary objects
-- remain in Supabase Storage. Module-specific attachment visibility and storage
-- object policies are later bounded units within OPS-004 / downstream modules.
--
-- Security posture for this foundation is deliberately restrictive:
-- - RLS is enabled immediately.
-- - OWNER_ADMIN may read/create attachment metadata.
-- - Direct authenticated update/delete is not granted.
-- - service_role retains full access for trusted backend/storage orchestration.

begin;

create table public.attachments (
  id uuid primary key default gen_random_uuid(),
  linked_entity_type text not null,
  linked_entity_id uuid not null,
  attachment_kind text not null default 'GENERAL',
  storage_bucket text not null default 'ops-attachments',
  storage_path text not null unique,
  original_file_name text not null,
  media_type text,
  size_bytes bigint,
  metadata jsonb not null default '{}'::jsonb,
  uploaded_by_user_id uuid references public.users(id) on delete set null,
  created_at timestamptz not null default timezone('utc', now()),

  constraint attachments_linked_entity_type_not_blank
    check (length(btrim(linked_entity_type)) > 0),
  constraint attachments_linked_entity_type_supported
    check (
      linked_entity_type in (
        'CUSTOMER',
        'SUPPLIER',
        'PRODUCT_VARIANT',
        'PURCHASE_ORDER',
        'GOODS_RECEIPT',
        'QUOTATION',
        'SALES_ORDER',
        'SALES_ORDER_ITEM',
        'PRINT_JOB',
        'CUSTOMER_PAYMENT',
        'DELIVERY',
        'TASK',
        'STOCKTAKE'
      )
    ),
  constraint attachments_kind_supported
    check (
      attachment_kind in (
        'GENERAL',
        'ARTWORK',
        'DOCUMENT',
        'PAYMENT_EVIDENCE',
        'DELIVERY_EVIDENCE',
        'PRODUCTION_EVIDENCE'
      )
    ),
  constraint attachments_storage_bucket_not_blank
    check (length(btrim(storage_bucket)) > 0),
  constraint attachments_storage_path_not_blank
    check (length(btrim(storage_path)) > 0),
  constraint attachments_original_file_name_not_blank
    check (length(btrim(original_file_name)) > 0),
  constraint attachments_size_nonnegative
    check (size_bytes is null or size_bytes >= 0),
  constraint attachments_metadata_is_object
    check (jsonb_typeof(metadata) = 'object')
);

create index attachments_linked_entity_idx
  on public.attachments(linked_entity_type, linked_entity_id);

create index attachments_uploaded_by_user_id_idx
  on public.attachments(uploaded_by_user_id);

create index attachments_created_at_idx
  on public.attachments(created_at desc);

alter table public.attachments enable row level security;

revoke all on public.attachments from public, anon, authenticated;
grant select, insert on public.attachments to authenticated;
grant all on public.attachments to service_role;

create policy attachments_select_owner_admin
on public.attachments
for select
to authenticated
using (
  public.current_user_has_role('OWNER_ADMIN')
);

create policy attachments_insert_owner_admin
on public.attachments
for insert
to authenticated
with check (
  public.current_user_has_role('OWNER_ADMIN')
  and (
    uploaded_by_user_id is null
    or uploaded_by_user_id = auth.uid()
  )
);

commit;
