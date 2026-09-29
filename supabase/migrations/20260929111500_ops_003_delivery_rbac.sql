-- OPS-003 bounded unit: delivery RBAC policies
-- Architecture Generation 1
-- Source of Truth: SOURCE_OF_TRUTH.md
--
-- Scope is intentionally limited to delivery headers/items.
-- Operational-task authorization and representative permission verification
-- remain later bounded units inside OPS-003.
--
-- Policy intent derived from SOT Sections 4.10 and 5:
-- - OWNER_ADMIN and WAREHOUSE may read/create/update operational deliveries.
-- - SALES may read delivery records needed to follow order/delivery status.
-- - ACCOUNTING and PRINTER_PRODUCTION receive no direct delivery-table access.
-- - No authenticated DELETE is granted; cancellation is represented by the
--   delivery status and preserves operational traceability.

begin;

revoke all on
  public.deliveries,
  public.delivery_items
from anon;

revoke all on
  public.deliveries,
  public.delivery_items
from authenticated;

grant select, insert, update on
  public.deliveries,
  public.delivery_items
to authenticated;

grant all on
  public.deliveries,
  public.delivery_items
to service_role;

create policy deliveries_select_operational_roles
on public.deliveries
for select
to authenticated
using (
  public.current_user_has_role('OWNER_ADMIN')
  or public.current_user_has_role('WAREHOUSE')
  or public.current_user_has_role('SALES')
);

create policy deliveries_insert_operational_roles
on public.deliveries
for insert
to authenticated
with check (
  public.current_user_has_role('OWNER_ADMIN')
  or public.current_user_has_role('WAREHOUSE')
);

create policy deliveries_update_operational_roles
on public.deliveries
for update
to authenticated
using (
  public.current_user_has_role('OWNER_ADMIN')
  or public.current_user_has_role('WAREHOUSE')
)
with check (
  public.current_user_has_role('OWNER_ADMIN')
  or public.current_user_has_role('WAREHOUSE')
);

create policy delivery_items_select_operational_roles
on public.delivery_items
for select
to authenticated
using (
  public.current_user_has_role('OWNER_ADMIN')
  or public.current_user_has_role('WAREHOUSE')
  or public.current_user_has_role('SALES')
);

create policy delivery_items_insert_operational_roles
on public.delivery_items
for insert
to authenticated
with check (
  public.current_user_has_role('OWNER_ADMIN')
  or public.current_user_has_role('WAREHOUSE')
);

create policy delivery_items_update_operational_roles
on public.delivery_items
for update
to authenticated
using (
  public.current_user_has_role('OWNER_ADMIN')
  or public.current_user_has_role('WAREHOUSE')
)
with check (
  public.current_user_has_role('OWNER_ADMIN')
  or public.current_user_has_role('WAREHOUSE')
);

commit;
