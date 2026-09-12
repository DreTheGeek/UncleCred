import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import postgres from "https://deno.land/x/postgresjs@v3.4.5/mod.js";
import {
  getHiggsfieldRequestStatus,
  submitHiggsfieldGeneration,
} from "../_shared/higgsfield.ts";
import {
  chooseGenerationRoute,
  type CapabilityRow,
  type HealthRow,
} from "../_shared/scene-generation-router.ts";
import type { SceneGenerationRequest } from "../_shared/scene-generation-contracts.ts";

const dbUrl = Deno.env.get("SUPABASE_DB_URL");
if (!dbUrl) throw new Error("SUPABASE_DB_URL unavailable");
const workerSecret = Deno.env.get("WORKER_SECRET");
const sql = postgres(dbUrl, { prepare: false });

type Job = {
  id: string;
  organization_id: string;
  status: string;
  requirements: Record<string, unknown>;
  input_payload: Record<string, unknown>;
  selected_provider: string | null;
  selected_route_key: string | null;
  provider_request_id: string | null;
  provider_status: string | null;
  attempt_count: number;
  max_attempts: number;
  cost_ceiling_cents: number | null;
  retry_budget_cents: number | null;
};

function errText(error: unknown) {
  if (error instanceof Error) return `${error.name}: ${error.message}`;
  try { return JSON.stringify(error); } catch { return String(error); }
}

function asRecord(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : {};
}

function asGenerationRequest(job: Job): SceneGenerationRequest {
  return {
    requirements: job.requirements as SceneGenerationRequest["requirements"],
    prompt: typeof job.input_payload.prompt === "string" ? job.input_payload.prompt : "",
    referenceUrls: Array.isArray(job.input_payload.referenceUrls)
      ? job.input_payload.referenceUrls.filter((value): value is string => typeof value === "string")
      : [],
    lastFrameUrl: typeof job.input_payload.lastFrameUrl === "string" ? job.input_payload.lastFrameUrl : null,
    negativePrompt: typeof job.input_payload.negativePrompt === "string" ? job.input_payload.negativePrompt : null,
    seed: Number.isInteger(job.input_payload.seed) ? Number(job.input_payload.seed) : null,
    metadata: asRecord(job.input_payload.metadata),
  };
}

function higgsfieldPayload(routeMetadata: Record<string, unknown>, request: SceneGenerationRequest) {
  const task = request.requirements.task;
  if (task !== "image_to_video") {
    throw new Error(`higgsfield_task_not_implemented:${task}`);
  }

  const refs = request.referenceUrls ?? [];
  if (!refs.length) throw new Error("higgsfield_reference_required");

  const model = typeof routeMetadata.model === "string" && routeMetadata.model.trim()
    ? routeMetadata.model.trim()
    : "dop-turbo";

  return {
    model,
    prompt: request.prompt,
    input_images: refs.map((url) => ({ type: "image_url", image_url: url })),
    ...(request.seed != null ? { seed: request.seed } : {}),
  };
}

async function routeFor(request: SceneGenerationRequest) {
  const capabilities = await sql<CapabilityRow[]>`
    select provider, route_key, task_type, endpoint, active, priority,
           production_modes, quality_classes, supports_references,
           supports_dialogue, supports_lipsync, supports_camera_control,
           max_duration_seconds, expected_cost_cents, expected_latency_seconds,
           metadata
    from production.scene_provider_capabilities
    where active = true
  `;
  const health = await sql<HealthRow[]>`
    select provider, route_key, status, consecutive_failures
    from production.scene_provider_health
  `;
  return chooseGenerationRoute({ request, capabilities, health });
}

async function capability(routeKey: string) {
  const rows = await sql<Array<{ endpoint: string; metadata: Record<string, unknown>; expected_cost_cents: number | null }>>`
    select endpoint, metadata, expected_cost_cents
    from production.scene_provider_capabilities
    where route_key = ${routeKey} and active = true
    limit 1
  `;
  if (!rows.length) throw new Error(`generation_route_missing:${routeKey}`);
  return rows[0];
}

async function emit(orgId: string, eventType: string, jobId: string, payload: Record<string, unknown>) {
  await sql`
    select system.emit_event(
      ${orgId}::uuid,
      ${eventType},
      'production.scene_generation_jobs',
      ${jobId}::uuid,
      ${JSON.stringify(payload)}::jsonb,
      'scene-generation-worker'
    )
  `.catch(() => {});
}

async function markHealth(provider: string, routeKey: string, ok: boolean, latencyMs: number | null, error: string | null = null) {
  await sql`
    insert into production.scene_provider_health(
      provider, route_key, status, last_checked_at, last_success_at, last_failure_at,
      latency_ms, success_count, failure_count, consecutive_failures, last_error, updated_at
    ) values (
      ${provider}, ${routeKey}, ${ok ? "healthy" : "degraded"}, now(),
      ${ok ? sql`now()` : null}, ${ok ? null : sql`now()`}, ${latencyMs},
      ${ok ? 1 : 0}, ${ok ? 0 : 1}, ${ok ? 0 : 1}, ${error}, now()
    )
    on conflict(provider, route_key) do update set
      status = excluded.status,
      last_checked_at = now(),
      last_success_at = case when ${ok} then now() else production.scene_provider_health.last_success_at end,
      last_failure_at = case when ${ok} then production.scene_provider_health.last_failure_at else now() end,
      latency_ms = coalesce(${latencyMs}, production.scene_provider_health.latency_ms),
      success_count = production.scene_provider_health.success_count + ${ok ? 1 : 0},
      failure_count = production.scene_provider_health.failure_count + ${ok ? 0 : 1},
      consecutive_failures = case when ${ok} then 0 else production.scene_provider_health.consecutive_failures + 1 end,
      last_error = ${error},
      updated_at = now()
  `;
}

async function submit(job: Job, workerId: string) {
  const request = asGenerationRequest(job);
  const route = await routeFor(request);
  if (route.provider !== "higgsfield") throw new Error(`provider_handler_not_implemented:${route.provider}`);

  const cap = await capability(route.routeKey);
  const payload = higgsfieldPayload(cap.metadata ?? {}, request);
  const attemptNumber = job.attempt_count;
  const started = Date.now();

  const attemptRows = await sql<Array<{ id: string }>>`
    insert into production.scene_generation_attempts(
      organization_id, job_id, attempt_number, provider, route_key, endpoint,
      request_payload, estimated_cost_cents
    ) values (
      ${job.organization_id}::uuid, ${job.id}::uuid, ${attemptNumber}, ${route.provider},
      ${route.routeKey}, ${route.modelOrEndpoint}, ${JSON.stringify(payload)}::jsonb,
      ${route.expectedCostCents}
    )
    on conflict(job_id, attempt_number) do nothing
    returning id::text
  `;
  if (!attemptRows.length) throw new Error("generation_attempt_already_exists");

  try {
    const result = await submitHiggsfieldGeneration({ endpoint: route.modelOrEndpoint, payload });
    const latencyMs = Date.now() - started;

    await sql.begin(async (tx) => {
      await tx`
        update production.scene_generation_attempts
        set provider_request_id = ${result.requestId}, provider_status = ${result.status},
            status_url = ${result.statusUrl}, cancel_url = ${result.cancelUrl}, submitted_at = now(),
            latency_ms = ${latencyMs}, provenance = ${JSON.stringify({ submission: result.raw })}::jsonb
        where job_id = ${job.id}::uuid and attempt_number = ${attemptNumber}
      `;
      await tx`
        update production.scene_generation_jobs
        set status = 'submitted', selected_provider = ${route.provider}, selected_route_key = ${route.routeKey},
            provider_request_id = ${result.requestId}, provider_status = ${result.status},
            status_url = ${result.statusUrl}, cancel_url = ${result.cancelUrl},
            estimated_cost_cents = ${route.expectedCostCents}, submitted_at = now(),
            claimed_by = null, claimed_at = null, heartbeat_at = null,
            available_at = now() + interval '10 seconds', updated_at = now()
        where id = ${job.id}::uuid and claimed_by = ${workerId}
      `;
    });

    await markHealth(route.provider, route.routeKey, true, latencyMs);
    await emit(job.organization_id, "scene.generation.submitted", job.id, {
      provider: route.provider,
      route_key: route.routeKey,
      provider_request_id: result.requestId,
      attempt_number: attemptNumber,
    });
    return { action: "submitted", provider: route.provider, route_key: route.routeKey, provider_request_id: result.requestId };
  } catch (error) {
    const message = errText(error);
    await sql`
      update production.scene_generation_attempts
      set provider_status = 'submit_failed', completed_at = now(), rejection_reason = ${message}
      where job_id = ${job.id}::uuid and attempt_number = ${attemptNumber}
    `.catch(() => {});
    await markHealth(route.provider, route.routeKey, false, Date.now() - started, message).catch(() => {});
    throw error;
  }
}

async function reconcile(job: Job, workerId: string) {
  if (job.selected_provider !== "higgsfield") throw new Error(`provider_reconcile_not_implemented:${job.selected_provider ?? "none"}`);
  if (!job.provider_request_id || !job.selected_route_key) throw new Error("provider_request_identity_missing");

  const started = Date.now();
  const result = await getHiggsfieldRequestStatus(job.provider_request_id);
  const latencyMs = Date.now() - started;

  await sql`
    update production.scene_generation_attempts
    set provider_status = ${result.status}, result_payload = ${JSON.stringify(result.raw)}::jsonb,
        provenance = provenance || ${JSON.stringify({ last_status_poll_at: new Date().toISOString() })}::jsonb
    where job_id = ${job.id}::uuid and attempt_number = ${job.attempt_count}
  `;

  if (!result.terminal) {
    await sql`
      update production.scene_generation_jobs
      set status = 'processing', provider_status = ${result.status},
          claimed_by = null, claimed_at = null, heartbeat_at = null,
          available_at = now() + interval '10 seconds', updated_at = now()
      where id = ${job.id}::uuid and claimed_by = ${workerId}
    `;
    return { action: "processing", provider_status: result.status };
  }

  if (result.status === "completed") {
    await sql.begin(async (tx) => {
      await tx`
        update production.scene_generation_attempts
        set provider_status = ${result.status}, completed_at = now(), result_payload = ${JSON.stringify(result.raw)}::jsonb,
            accepted = null
        where job_id = ${job.id}::uuid and attempt_number = ${job.attempt_count}
      `;
      await tx`
        update production.scene_generation_jobs
        set status = 'completed', provider_status = ${result.status}, result_payload = ${JSON.stringify(result.raw)}::jsonb,
            completed_at = now(), claimed_by = null, claimed_at = null, heartbeat_at = null, updated_at = now()
        where id = ${job.id}::uuid and claimed_by = ${workerId}
      `;
    });
    await markHealth(job.selected_provider, job.selected_route_key, true, latencyMs);
    await emit(job.organization_id, "scene.generation.completed", job.id, {
      provider: job.selected_provider,
      route_key: job.selected_route_key,
      provider_request_id: job.provider_request_id,
      qa_pending: true,
    });
    return { action: "completed", provider_status: result.status, qa_pending: true };
  }

  const error = `provider_terminal_status:${result.status}`;
  await sql`
    update production.scene_generation_attempts
    set provider_status = ${result.status}, completed_at = now(), result_payload = ${JSON.stringify(result.raw)}::jsonb,
        accepted = false, rejection_reason = ${error}
    where job_id = ${job.id}::uuid and attempt_number = ${job.attempt_count}
  `;
  await markHealth(job.selected_provider, job.selected_route_key, false, latencyMs, error);
  throw new Error(error);
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return new Response("Method Not Allowed", { status: 405 });
  if (workerSecret && req.headers.get("x-worker-secret") !== workerSecret) {
    return new Response("forbidden", { status: 403 });
  }

  try {
    const body = await req.json().catch(() => ({}));
    const limit = Math.max(1, Math.min(Number(body.limit ?? 1), 10));
    const workerId = `scene-generation-worker:${crypto.randomUUID().slice(0, 8)}`;
    const results: Array<Record<string, unknown>> = [];
    let completed = 0;
    let failed = 0;

    for (let i = 0; i < limit; i++) {
      const claimed = await sql<Job[]>`
        select id::text, organization_id::text, status, requirements, input_payload,
               selected_provider, selected_route_key, provider_request_id, provider_status,
               attempt_count, max_attempts, cost_ceiling_cents, retry_budget_cents
        from production.claim_scene_generation_job(${workerId})
      `;
      if (!claimed.length) break;
      const job = claimed[0];

      try {
        const result = job.status === "submitting"
          ? await submit(job, workerId)
          : await reconcile(job, workerId);
        completed++;
        results.push({ job_id: job.id, ok: true, ...result });
      } catch (error) {
        failed++;
        const message = errText(error);
        const release = await sql<Array<{ release_scene_generation_job: Record<string, unknown> }>>`
          select production.release_scene_generation_job(${job.id}::uuid, ${workerId}, ${message}, 60)
        `.catch(() => []);
        results.push({ job_id: job.id, ok: false, error: message, release: release[0]?.release_scene_generation_job ?? null });
        await emit(job.organization_id, "scene.generation.failed", job.id, { error: message }).catch(() => {});
      }
    }

    return Response.json({ worker_id: workerId, claimed: completed + failed, completed, failed, results });
  } catch (error) {
    return Response.json({ error: errText(error) }, { status: 500 });
  } finally {
    await sql.end({ timeout: 1 }).catch(() => {});
  }
});
