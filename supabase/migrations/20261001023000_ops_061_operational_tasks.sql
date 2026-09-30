-- OPS-061: operational task workflow
-- Architecture Generation 1
-- Source of Truth: SOURCE_OF_TRUTH.md
begin;

create or replace function public.guard_assigned_task_update()
returns trigger
language plpgsql
set search_path=public,pg_temp
as $$
declare
  v_user_id uuid:=auth.uid();
  v_is_owner boolean:=coalesce(public.current_user_has_role('OWNER_ADMIN'),false);
  v_valid_assignee boolean;
begin
  if tg_op='INSERT' then
    if v_user_id is not null then
      if not v_is_owner then
        raise exception 'Only OWNER_ADMIN may create operational tasks' using errcode='42501';
      end if;
      if new.created_by_user_id is null then
        new.created_by_user_id:=v_user_id;
      elsif new.created_by_user_id is distinct from v_user_id then
        raise exception 'Task creator must match authenticated user';
      end if;
    end if;

    if new.status<>'OPEN' or new.completed_at is not null then
      raise exception 'New operational tasks must start OPEN and incomplete';
    end if;

    if new.assignee_user_id is not null then
      select exists(
        select 1
        from public.users u
        join public.user_roles ur on ur.user_id=u.id
        join public.roles r on r.id=ur.role_id
        where u.id=new.assignee_user_id
          and u.is_active=true
          and r.code in ('SALES','ACCOUNTING','WAREHOUSE','PRINTER_PRODUCTION')
      ) into v_valid_assignee;
      if not v_valid_assignee then
        raise exception 'Task assignee must be an active operational user';
      end if;
    end if;
    return new;
  end if;

  if new.status='DONE' then
    new.completed_at:=coalesce(old.completed_at,new.completed_at,timezone('utc',now()));
  else
    new.completed_at:=null;
  end if;

  if v_user_id is not null and not v_is_owner then
    if old.assignee_user_id is distinct from v_user_id then
      raise exception 'User is not authorized to update this task' using errcode='42501';
    end if;

    if old.status in ('DONE','CANCELLED') then
      raise exception 'Closed operational tasks are locked for assignees';
    end if;

    if new.id is distinct from old.id
       or new.task_type is distinct from old.task_type
       or new.linked_entity_type is distinct from old.linked_entity_type
       or new.linked_entity_id is distinct from old.linked_entity_id
       or new.assignee_user_id is distinct from old.assignee_user_id
       or new.due_at is distinct from old.due_at
       or new.priority is distinct from old.priority
       or new.created_by_user_id is distinct from old.created_by_user_id
       or new.created_at is distinct from old.created_at then
      raise exception 'Task assignees may update only execution fields on their assigned tasks';
    end if;
  end if;

  if new.assignee_user_id is distinct from old.assignee_user_id and new.assignee_user_id is not null then
    select exists(
      select 1
      from public.users u
      join public.user_roles ur on ur.user_id=u.id
      join public.roles r on r.id=ur.role_id
      where u.id=new.assignee_user_id
        and u.is_active=true
        and r.code in ('SALES','ACCOUNTING','WAREHOUSE','PRINTER_PRODUCTION')
    ) into v_valid_assignee;
    if not v_valid_assignee then
      raise exception 'Task assignee must be an active operational user';
    end if;
  end if;

  if v_user_id is null or v_is_owner then
    return new;
  end if;

  if new.status='CANCELLED' then
    raise exception 'Only OWNER_ADMIN may cancel operational tasks' using errcode='42501';
  end if;

  if old.status='IN_PROGRESS' and new.status='OPEN' then
    raise exception 'Assignee cannot move IN_PROGRESS task back to OPEN';
  end if;
  if old.status='BLOCKED' and new.status='OPEN' then
    raise exception 'Assignee cannot move BLOCKED task back to OPEN';
  end if;

  return new;
end;
$$;
revoke all on function public.guard_assigned_task_update() from public,anon,authenticated;

drop trigger if exists tasks_guard_assigned_update on public.tasks;
create trigger tasks_guard_assigned_update
before insert or update on public.tasks
for each row execute function public.guard_assigned_task_update();

create or replace view public.operational_task_queue
with (security_invoker=true)
as
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
    when t.status not in ('DONE','CANCELLED')
      and t.due_at is not null
      and t.due_at < timezone('utc',now())
      then true
    else false
  end as is_overdue,
  t.created_by_user_id
from public.tasks t;

revoke all on public.operational_task_queue from public,anon;
grant select on public.operational_task_queue to authenticated;
grant all on public.operational_task_queue to service_role;

create or replace function public.task_assignee_directory()
returns table(
  user_id uuid,
  display_name text,
  role_codes text[]
)
language plpgsql
stable
security invoker
set search_path=public,pg_temp
as $$
begin
  if not public.current_user_has_role('OWNER_ADMIN') then
    raise exception 'Task assignee directory requires OWNER_ADMIN role' using errcode='42501';
  end if;

  return query
  select
    u.id,
    u.display_name,
    array_agg(distinct r.code order by r.code)
  from public.users u
  join public.user_roles ur on ur.user_id=u.id
  join public.roles r on r.id=ur.role_id
  where u.is_active=true
    and r.code in ('SALES','ACCOUNTING','WAREHOUSE','PRINTER_PRODUCTION')
  group by u.id,u.display_name
  order by coalesce(u.display_name,u.id::text),u.id;
end;
$$;
revoke all on function public.task_assignee_directory() from public,anon;
grant execute on function public.task_assignee_directory() to authenticated,service_role;

create or replace function public.create_operational_task(
  p_task_type text,
  p_linked_entity_type text default null,
  p_linked_entity_id uuid default null,
  p_assignee_user_id uuid default null,
  p_due_at timestamptz default null,
  p_priority text default 'NORMAL',
  p_notes text default null
)
returns uuid
language plpgsql
security invoker
set search_path=public,pg_temp
as $$
declare
  v_user_id uuid:=auth.uid();
  v_task_id uuid;
  v_task_type text:=upper(btrim(coalesce(p_task_type,'')));
  v_link_type text:=upper(btrim(coalesce(p_linked_entity_type,'')));
  v_priority text:=upper(btrim(coalesce(p_priority,'NORMAL')));
begin
  if v_user_id is null or not public.current_user_has_role('OWNER_ADMIN') then
    raise exception 'Operational task creation requires OWNER_ADMIN role' using errcode='42501';
  end if;
  if length(v_task_type)=0 then raise exception 'Task type is required'; end if;
  if v_priority not in ('LOW','NORMAL','HIGH','URGENT') then raise exception 'Invalid task priority'; end if;
  if (length(v_link_type)=0) is distinct from (p_linked_entity_id is null) then
    raise exception 'Linked entity type and id must be provided together';
  end if;

  insert into public.tasks(
    task_type,linked_entity_type,linked_entity_id,assignee_user_id,due_at,status,priority,notes,created_by_user_id
  )
  values(
    v_task_type,
    nullif(v_link_type,''),
    p_linked_entity_id,
    p_assignee_user_id,
    p_due_at,
    'OPEN',
    v_priority,
    nullif(btrim(coalesce(p_notes,'')),''),
    v_user_id
  )
  returning id into v_task_id;

  return v_task_id;
end;
$$;
revoke all on function public.create_operational_task(text,text,uuid,uuid,timestamptz,text,text) from public,anon;
grant execute on function public.create_operational_task(text,text,uuid,uuid,timestamptz,text,text)
to authenticated,service_role;

create or replace function public.manage_operational_task(
  p_task_id uuid,
  p_assignee_user_id uuid,
  p_due_at timestamptz,
  p_priority text,
  p_notes text default null
)
returns uuid
language plpgsql
security invoker
set search_path=public,pg_temp
as $$
declare
  v_user_id uuid:=auth.uid();
  v_status text;
  v_priority text:=upper(btrim(coalesce(p_priority,'NORMAL')));
begin
  if v_user_id is null or not public.current_user_has_role('OWNER_ADMIN') then
    raise exception 'Operational task management requires OWNER_ADMIN role' using errcode='42501';
  end if;
  if v_priority not in ('LOW','NORMAL','HIGH','URGENT') then raise exception 'Invalid task priority'; end if;

  select status into v_status from public.tasks where id=p_task_id for update;
  if not found then raise exception 'Operational task % does not exist',p_task_id; end if;
  if v_status in ('DONE','CANCELLED') then
    raise exception 'Closed operational task management is locked';
  end if;

  update public.tasks
  set assignee_user_id=p_assignee_user_id,
      due_at=p_due_at,
      priority=v_priority,
      notes=nullif(btrim(coalesce(p_notes,'')),'')
  where id=p_task_id;

  return p_task_id;
end;
$$;
revoke all on function public.manage_operational_task(uuid,uuid,timestamptz,text,text) from public,anon;
grant execute on function public.manage_operational_task(uuid,uuid,timestamptz,text,text)
to authenticated,service_role;

create or replace function public.update_operational_task_execution(
  p_task_id uuid,
  p_status text,
  p_notes text default null
)
returns uuid
language plpgsql
security invoker
set search_path=public,pg_temp
as $$
declare
  v_user_id uuid:=auth.uid();
  v_old_status text;
  v_assignee uuid;
  v_status text:=upper(btrim(coalesce(p_status,'')));
  v_is_owner boolean;
begin
  if v_user_id is null then raise exception 'Authentication required' using errcode='42501'; end if;
  v_is_owner:=public.current_user_has_role('OWNER_ADMIN');

  if v_status not in ('OPEN','IN_PROGRESS','BLOCKED','DONE') then
    raise exception 'Invalid operational task execution status';
  end if;

  select status,assignee_user_id
  into v_old_status,v_assignee
  from public.tasks
  where id=p_task_id
  for update;

  if not found then raise exception 'Operational task % does not exist or is not visible',p_task_id; end if;
  if not v_is_owner and v_assignee is distinct from v_user_id then
    raise exception 'Operational task execution requires OWNER_ADMIN or current assignee role' using errcode='42501';
  end if;
  if not v_is_owner and v_old_status in ('DONE','CANCELLED') then
    raise exception 'Closed operational tasks are locked for assignees';
  end if;

  update public.tasks
  set status=v_status,
      notes=case
        when p_notes is null then notes
        else nullif(btrim(p_notes),'')
      end
  where id=p_task_id;

  return p_task_id;
end;
$$;
revoke all on function public.update_operational_task_execution(uuid,text,text) from public,anon;
grant execute on function public.update_operational_task_execution(uuid,text,text)
to authenticated,service_role;

create or replace function public.cancel_operational_task(
  p_task_id uuid,
  p_note text default null
)
returns uuid
language plpgsql
security invoker
set search_path=public,pg_temp
as $$
declare
  v_user_id uuid:=auth.uid();
  v_status text;
begin
  if v_user_id is null or not public.current_user_has_role('OWNER_ADMIN') then
    raise exception 'Operational task cancellation requires OWNER_ADMIN role' using errcode='42501';
  end if;

  select status into v_status from public.tasks where id=p_task_id for update;
  if not found then raise exception 'Operational task % does not exist',p_task_id; end if;
  if v_status in ('DONE','CANCELLED') then raise exception 'Closed operational task cannot be cancelled'; end if;

  update public.tasks
  set status='CANCELLED',
      notes=case
        when nullif(btrim(coalesce(p_note,'')),'') is null then notes
        else concat_ws(E'\n',notes,'Cancelled: '||btrim(p_note))
      end
  where id=p_task_id;

  return p_task_id;
end;
$$;
revoke all on function public.cancel_operational_task(uuid,text) from public,anon;
grant execute on function public.cancel_operational_task(uuid,text) to authenticated,service_role;

commit;
