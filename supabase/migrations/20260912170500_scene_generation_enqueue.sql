-- P2 provider-neutral enqueue boundary.
-- Callers describe the generation requirement and media intent. They never select a provider/model.

create or replace function production.enqueue_scene_generation_job(
  p_organization_id uuid,
  p_idempotency_key text,
  p_requirements jsonb,
  p_input_payload jsonb,
  p_show_id uuid default null,
  p_scene_id uuid default null,
  p_shot_id uuid default null,
  p_max_attempts integer default 3
)
returns production.scene_generation_jobs
language plpgsql
security definer
set search_path = pg_catalog, platform, production
as $$
declare
  v_user uuid := auth.uid();
  v_existing production.scene_generation_jobs%rowtype;
  v_job production.scene_generation_jobs%rowtype;
  v_task text;
  v_mode text;
  v_quality text;
  v_latency text;
  v_prompt text;
  v_cost_ceiling integer;
  v_retry_budget integer;
begin
  if p_organization_id is null then raise exception 'organization_required'; end if;
  if nullif(trim(p_idempotency_key), '') is null or length(p_idempotency_key) < 8 or length(p_idempotency_key) > 200 then
    raise exception 'invalid_idempotency_key';
  end if;
  if p_requirements is null or jsonb_typeof(p_requirements) <> 'object' then raise exception 'requirements_object_required'; end if;
  if p_input_payload is null or jsonb_typeof(p_input_payload) <> 'object' then raise exception 'input_payload_object_required'; end if;
  if p_max_attempts < 1 or p_max_attempts > 10 then raise exception 'invalid_max_attempts'; end if;

  -- service_role has no auth.uid(). Direct authenticated callers must belong to the organization.
  if v_user is not null and not platform.is_org_member(p_organization_id) then raise exception 'forbidden'; end if;

  -- Provider/model selection is explicitly forbidden at the public generation boundary.
  if p_requirements ?| array['provider','model','routeKey','route_key','endpoint']
     or p_input_payload ?| array['provider','model','routeKey','route_key','endpoint'] then
    raise exception 'provider_selection_not_allowed';
  end if;

  v_task := nullif(trim(p_requirements->>'task'), '');
  v_mode := nullif(trim(p_requirements->>'productionMode'), '');
  v_quality := nullif(trim(p_requirements->>'qualityClass'), '');
  v_latency := nullif(trim(p_requirements->>'latencyClass'), '');
  v_prompt := nullif(trim(p_input_payload->>'prompt'), '');

  if v_task is null then raise exception 'generation_task_required'; end if;
  if v_task not in ('image','reference_image','video','image_to_video','lip_sync','voice','audio') then raise exception 'invalid_generation_task'; end if;
  if v_mode is null or v_mode not in ('cinematic','anime','stylized_3d','cartoon','comic','stick_figure') then raise exception 'invalid_production_mode'; end if;
  if v_quality is null or v_quality not in ('draft','standard','cinematic','hero') then raise exception 'invalid_quality_class'; end if;
  if v_latency is null or v_latency not in ('interactive','normal','batch') then raise exception 'invalid_latency_class'; end if;
  if v_prompt is null then raise exception 'generation_prompt_required'; end if;

  if v_task in ('video','image_to_video') and coalesce((p_requirements->>'targetDurationSeconds')::numeric, 0) <= 0 then
    raise exception 'video_target_duration_required';
  end if;
  if v_task = 'image_to_video' and coalesce(jsonb_array_length(coalesce(p_input_payload->'referenceUrls','[]'::jsonb)), 0) < 1 then
    raise exception 'image_to_video_reference_required';
  end if;

  v_cost_ceiling := nullif(p_requirements->>'costCeilingCents','')::integer;
  v_retry_budget := nullif(p_requirements->>'retryBudgetCents','')::integer;
  if v_cost_ceiling is not null and v_cost_ceiling < 0 then raise exception 'invalid_cost_ceiling'; end if;
  if v_retry_budget is not null and v_retry_budget < 0 then raise exception 'invalid_retry_budget'; end if;

  select * into v_existing
  from production.scene_generation_jobs
  where organization_id = p_organization_id and idempotency_key = p_idempotency_key;

  if v_existing.id is not null then
    if v_existing.requirements is distinct from p_requirements
       or v_existing.input_payload is distinct from p_input_payload
       or v_existing.show_id is distinct from p_show_id
       or v_existing.scene_id is distinct from p_scene_id
       or v_existing.shot_id is distinct from p_shot_id then
      raise exception 'idempotency_conflict';
    end if;
    return v_existing;
  end if;

  insert into production.scene_generation_jobs(
    organization_id, show_id, scene_id, shot_id, idempotency_key,
    status, requirements, input_payload,
    cost_ceiling_cents, retry_budget_cents, max_attempts
  ) values (
    p_organization_id, p_show_id, p_scene_id, p_shot_id, p_idempotency_key,
    'queued', p_requirements, p_input_payload,
    v_cost_ceiling, v_retry_budget, p_max_attempts
  ) returning * into v_job;

  perform system.emit_event(
    p_organization_id,
    'scene.generation.queued',
    'production.scene_generation_jobs',
    v_job.id,
    jsonb_build_object(
      'task', v_task,
      'production_mode', v_mode,
      'quality_class', v_quality,
      'show_id', p_show_id,
      'scene_id', p_scene_id,
      'shot_id', p_shot_id
    ),
    'scene-generation-enqueue'
  );

  return v_job;
end;
$$;

revoke all on function production.enqueue_scene_generation_job(uuid,text,jsonb,jsonb,uuid,uuid,uuid,integer) from public, anon;
grant execute on function production.enqueue_scene_generation_job(uuid,text,jsonb,jsonb,uuid,uuid,uuid,integer) to authenticated, service_role;

comment on function production.enqueue_scene_generation_job(uuid,text,jsonb,jsonb,uuid,uuid,uuid,integer) is
  'Idempotently queues a provider-neutral Scene generation job. Provider/model/endpoint choice is rejected at this boundary.';
