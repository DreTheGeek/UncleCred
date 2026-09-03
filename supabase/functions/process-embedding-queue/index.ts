// Incremental embedding path: drains the pgmq queue 'dre_embeddings' with a 180 second
// visibility timeout, embeds each chunk, and deletes the message only after the write
// succeeds. A chunk already embedded, or whose row is gone, is treated as done rather
// than retried forever.
//
// Ported from DreTheGeek/laseanpickens supabase/functions/process-embedding-queue/index.ts.
// Changed on the way in: dre_knowledge.document_chunks becomes knowledge.document_chunks.
// The queue name stays 'dre_embeddings' because knowledge.enqueue_chunk_embedding()
// (202609020006_functions.sql:104) and pgmq.create in 202609020000 both use that name.
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
  return e instanceof Error ? `${e.name}: ${e.message}` : String(e)
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') return new Response('Method Not Allowed', { status: 405 })
  try {
    const body = await req.json().catch(() => ({}))
    const limit = Math.max(1, Math.min(Number(body.limit ?? 1), 4))
    const jobs = await sql`
      select msg_id::bigint, message
      from pgmq.read('dre_embeddings', 180, ${limit})
    `

    const completed: Array<{ msg_id: number, chunk_id: string }> = []
    const failed: Array<{ msg_id: number, chunk_id?: string, error: string }> = []

    for (const job of jobs) {
      const chunkId = job.message?.chunk_id as string | undefined
      try {
        if (!chunkId) throw new Error('queue message missing chunk_id')
        const rows = await sql`
          select id::text, content, embedding is not null as already_embedded
          from knowledge.document_chunks
          where id = ${chunkId}::uuid
          limit 1
        `
        if (!rows.length || rows[0].already_embedded) {
          await sql`select pgmq.delete('dre_embeddings', ${job.msg_id}::bigint)`
          completed.push({ msg_id: Number(job.msg_id), chunk_id: chunkId })
          continue
        }

        const vector = await model.run(rows[0].content, { mean_pool: true, normalize: true })
        const vectorText = JSON.stringify(vector)
        await sql`
          update knowledge.document_chunks
          set embedding = ${vectorText}::extensions.vector(384),
              embedding_model = 'gte-small',
              embedding_dimensions = 384,
              embedded_at = now()
          where id = ${chunkId}::uuid
        `
        await sql`select pgmq.delete('dre_embeddings', ${job.msg_id}::bigint)`
        completed.push({ msg_id: Number(job.msg_id), chunk_id: chunkId })
      } catch (e) {
        failed.push({ msg_id: Number(job.msg_id), chunk_id: chunkId, error: errText(e) })
      }
    }

    return Response.json({ requested: limit, found: jobs.length, completed, failed })
  } catch (e) {
    return Response.json({ error: errText(e) }, { status: 500 })
  } finally {
    await sql.end({ timeout: 1 }).catch(() => {})
  }
})
