// Backfill sweep: embeds any knowledge.document_chunks row still missing an embedding.
// process-embedding-queue is the incremental path; this is the sweep that drains a backlog.
//
// Ported from DreTheGeek/laseanpickens supabase/functions/dre-embed-worker/index.ts.
// Changed on the way in:
//   1. dre_knowledge.document_chunks becomes knowledge.document_chunks (7 schema split).
//   2. Returns 200 with a structured body on partial failure instead of only counting.
//   3. Emits system.emit_event once per invocation so the sweep is visible in the ledger.
// Embeddings use the edge runtime's built-in gte-small session. No external key.
//
// eslint-disable-next-line @typescript-eslint/triple-slash-reference
/// <reference path="../_shared/supabase-ai.d.ts" />
import 'jsr:@supabase/functions-js/edge-runtime.d.ts'
import postgres from 'https://deno.land/x/postgresjs@v3.4.5/mod.js'

const model = new Supabase.ai.Session('gte-small')
const dbUrl = Deno.env.get('SUPABASE_DB_URL')
if (!dbUrl) throw new Error('SUPABASE_DB_URL unavailable')
const sql = postgres(dbUrl, { prepare: false })

function errText(e: unknown) {
  if (e instanceof Error) return `${e.name}: ${e.message}`
  try { return JSON.stringify(e) } catch (_) { return String(e) }
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') return new Response('Method Not Allowed', { status: 405 })
  try {
    const body = await req.json().catch(() => ({}))
    const limit = Math.max(1, Math.min(Number(body.limit ?? 50), 200))
    const chunks = await sql`
      select id::text as chunk_id, content
      from knowledge.document_chunks
      where embedding is null
      order by created_at, chunk_index
      limit ${limit}
    `

    let embedded = 0
    const failures: Array<{ chunk_id: string, error: string }> = []
    for (const chunk of chunks) {
      try {
        const vector = await model.run(chunk.content, { mean_pool: true, normalize: true })
        const vectorText = JSON.stringify(vector)
        await sql`
          update knowledge.document_chunks
          set embedding = ${vectorText}::extensions.vector(384),
              embedding_model = 'gte-small',
              embedding_dimensions = 384,
              embedded_at = now()
          where id = ${chunk.chunk_id}::uuid
        `
        embedded++
      } catch (e) {
        failures.push({ chunk_id: chunk.chunk_id, error: errText(e) })
      }
    }

    const [{ remaining }] = await sql`
      select count(*)::bigint as remaining from knowledge.document_chunks where embedding is null
    `
    await sql`
      select system.emit_event(
        null::uuid, 'knowledge.embed_sweep', 'knowledge.document_chunks', null::uuid,
        ${JSON.stringify({ requested: limit, found: chunks.length, embedded, failed: failures.length, remaining: Number(remaining) })}::jsonb,
        'embed-worker'
      )
    `

    return Response.json({ requested: limit, found: chunks.length, embedded, remaining: Number(remaining), failures })
  } catch (e) {
    return Response.json({ error: errText(e) }, { status: 500 })
  } finally {
    await sql.end({ timeout: 1 }).catch(() => {})
  }
})
