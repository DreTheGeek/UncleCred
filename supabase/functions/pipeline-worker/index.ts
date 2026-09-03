// Pipeline worker: claim one stage, do the work, complete it, emit to the ledger.
//
// Phase 01 gate wants proof that an edge function on cron can claim a pipeline_stage
// and complete it. At v1 the work step is a deliberate no-op, so this proves the
// state machine round trip and nothing else. Real stage handlers register in HANDLERS
// as Phase 04 lands them; the claim, complete, emit, and error paths do not change.
//
// Contract:
//   POST, guarded by x-worker-secret, same as embed-worker and process-embedding-queue.
//   Body: { worker_class?: string, limit?: number }
//   Returns: { claimed, completed, failed, results }
//
// system.claim_pipeline_stage(p_worker_class, p_worker_id) returns SETOF studio.pipeline_stages
//   (202609020006_functions.sql:791). It takes exactly one stage, FOR UPDATE SKIP LOCKED,
//   so concurrent invocations never claim the same row.
// system.complete_pipeline_stage(p_stage_id, p_worker_id, p_output) returns jsonb
//   (202609020006_functions.sql:807). It RAISES if an active studio.stage_gate_policies row
//   exists for the stage_code and no matching stage_gate_evaluations row exists for this
//   attempt. A no-op proof stage must therefore use a stage_code with no active gate policy.
//
import 'jsr:@supabase/functions-js/edge-runtime.d.ts'
import postgres from 'https://deno.land/x/postgresjs@v3.4.5/mod.js'

const dbUrl = Deno.env.get('SUPABASE_DB_URL')
if (!dbUrl) throw new Error('SUPABASE_DB_URL unavailable')
const workerSecret = Deno.env.get('WORKER_SECRET')
const sql = postgres(dbUrl, { prepare: false })

function errText(e: unknown) {
  if (e instanceof Error) return `${e.name}: ${e.message}`
  try { return JSON.stringify(e) } catch (_) { return String(e) }
}

// Stage handlers register here as they land. A stage_code with no handler is a no-op,
// which is what the Phase 01 gate exercises.
type Stage = { id: string, organization_id: string, stage_code: string, input: Record<string, unknown> }
const HANDLERS: Record<string, (s: Stage) => Promise<Record<string, unknown>>> = {}

async function runStage(stage: Stage): Promise<Record<string, unknown>> {
  const handler = HANDLERS[stage.stage_code]
  if (!handler) return { noop: true, stage_code: stage.stage_code, note: 'no handler registered, completed as no-op' }
  return await handler(stage)
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') return new Response('Method Not Allowed', { status: 405 })
  if (workerSecret && req.headers.get('x-worker-secret') !== workerSecret) {
    return new Response('forbidden', { status: 403 })
  }
  try {
    const body = await req.json().catch(() => ({}))
    const workerClass = String(body.worker_class ?? 'noop')
    const limit = Math.max(1, Math.min(Number(body.limit ?? 1), 10))
    const workerId = `pipeline-worker:${crypto.randomUUID().slice(0, 8)}`

    const results: Array<Record<string, unknown>> = []
    let completed = 0
    let failed = 0

    for (let i = 0; i < limit; i++) {
      const claimed = await sql<Stage[]>`
        select id::text, organization_id::text, stage_code, input
        from system.claim_pipeline_stage(${workerClass}, ${workerId})
      `
      if (!claimed.length) break
      const stage = claimed[0]

      try {
        const output = await runStage(stage)
        const [{ complete_pipeline_stage: result }] = await sql`
          select system.complete_pipeline_stage(
            ${stage.id}::uuid, ${workerId}, ${JSON.stringify(output)}::jsonb
          )
        `
        completed++
        results.push({ stage_id: stage.id, stage_code: stage.stage_code, ok: true, result })
        await sql`
          select system.emit_event(
            ${stage.organization_id}::uuid, 'pipeline.stage.completed', 'studio.pipeline_stages',
            ${stage.id}::uuid,
            ${JSON.stringify({ stage_code: stage.stage_code, worker_class: workerClass, worker_id: workerId, output })}::jsonb,
            'pipeline-worker'
          )
        `
      } catch (e) {
        // Release the claim so the stage retries instead of sitting in running forever.
        // attempts was already incremented by claim_pipeline_stage, so max_attempts still governs.
        failed++
        const message = errText(e)
        await sql`
          update studio.pipeline_stages
          set status = case when attempts >= max_attempts then 'failed' else 'queued' end,
              claimed_by = null, claimed_at = null, heartbeat_at = null,
              error_code = 'WORKER_ERROR', error_message = ${message},
              available_at = now() + interval '1 minute', updated_at = now()
          where id = ${stage.id}::uuid and claimed_by = ${workerId}
        `.catch(() => {})
        results.push({ stage_id: stage.id, stage_code: stage.stage_code, ok: false, error: message })
        await sql`
          select system.emit_event(
            ${stage.organization_id}::uuid, 'pipeline.stage.failed', 'studio.pipeline_stages',
            ${stage.id}::uuid,
            ${JSON.stringify({ stage_code: stage.stage_code, worker_class: workerClass, worker_id: workerId, error: message })}::jsonb,
            'pipeline-worker'
          )
        `.catch(() => {})
      }
    }

    return Response.json({ worker_id: workerId, worker_class: workerClass, claimed: completed + failed, completed, failed, results })
  } catch (e) {
    return Response.json({ error: errText(e) }, { status: 500 })
  } finally {
    await sql.end({ timeout: 1 }).catch(() => {})
  }
})
