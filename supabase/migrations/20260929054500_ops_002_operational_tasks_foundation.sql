-- OPS-002 bounded unit: operational-task database foundation
-- Architecture Generation 1
-- Source of Truth: SOURCE_OF_TRUTH.md
--
-- Scope is limited to the shared operational task record and queue view.
-- Task workflow behavior, assignment UX, notifications, authorization,
-- attachments, audit/activity logging, and module-specific automation remain
-- in later OPS tasks.

begin;

create table public.tasks (
  id uuid primary key default gen_random_uuid(),
  task_type text not null,
  linked_entity_type text,
  linked_entity_id uuid,
  assignee_user_id uuid,
  due_at timestamptz,
  status text not null default 'OPEN',
  priority text not null default 'NORMAL',
  notes text,
  completed_at timestamptz,
  created_by_user_id uuid,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint tasks_type_not_blank
    check (length(btrim(task_type)) > 0),
  constraint tasks_link_pair_valid
    check (
      (linked_entity_type is null and linked_entity_id is null)
      or
      (
        linked_entity_type is not null
        and length(btrim(linked_entity_type)) > 0
        and linked_entity_id is not null
      )
    ),
  constraint tasks_status_valid
    check (
      status in (
        'OPEN',
        'IN_PROGRESS',
        'BLOCKED',
        'DONE',
        'CANCELLED'
      )
    ),
  constraint tasks_priority_valid
    check (priority in ('LOW', 'NORMAL', 'HIGH', 'URGENT')),
  constraint tasks_completion_state_valid
    check (
      (status = 'DONE' and completed_at is not null)
      or
      (status <> 'DONE' and completed_at is null)
    )
);

create view public.operational_task_queue as
select
  t.id as task_id,
  t.task_type,
  t.linked_entity_type,
  t.linked_entity_id,
  t.assignee_user_id,
  t.due_at,
  t.status,
  t.priority,
  t.notes,
  t.completed_at,
  t.created_at,
  t.updated_at,
  case
    when t.status not in ('DONE', 'CANCELLED')
      and t.due_at is not null
      and t.due_at < timezone('utc', now())
      then true
    else false
  end as is_overdue
from public.tasks t;

create index tasks_status_due_at_idx
  on public.tasks(status, due_at);

create index tasks_assignee_status_idx
  on public.tasks(assignee_user_id, status);

create index tasks_linked_entity_idx
  on public.tasks(linked_entity_type, linked_entity_id);

create index tasks_type_status_idx
  on public.tasks(task_type, status);

create trigger tasks_set_updated_at
before update on public.tasks
for each row execute function public.set_updated_at();

commit;
