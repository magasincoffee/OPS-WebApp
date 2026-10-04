-- OPS-003 bounded unit: operational-task RBAC policies
-- Architecture Generation 1
-- Source of Truth: SOURCE_OF_TRUTH.md
--
-- Scope is intentionally limited to shared operational tasks and the
-- operational_task_queue view. Representative permission verification remains
-- a later bounded unit inside OPS-003.
--
-- Policy intent derived from SOT Sections 4.12 and 5:
-- - OWNER_ADMIN has full task administration.
-- - Users holding any locked V1 operational role may read tasks assigned to
--   themselves and update only execution fields on those assigned tasks.
-- - Assignees cannot rewrite task identity, linked business entity, assignment,
--   due date, priority, creator, or creation timestamp.
-- - Task creation/reassignment/deletion stays OWNER_ADMIN-only at this bounded
--   RBAC layer; later module workflows may create tasks through trusted backend
--   automation/service-role paths without weakening end-user policies.

begin;

revoke all on public.tasks from anon;
revoke all on public.tasks from authenticated;

grant select, insert, update, delete on public.tasks to authenticated;
grant all on public.tasks to service_role;

create policy tasks_select_owner_or_assignee
on public.tasks
for select
to authenticated
using (
  public.current_user_has_role('OWNER_ADMIN')
  or (
    assignee_user_id = auth.uid()
    and (
      public.current_user_has_role('SALES')
      or public.current_user_has_role('ACCOUNTING')
      or public.current_user_has_role('WAREHOUSE')
      or public.current_user_has_role('PRINTER_PRODUCTION')
    )
  )
);

create policy tasks_insert_owner_admin
on public.tasks
for insert
to authenticated
with check (
  public.current_user_has_role('OWNER_ADMIN')
);

create policy tasks_update_owner_or_assignee
on public.tasks
for update
to authenticated
using (
  public.current_user_has_role('OWNER_ADMIN')
  or (
    assignee_user_id = auth.uid()
    and (
      public.current_user_has_role('SALES')
      or public.current_user_has_role('ACCOUNTING')
      or public.current_user_has_role('WAREHOUSE')
      or public.current_user_has_role('PRINTER_PRODUCTION')
    )
  )
)
with check (
  public.current_user_has_role('OWNER_ADMIN')
  or (
    assignee_user_id = auth.uid()
    and (
      public.current_user_has_role('SALES')
      or public.current_user_has_role('ACCOUNTING')
      or public.current_user_has_role('WAREHOUSE')
      or public.current_user_has_role('PRINTER_PRODUCTION')
    )
  )
);

create policy tasks_delete_owner_admin
on public.tasks
for delete
to authenticated
using (
  public.current_user_has_role('OWNER_ADMIN')
);

create or replace function public.guard_assigned_task_update()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if auth.role() = 'service_role'
     or public.current_user_has_role('OWNER_ADMIN') then
    return new;
  end if;

  if old.assignee_user_id = auth.uid()
     and (
       public.current_user_has_role('SALES')
       or public.current_user_has_role('ACCOUNTING')
       or public.current_user_has_role('WAREHOUSE')
       or public.current_user_has_role('PRINTER_PRODUCTION')
     ) then
    if new.id is distinct from old.id
       or new.task_type is distinct from old.task_type
       or new.linked_entity_type is distinct from old.linked_entity_type
       or new.linked_entity_id is distinct from old.linked_entity_id
       or new.assignee_user_id is distinct from old.assignee_user_id
       or new.due_at is distinct from old.due_at
       or new.priority is distinct from old.priority
       or new.created_by_user_id is distinct from old.created_by_user_id
       or new.created_at is distinct from old.created_at then
      raise exception
        'Task assignees may update only execution fields on their assigned tasks';
    end if;

    return new;
  end if;

  raise exception 'User is not authorized to update this task';
end;
$$;

revoke all on function public.guard_assigned_task_update()
from public, anon, authenticated;

drop trigger if exists tasks_guard_assigned_update on public.tasks;
create trigger tasks_guard_assigned_update
before update on public.tasks
for each row execute function public.guard_assigned_task_update();

alter view public.operational_task_queue set (security_invoker = true);

revoke all on public.operational_task_queue from public, anon;
grant select on public.operational_task_queue to authenticated;
grant all on public.operational_task_queue to service_role;

commit;
