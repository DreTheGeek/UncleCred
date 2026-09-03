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

## Phase 01 gate items closed (Claude Code, 2026-09-03)

### CLOSED: embedding backfill, gate count(embedding) = count(*)
Measured directly against knowledge.document_chunks:
    count(*)                7424
    count(embedding)        7424
    embedding IS NULL          0
    embedding_dimensions <> 384    0
    embedding_model <> gte-small   0
    embedded_at IS NULL            0
Gate MET. 38 knowledge.embedded rows in the ledger. Every vector came from the same
gte-small model that the column was sized for, so nothing in the table is a different
embedding space from anything else.

Rate history, for whoever tunes the cron later: 366 at 02:58, 573 at 03:29 (6.5/min),
2151 at 04:35 (24.1/min over that segment), 7424 complete. The slow early window is real
and worth understanding before the next large ingest, but it resolved on its own.

### CLOSED: proof object in Supabase Storage
    canon/uncle_cred/face_master_001.jpg     197,449 bytes  sha256 4774ea1f3581c96c6d72643da2e88a25d2892a1d0a50516f868b35e7ae118f43
    canon/uncle_cred/reference_set_v1.zip  7,118,838 bytes  sha256 c38b7bd740764ead35c93af45b411e4596b9e13d43634d69b29810332fe32694
Both recorded in canon and verified through the accessors the ruling asked for:
    reference_assets->>'face_master'    canon/uncle_cred/face_master_001.jpg
    reference_assets->>'reference_set'  canon/uncle_cred/reference_set_v1.zip
Ledger event 16, canon.reference_set.stored.

Shape change on record: reference_assets was a 7 element ARRAY holding curation history
(two rejected candidate rounds, the Boss photo keep and exclude lists including
excluded_minor_in_frame, and the twists versus low cut ruling). The ->> accessors require
an object, so the column is now an object and the original array is preserved verbatim at
reference_assets.history. Anything that expected an array must read .history.

Operational note: supabase-js failed the 7MB zip upload with a bare "fetch failed". The
direct storage REST POST with the same key succeeded first attempt. Use REST for large
objects.

### BLOCKED: one pipeline_stage claimed and completed
Stage code chosen for the proof: intake, worker_class media. It is stage 1 of the 14 that
system.start_media_assembly_line lays down, the only one created queued (the rest are
blocked behind depends_on_stage_code), and studio.stage_gate_policies is empty so
complete_pipeline_stage cannot raise the quality gate exception.

The seed cannot run. See the schema defect section below. studio.assets row
8dabdd79-9d7c-4967-9c55-f4b292797bf8 (asset_type reference_image, pointing at the canon
face master) is already inserted and waiting; start_media_assembly_line is idempotent on
re-run, so the seed is a single call once the defect is fixed.

### DEFECT FOUND: four event tables have no identity on id
studio.pipeline_events, studio.content_lifecycle_events, system.automation_events and
system.workflow_events all declare "id bigint not null" with no default and no identity.
Every insert fails 23502. The port from laseanpickens dropped the identity clause;
system.system_events was written fresh in 202609020010 and is unaffected.

Impact is not one call site. system.start_media_assembly_line, system.complete_pipeline_stage
and system.advance_media_assembly_lines all write studio.pipeline_events, so the media
assembly line cannot be started, advanced, or completed. This is why the Phase 01 pipeline
gate cannot be reached, independent of whether pipeline-worker is deployed.

Fix written as supabase/migrations/202609030000_fix_event_table_identity.sql. All four
tables verified empty first, so an identity starting at 1 cannot collide. Needs the
Composio path; no control plane access here.

### WRITTEN, NOT DEPLOYED: remote MCP
supabase/functions/mcp/index.ts. JSON-RPC 2.0 over POST, authenticated with the same uc_
API key as the REST API per API-STANDARD, so there is no second auth system. Deliberately
not a port of laseanpickens kaldr-mcp, which brings its own OAuth tables that UncleCred
does not need.

Five tools: search_credit_knowledge (Supabase.ai gte-small embeds the query, pgvector
cosine over the 7,424 embedded chunks, same model that wrote the column), list_characters,
get_character, studio_status, recent_events. Every tools/call writes an mcp.tool.called
ledger row. Unauthenticated requests are refused before the body is parsed and the key is
never echoed or logged.

### WRITTEN AND VERIFIED, NOT DEPLOYED: apps/studio
Next 15 App Router, TypeScript strict, Tailwind, @supabase/ssr. Tokens and shell taken from
apps/studio-mockups; the mockups were not shipped as the app.

    tsc --noEmit   exit 0
    next build     exit 0, six routes, middleware 93kB
    npm audit      0 vulnerabilities (postcss forced to 8.5.26 across the tree; next pins
                   8.4.31 internally, which carries a high advisory)
    em dashes      0

Login is one email box and one button, no password field and no signup page. getUser
everywhere, never getSession. Anon key only; the service role key never enters the bundle.
Home routes to /review when episodes are waiting and /command-center otherwise. Three
one-tap decisions, each writing the episode row and one ledger event.

Two findings recorded in code rather than guessed at:
1. There is no READY_FOR_LASEAN value. platform.work_status is idea, research, ready,
   scheduled, in_progress, blocked, review, approved, completed, published, archived,
   killed. The app maps to "review", the enum value meaning awaiting a human, matching
   pipeline stage 12 named human_review. One constant in lib/constants.ts. The alternative
   is studio.episodes.production_state, free text, default "insight".
2. A valid session with no platform.organization_members row reads zero rows from every
   table, which is indistinguishable from an empty studio. There is a dedicated empty state
   saying RLS is working and onboarding step 1 creates the row, so first login does not
   look like a broken app.

Blocked on NEXT_PUBLIC_SUPABASE_ANON_KEY, which is not obtainable without control plane
access. That also blocks attaching content.unclecred.app, whose DNS already resolves to
Vercel but which no project currently claims.

## CLOSED: live URL, studio deployed (2026-09-03)

https://content.unclecred.app is serving apps/studio. Verified from outside:

    /login            200, <title>Uncle Cred Studio</title>, form renders
    /                 307 -> /login?next=%2F
    /command-center   307 -> /login?next=%2Fcommand-center
    /review           307 -> /login?next=%2Freview
    all five security headers present (CSP, X-Frame-Options DENY, X-Content-Type-Options,
    Referrer-Policy, Permissions-Policy)

Before this, the same domain served apps/studio-mockups. Proof it was the mockups and not
the app: /01-command-center and /02-review-room returned 200 while /login, /review and
/command-center returned 404, and every number on that screen was hardcoded HTML against a
database holding 0 episodes, 0 pipeline_runs, 0 pipeline_stages, 0 clips, 0 platform_posts.

Three defects had to be cleared to get here:
1. Root vercel.json had framework null, an empty buildCommand and outputDirectory
   apps/studio-mockups. The production build finished in 31ms having built nothing.
2. The project's stored Output Directory setting also pointed at apps/studio-mockups, so
   the deploy failed after a successful Next build. apps/studio/vercel.json overrides it.
3. NEXT_PUBLIC_ values are not visible to the build on this project, so the inlined
   constants were undefined and middleware threw MIDDLEWARE_INVOCATION_FAILED on every
   route. lib/supabase/env.ts now resolves from any provisioned spelling at runtime, and
   the layout hands the browser its config as application/json.

Deployment path caveat: production is currently updated by `vercel deploy --prod` from
apps/studio. Git pushes still trigger a build from the repo root, which fails Next
detection ("No Next.js version detected") and leaves production untouched. Setting the
project Root Directory to apps/studio makes git deploys use apps/studio/vercel.json and
behave identically. There is no API for that setting; it is a dashboard field.

## PHASE 01 GATE: COMPLETE (2026-09-03)

Every gate item from phases/PHASES.md 01, with evidence.

### Login on a live URL
https://content.unclecred.app serving apps/studio. /login 200 and renders; /, /command-center
and /review each 307 to /login?next=...; all five security headers present.

### MCP answering
supabase/functions/mcp deployed and answering JSON-RPC 2.0 on the uc_ API key:
    initialize   200  serverInfo {"name":"unclecred-studio","version":"0.1.0"}  protocol 2024-11-05
    tools/list   200  search_credit_knowledge, list_characters, get_character, studio_status, recent_events
    bad key      401  refused before the body is parsed
    studio_status            isError:false  characters 5, chunks_embedded 7424/7424, ledger 49
    search_credit_knowledge  isError:false  sim 0.9250 on "The BEST Day to Pay Your Credit Card"
    get_character            isError:false  Uncle Cred, lora UNCLECRED_V1, voice b2DJJJVITlSI2seQjLf5
    recent_events            isError:false  mcp.tool.called rows landing in the ledger
Bug found and fixed during verification: supabase-js rpc() is thenable but not a Promise, so
the audit write's .catch() threw TypeError after every successful tool call and the handler
reported isError:true on work that had actually succeeded.

### One pipeline_stage claimed and completed by an edge function on cron
    intake      completed  claimed_by pipeline-worker:proof01     (manual RPC round trip)
    probe       completed  claimed_by pipeline-worker:a074aa53    (cron, deployed function)
    transcribe  queued     worker_class speech, no worker exists yet
    cron uc-pipeline-work, 15 seconds, succeeded
    studio.pipeline_events 1 pipeline_created, 2 and 3 stage_completed
The worker id on probe was generated inside the edge function, so that stage was claimed and
completed autonomously, not by hand.

### One object in Supabase Storage
canon/uncle_cred/face_master_001.jpg and canon/uncle_cred/reference_set_v1.zip, both sha256
verified, both recorded in studio.visual_characters.reference_assets.

### Embeddings
7,424 of 7,424. count(embedding) = count(*). Zero nulls, all gte-small/384, all stamped.

### pg_cron
10 jobs active. 3,751+ runs, zero failures.

### RLS
151 tables, RLS on all, 463 policies of which 436 are owner_*, gated on platform.is_org_member().

## Retrieval layer applied
knowledge.match_chunks(uuid, vector(384), text, int, float8, text[], text[]) is live.
Hybrid vector + full text via reciprocal rank fusion, authority weighted, superseded
documents excluded. Verified live: for "when should I pay my credit card to lower
utilization" the top hits are sim 0.9250 / 0.9247 / 0.9185 with both the vector and the
text halves scoring non zero on the same rows, correctly landing in credit-fundamentals.

## Known gap carried into Phase 02
The knowledge base is weighted toward internal operations SOPs rather than viewer facing
credit education: Phase_1_R1_Disputes_Ideal_Full (377 chunks), BDCR_Full_Operational_Process
(330), 03_Damage_Assessment_Reference_v7 (136). Layer split is 5,322 lesson to 2,102 source.
Grounding will pass on SOP text that Uncle Cred cannot teach from. Either curate, or
downgrade authority on the SOP documents; match_chunks already weights by authority
(canonical 1.30 down to unverified 0.50), so a downgrade is sufficient.
