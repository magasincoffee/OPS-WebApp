-- OPS-004 bounded unit: activity-log foundation
-- Architecture Generation 1
-- Source of Truth: SOURCE_OF_TRUTH.md
--
-- Scope is intentionally limited to the shared append-only activity/audit log.
-- Module-specific automatic event capture and role-scoped activity projections
-- remain later bounded work within OPS-004 / downstream modules.
--
-- Security posture:
-- - activity logs are append-only once written;
-- - authenticated users cannot directly insert/update/delete audit records;
-- - OWNER_ADMIN may read the shared audit trail;
-- - trusted backend/database automation may insert through service_role.

begin;

create table public.activity_logs (
  id uuid primary key default gen_random_uuid(),
  linked_entity_type text not null,
  linked_entity_id uuid not null,
  action_type text not null,
  actor_user_id uuid,
  event_source text not null default 'SYSTEM',
  change_summary text,
  before_data jsonb,
  after_data jsonb,
  metadata jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default timezone('utc', now()),
  created_at timestamptz not null default timezone('utc', now()),

  constraint activity_logs_linked_entity_type_not_blank
    check (length(btrim(linked_entity_type)) > 0),
  constraint activity_logs_action_type_not_blank
    check (length(btrim(action_type)) > 0),
  constraint activity_logs_event_source_valid
    check (event_source in ('USER', 'SYSTEM', 'MIGRATION')),
  constraint activity_logs_before_data_is_object
    check (before_data is null or jsonb_typeof(before_data) = 'object'),
  constraint activity_logs_after_data_is_object
    check (after_data is null or jsonb_typeof(after_data) = 'object'),
  constraint activity_logs_metadata_is_object
    check (jsonb_typeof(metadata) = 'object')
);

create index activity_logs_entity_occurred_at_idx
  on public.activity_logs(linked_entity_type, linked_entity_id, occurred_at desc);

create index activity_logs_actor_occurred_at_idx
  on public.activity_logs(actor_user_id, occurred_at desc)
  where actor_user_id is not null;

create index activity_logs_action_occurred_at_idx
  on public.activity_logs(action_type, occurred_at desc);

create or replace function public.prevent_activity_log_mutation()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  raise exception
    'Activity logs are append-only; create a new activity record instead';
end;
$$;

revoke all on function public.prevent_activity_log_mutation()
from public, anon, authenticated;

create trigger activity_logs_prevent_update
before update on public.activity_logs
for each row execute function public.prevent_activity_log_mutation();

create trigger activity_logs_prevent_delete
before delete on public.activity_logs
for each row execute function public.prevent_activity_log_mutation();

alter table public.activity_logs enable row level security;

revoke all on public.activity_logs from public, anon, authenticated;
grant select on public.activity_logs to authenticated;
grant all on public.activity_logs to service_role;

create policy activity_logs_select_owner_admin
on public.activity_logs
for select
to authenticated
using (
  public.current_user_has_role('OWNER_ADMIN')
);

commit;
