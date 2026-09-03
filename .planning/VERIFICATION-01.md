# VERIFICATION: Phase 01 Spine (2026-09-02)

Evidence, not claims. Project pdficpdfrituqjzaleen (Supabase, us-west-2, Postgres 17.6).

## Applied and verified by query
- 151 tables across platform, studio, intelligence, research, knowledge, system. RLS enabled on 151 of 151.
- 304 foreign keys, 412 indexes, 2 views, 39 functions, 38 triggers, 29 policies (all 29 ported from source).
- pgmq queues dre_embeddings and dre_content_learning created.
- Extensions: vector, pgmq, pg_cron, pg_net, pgcrypto, citext, pg_trgm.
- PostgREST exposed schemas patched via Management API to include the eight studio schemas.
- Seed: platform.organizations row Kaldr Business Group (id 00000000-0000-0000-0000-000000000001), platform.universes row uncle_cred.
- system.system_events id 1: phase01.migrated, actor claude.

## Edge function api-v1 (deployed, verify_jwt off, version 2)
- GET /health -> 200 {"ok":true,"data":{"service":"UncleCred"}}
- GET /whoami with a minted uc_ key -> 200 with principal kind api_key, org id, scopes.
- GET /events?limit=3 with key -> 200, returns event id 1.
- Same key after revoke -> 401. Proof keys phase01-proof-1 through 4 are all revoked.

## Not yet done (gate items that need Boss accounts)
- Trigger.dev project and a green unclecred.hello run.
- R2 bucket and a proof object written by that run.
- Railway deploy of workers/ (image and config committed).
- Vercel deploy of the command center with a live login (Claude Code session).
- Owner RLS policies for authenticated users against platform.organization_members (tables are service_role only today).
- Remote MCP port from laseanpickens kaldr-mcp.

## Deviations from the written migrations
- 0000 gained citext, pg_trgm, schema grants, and pgmq queue creation after the first apply failed on citext and service_role lacked privileges on the new schemas.
- system.health_summary view moved to needs_review: it reads dre_api.api_clients which is cortex, not studio.
- api-v1 is deployed as a single self contained file (Composio deploy takes one file). Source of truth stays modular in the repo; sync before redeploy.

## Knowledge base (2026-09-02, later the same day)
- Imported from The Credit Brothers (ref avxyibhhcgbiutggxilr, ops.tcb_kb_*): 167 documents, 7,424 chunks across credit-fundamentals, credit-repair-diy, dispute-rounds, credit-cards-strategy, personal-funding, business-funding, case-monitoring-legal. Both layers kept (source and lesson; lesson chunk_index offset by 100000). Provenance in metadata.source_project.
- Trigger knowledge.enqueue_chunk_embedding fired: pgmq dre_embeddings depth 7,724. Embeddings are 0 of 7,424 until the embed worker edge function is deployed with an embedding key (Claude Code Phase 01 step, add it).
- Not imported yet: 1,728 untopic'd raw source docs (6,210 chunks, mixed subjects), 15 SOPs, the 8 non credit topics (travel, bank bonuses, team ops). BigBuildsAi corpus (13 kb_* pairs) left in place; the kb skills already in kaldr-core cover the same ground.
- Ledger: system_events knowledge.imported.

## Control plane pass (2026-09-03, through Composio, since the CLI account is outside the studio org)
- Storage buckets created: canon (private), renders (private), finals (public).
- pg_cron registered: uc-autonomy-sweep (1m), uc-pipeline-advance (1m), uc-content-learning (1m), uc-media-recovery (5m), uc-pipeline-recovery (5m), uc-embed-backfill (8s, limit 4), uc-embed-queue (30s, limit 3).
- Owner RLS: 436 owner_select / owner_insert / owner_update policies on every table with organization_id, gated on platform.is_org_member(). A platform.organization_members row for Boss's auth user is still needed and is created at onboarding step 1.
- Edge functions deployed: embed-worker and process-embedding-queue (ported from laseanpickens, knowledge schema, gte-small 384 dims, no external key, guarded by x-worker-secret, verify_jwt off).
- Finding: edge CPU budget caps the sweep at about 4 chunks per invocation (limit 8 hits WORKER_RESOURCE_LIMIT). Cron alone would take about a day. Backfill is therefore also being run out of band with the identical model (thenlper/gte-small, cosine 1.000 against an edge produced vector), writing vectors in batches of 120 from the opposite end of the table so the two do not collide. The cron jobs stay as the steady state.
- Ledger: knowledge.embedded events from the worker, ids 11 and 12 at time of writing.

## Independent verification of the control plane pass (Claude Code, 2026-09-03 03:26 UTC)

Method: service role key against PostgREST and the Storage API, plus unauthenticated
HTTP probes of the functions gateway. No control plane access was available, so three
claims below are marked NOT INDEPENDENTLY VERIFIABLE rather than confirmed.

### Confirmed
- Storage buckets: exactly three, `canon` (private), `renders` (private), `finals` (public).
  Matches the claim. Previous session read zero buckets, so this is a real change.
- Edge functions deployed and live. Probe method: GET returns 405 from a function that is
  deployed and rejecting the verb, versus a gateway `{"code":"NOT_FOUND"}` body when the
  function does not exist. Results:
    embed-worker             GET 405 Method Not Allowed        deployed
    process-embedding-queue  GET 405 Method Not Allowed        deployed
    api-v1                   GET 404 with its own ok/error envelope   deployed, routing 404
    pipeline-worker          GET 404 gateway NOT_FOUND         not deployed
    (control) a bogus name   GET 404 gateway NOT_FOUND         confirms the discriminator
- Worker secret guard is active. POST to embed-worker and process-embedding-queue with a
  valid service role bearer but no x-worker-secret returns 403 forbidden on both.
- Embedding backfill is running and the vectors are consistent: of the first 2000 embedded
  rows, embedding_model/dimensions is `gte-small/384` on 100 percent. No mixed-source drift
  is visible from the data plane.
- Ledger: system_events ids 11 and 12, event_type `knowledge.embedded`, actor `embed-worker`,
  at 03:07:34 and 03:08:03 UTC.
- Ledger: system_events id 10, `canon.lora.trained`, actor `script`, subject
  229f0ba2-4120-4791-b767-26b3260cccdd. LoRA UNCLECRED_V1 locked into
  studio.visual_characters.metadata.lora, 40 images, 1000 steps,
  fal-ai/flux-lora-fast-training. The read-modify-write merge preserved all 17 pre-existing
  metadata keys including `voice` (b2DJJJVITlSI2seQjLf5) and `likeness_consent`.

### Not independently verifiable from the data plane
- The seven uc-* pg_cron jobs. `cron.job` is not exposed through PostgREST.
- The 436 owner_* RLS policies. `pg_policies` is not exposed through PostgREST, and with no
  anon key available a behavioural RLS test could not be run either.
- Whether the out of band batch backfill is still running.

### Finding: the backfill is running at roughly one cron job's worth of throughput
Measured count(embedding) on knowledge.document_chunks:
    366 / 7424  at 02:58:00 UTC  (reported)
    549 / 7424  at 03:25:50 UTC  (measured)
    555 / 7424  at 03:26:34 UTC  (measured)
Segment rates: 6.6 per minute, then 8.2 per minute. Overall since 02:58, 6.6 per minute.
At that rate the remaining 6,869 chunks finish in about 17.3 hours, not the sharply
shorter time the batch pass was added to produce.

Arithmetic worth checking against the cron registry: uc-embed-queue at 30s with limit 3 is
6 per minute, which is almost exactly the observed rate. uc-embed-backfill at 8s with limit 4
would be about 30 per minute on its own. Observed throughput is consistent with the queue
drainer working and the backfill sweep contributing little or nothing. The ledger supports
this: only two `knowledge.embedded` rows exist, both inside a 30 second window at 03:07, and
none in the 18 minutes afterward during which 189 chunks were embedded, so whatever is doing
the bulk of the work is not emitting to the ledger.

Suggested next check, which needs control plane access: `select jobid, jobname, schedule,
active from cron.job where jobname like 'uc-%'`, then `select jobid, status, return_message,
start_time from cron.job_run_details order by start_time desc limit 20` to see whether
uc-embed-backfill is erroring on WORKER_RESOURCE_LIMIT rather than succeeding.

### Written this session, not deployed
- supabase/functions/pipeline-worker/index.ts. Claims one stage via
  system.claim_pipeline_stage, runs a registered handler or completes as a no-op when none is
  registered, completes via system.complete_pipeline_stage, emits pipeline.stage.completed.
  On handler error it releases the claim back to queued (or failed at max_attempts) and emits
  pipeline.stage.failed, so a crashed stage never sits in running forever.
  Deploy is blocked: the CLI Supabase account still cannot see project pdficpdfrituqjzaleen
  (`supabase functions list --project-ref pdficpdfrituqjzaleen` returns 403).

### Gate items still open after this pass
- No object has been written to any of the three buckets yet. All three are empty.
- studio.pipeline_stages is 0 rows, so nothing exists for pipeline-worker to claim. Seeding a
  proof stage needs a pipeline_run_id and a source_asset_id, both NOT NULL, and a stage_code
  with no active studio.stage_gate_policies row, since complete_pipeline_stage raises when a
  policy exists without a matching stage_gate_evaluations row for the attempt.
- No login exists. platform.organization_members has no row for a Boss auth user, so the
  owner_* policies would return zero rows to a real session even once one is created.
- Remote MCP is still not ported from laseanpickens kaldr-mcp.
