-- Scene P2 Provider + Cost Control runtime.
-- Provider-neutral durable generation jobs with Higgsfield as the initial primary cinematic route.

create table if not exists production.scene_provider_capabilities (
  id uuid primary key default gen_random_uuid(),
  provider text not null,
  route_key text not null,
  task_type text not null,
  endpoint text not null,
  active boolean not null default true,
  priority integer not null default 100,
  production_modes text[] not null default '{}',
  quality_classes text[] not null default '{}',
  supports_references boolean not null default false,
  supports_dialogue boolean not null default false,
  supports_lipsync boolean not null default false,
  supports_camera_control boolean not null default false,
  max_duration_seconds numeric,
  expected_cost_cents numeric,
  expected_latency_seconds numeric,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint scene_provider_capabilities_provider_route_key_unique unique(provider, route_key),
  constraint scene_provider_capabilities_expected_cost_nonnegative check(expected_cost_cents is null or expected_cost_cents >= 0),
  constraint scene_provider_capabilities_expected_latency_nonnegative check(expected_latency_seconds is null or expected_latency_seconds >= 0)
);

create index if not exists scene_provider_capabilities_routing_idx
  on production.scene_provider_capabilities(task_type, active, priority desc);

create table if not exists production.scene_generation_jobs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references platform.organizations(id) on delete cascade,
  show_id uuid,
  scene_id uuid,
  shot_id uuid,
  idempotency_key text not null,
  status text not null default 'queued',
  requirements jsonb not null,
  input_payload jsonb not null,
  selected_provider text,
  selected_route_key text,
  provider_request_id text,
  provider_status text,
  status_url text,
  cancel_url text,
  cost_ceiling_cents integer,
  retry_budget_cents integer,
  estimated_cost_cents numeric,
  actual_cost_cents numeric,
  attempt_count integer not null default 0,
  max_attempts integer not null default 3,
  available_at timestamptz not null default now(),
  claimed_by text,
  claimed_at timestamptz,
  heartbeat_at timestamptz,
  submitted_at timestamptz,
  completed_at timestamptz,
  result_payload jsonb,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint scene_generation_jobs_org_idem_unique unique(organization_id, idempotency_key),
  constraint scene_generation_jobs_status_check check(status in ('queued','submitting','submitted','processing','completed','failed','canceled','retry')),
  constraint scene_generation_jobs_cost_ceiling_nonnegative check(cost_ceiling_cents is null or cost_ceiling_cents >= 0),
  constraint scene_generation_jobs_retry_budget_nonnegative check(retry_budget_cents is null or retry_budget_cents >= 0),
  constraint scene_generation_jobs_attempt_count_nonnegative check(attempt_count >= 0),
  constraint scene_generation_jobs_max_attempts_positive check(max_attempts > 0)
);

create index if not exists scene_generation_jobs_claim_idx
  on production.scene_generation_jobs(status, available_at, created_at)
  where status in ('queued','retry','submitted','processing');
create index if not exists scene_generation_jobs_provider_request_idx
  on production.scene_generation_jobs(selected_provider, provider_request_id)
  where provider_request_id is not null;
create index if not exists scene_generation_jobs_org_idx
  on production.scene_generation_jobs(organization_id, created_at desc);

create table if not exists production.scene_generation_attempts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references platform.organizations(id) on delete cascade,
  job_id uuid not null references production.scene_generation_jobs(id) on delete cascade,
  attempt_number integer not null,
  provider text not null,
  route_key text not null,
  endpoint text not null,
  request_payload jsonb not null,
  provider_request_id text,
  provider_status text,
  status_url text,
  cancel_url text,
  submitted_at timestamptz,
  completed_at timestamptz,
  estimated_cost_cents numeric,
  actual_cost_cents numeric,
  latency_ms integer,
  result_payload jsonb,
  qa_scores jsonb not null default '{}'::jsonb,
  accepted boolean,
  rejection_reason text,
  repair_action text,
  provenance jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint scene_generation_attempts_job_attempt_unique unique(job_id, attempt_number),
  constraint scene_generation_attempts_attempt_positive check(attempt_number > 0),
  constraint scene_generation_attempts_cost_nonnegative check((estimated_cost_cents is null or estimated_cost_cents >= 0) and (actual_cost_cents is null or actual_cost_cents >= 0)),
  constraint scene_generation_attempts_latency_nonnegative check(latency_ms is null or latency_ms >= 0)
);

create index if not exists scene_generation_attempts_job_idx
  on production.scene_generation_attempts(job_id, attempt_number desc);
create index if not exists scene_generation_attempts_provider_idx
  on production.scene_generation_attempts(provider, route_key, created_at desc);

create table if not exists production.scene_provider_health (
  provider text not null,
  route_key text not null,
  status text not null default 'unknown',
  last_checked_at timestamptz,
  last_success_at timestamptz,
  last_failure_at timestamptz,
  latency_ms integer,
  success_count bigint not null default 0,
  failure_count bigint not null default 0,
  consecutive_failures integer not null default 0,
  last_error text,
  metadata jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  primary key(provider, route_key),
  constraint scene_provider_health_status_check check(status in ('unknown','healthy','degraded','unavailable')),
  constraint scene_provider_health_counts_nonnegative check(success_count >= 0 and failure_count >= 0 and consecutive_failures >= 0),
  constraint scene_provider_health_latency_nonnegative check(latency_ms is null or latency_ms >= 0)
);

-- Initial benchmark route only. This is not a permanent routing winner.
insert into production.scene_provider_capabilities (
  provider, route_key, task_type, endpoint, active, priority,
  production_modes, quality_classes, supports_references,
  supports_dialogue, supports_lipsync, supports_camera_control,
  max_duration_seconds, metadata
) values (
  'higgsfield',
  'higgsfield.dop_turbo.image_to_video',
  'image_to_video',
  'v1/image2video/dop',
  true,
  100,
  array['cinematic'],
  array['cinematic','hero'],
  true,
  false,
  false,
  true,
  null,
  jsonb_build_object('model','dop-turbo','benchmark_only',true)
)
on conflict(provider, route_key) do update set
  endpoint = excluded.endpoint,
  task_type = excluded.task_type,
  active = excluded.active,
  metadata = production.scene_provider_capabilities.metadata || excluded.metadata,
  updated_at = now();

insert into production.scene_provider_health(provider, route_key)
values('higgsfield','higgsfield.dop_turbo.image_to_video')
on conflict do nothing;

create or replace function production.claim_scene_generation_job(
  p_worker_id text
)
returns setof production.scene_generation_jobs
language plpgsql
security definer
set search_path = pg_catalog, production
as $$
declare
  v_job production.scene_generation_jobs%rowtype;
begin
  if nullif(trim(p_worker_id), '') is null then
    raise exception 'worker_id_required';
  end if;

  select * into v_job
  from production.scene_generation_jobs j
  where j.status in ('queued','retry','submitted','processing')
    and j.available_at <= now()
    and (j.claimed_by is null or j.claimed_at < now() - interval '10 minutes')
  order by
    case when j.status in ('submitted','processing') then 0 else 1 end,
    j.available_at asc,
    j.created_at asc
  for update skip locked
  limit 1;

  if v_job.id is null then
    return;
  end if;

  update production.scene_generation_jobs
  set claimed_by = p_worker_id,
      claimed_at = now(),
      heartbeat_at = now(),
      updated_at = now(),
      status = case when v_job.status in ('queued','retry') then 'submitting' else v_job.status end,
      attempt_count = case when v_job.status in ('queued','retry') then v_job.attempt_count + 1 else v_job.attempt_count end
  where id = v_job.id
  returning * into v_job;

  return next v_job;
end;
$$;

revoke all on function production.claim_scene_generation_job(text) from public, anon, authenticated;
grant execute on function production.claim_scene_generation_job(text) to service_role;

create or replace function production.release_scene_generation_job(
  p_job_id uuid,
  p_worker_id text,
  p_error text,
  p_retry_delay_seconds integer default 60
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, production
as $$
declare
  v_job production.scene_generation_jobs%rowtype;
  v_next_status text;
begin
  select * into v_job from production.scene_generation_jobs
  where id = p_job_id and claimed_by = p_worker_id
  for update;

  if v_job.id is null then
    return jsonb_build_object('status','not_claimed');
  end if;

  v_next_status := case when v_job.attempt_count >= v_job.max_attempts then 'failed' else 'retry' end;

  update production.scene_generation_jobs
  set status = v_next_status,
      available_at = case when v_next_status = 'retry' then now() + make_interval(secs => greatest(coalesce(p_retry_delay_seconds,60),1)) else available_at end,
      claimed_by = null,
      claimed_at = null,
      heartbeat_at = null,
      last_error = left(coalesce(p_error,'generation_worker_error'), 4000),
      completed_at = case when v_next_status = 'failed' then now() else completed_at end,
      updated_at = now()
  where id = p_job_id;

  return jsonb_build_object('status',v_next_status,'attempt_count',v_job.attempt_count,'max_attempts',v_job.max_attempts);
end;
$$;

revoke all on function production.release_scene_generation_job(uuid,text,text,integer) from public, anon, authenticated;
grant execute on function production.release_scene_generation_job(uuid,text,text,integer) to service_role;

create or replace function production.release_scene_generation_claim(
  p_job_id uuid,
  p_worker_id text,
  p_next_poll_seconds integer default 10
)
returns boolean
language sql
security definer
set search_path = pg_catalog, production
as $$
  update production.scene_generation_jobs
  set claimed_by = null,
      claimed_at = null,
      heartbeat_at = null,
      available_at = now() + make_interval(secs => greatest(coalesce(p_next_poll_seconds,10),1)),
      updated_at = now()
  where id = p_job_id and claimed_by = p_worker_id
  returning true;
$$;

revoke all on function production.release_scene_generation_claim(uuid,text,integer) from public, anon, authenticated;
grant execute on function production.release_scene_generation_claim(uuid,text,integer) to service_role;

alter table production.scene_provider_capabilities enable row level security;
alter table production.scene_generation_jobs enable row level security;
alter table production.scene_generation_attempts enable row level security;
alter table production.scene_provider_health enable row level security;

grant select on production.scene_provider_capabilities, production.scene_provider_health to authenticated;
grant select on production.scene_generation_jobs, production.scene_generation_attempts to authenticated;
grant all on production.scene_provider_capabilities, production.scene_generation_jobs, production.scene_generation_attempts, production.scene_provider_health to service_role;

create policy scene_generation_jobs_select_member on production.scene_generation_jobs
for select to authenticated
using (platform.is_org_member(organization_id));

create policy scene_generation_attempts_select_member on production.scene_generation_attempts
for select to authenticated
using (platform.is_org_member(organization_id));

create policy scene_provider_capabilities_read on production.scene_provider_capabilities
for select to authenticated using (true);

create policy scene_provider_health_read on production.scene_provider_health
for select to authenticated using (true);

comment on table production.scene_generation_jobs is 'Durable Scene media generation jobs. Provider choice is internal and creator-facing clients submit provider-neutral requirements.';
comment on table production.scene_generation_attempts is 'One row per provider attempt for cost, QA, repair, and provenance learning.';
comment on table production.scene_provider_capabilities is 'Internal capability registry used by the Scene Production Router.';
