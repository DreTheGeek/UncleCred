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
