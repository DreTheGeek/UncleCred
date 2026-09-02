# HARVEST MAP: what FDS pulls from where

Rule: take the winner, cite the path, MAKE IT BETTER on the way in. Raw copies are reference; packages/ is the deliverable.

## From DreTheGeek/laseanpickens (the DRE content engine, live in Supabase project mbahmbszfbttnctcfzar)
| Organ | Source | Lands in |
|---|---|---|
| Content data model | dre_media schema: content_ideas (41 cols), content_calendar, episodes, scripts, clips, takes, assets, asset_versions, media_jobs, pipeline_stages, pipeline_runs, stage_gate_policies, stage_gate_evaluations, creative_evaluations, creative_lineage, visual_characters (prohibited_changes, reference_assets), visual_environments, visual_props, visual_styles, platform_posts, publishing_jobs, distribution_packages, content_metrics, claim_ledger, capture_checks, hooks, titles, thumbnails | supabase/migrations on the 7 schema split (canon, studio, production, publishing, analytics) |
| Intelligence and learning | dre_intelligence: taste_events, preference_signals, performance_hypotheses, performance_observations, learning_queue, showrunner_constitutions, audience_simulations, revision_events | schema intelligence |
| Knowledge and memory | dre_knowledge: documents, document_chunks, memories. pgmq q_dre_embeddings, q_dre_content_learning. dre-embed-worker, process-embedding-queue, kaldr-knowledge-ingest | schema knowledge |
| Gates | supabase/functions/kaldr-content-api: package-quality.ts, voice-check.ts, platform-rules.ts, topic-fatigue.ts, series.ts, production-brief.ts (all with tests) | packages/qa-gate (script and package level) |
| Planner | kaldr-content-api/index.ts actions: content_plan, today_planning, generate_today_plan, get_content_package, accept_content_package, decide_episode, hook_plan, filming_plan, record_content_feedback. _shared/content-formats.ts (5 lanes, allocateMix), filming-setups.ts | packages/showrunner |
| Worker spine | kaldr-worker-api (gate-evaluator.ts), dre_system.autonomy_sweep, advance_media_assembly_lines, recover_media_jobs, recover_pipeline_stages | workers/ (re expressed as Trigger.dev tasks; keep the SQL functions as the state machine) |
| Production | dre-production-compile, dre-production-room, kaldr-cutting-room, kaldr-filming-api | packages/production |
| Analytics sync | dre-analytics-sync, dre-youtube-analytics, dre-instagram-insights, dre-tiktok-display | packages/analytics |
| Auth and MCP | _shared/owner-auth.ts, token-auth.ts, dre_system.mcp_oauth_clients, mcp_auth_codes, mcp_access_tokens, supabase/functions/kaldr-mcp, migrations/20260828_kaldr_mcp_oauth.sql, docs/CONNECT-AI.md | packages/connectivity |
| Budget | ai-budget-gate, public.lp_ai_budget | schema system |

## From DreTheGeek/kaldr-core
| Organ | Source | Lands in |
|---|---|---|
| Doctrine | doctrine/kaldr-build-system (v6.4), assets: confirm-destructive.tsx, support-widget.tsx, whats-new.tsx, status-page.tsx, first-run.tsx, ops-bot-telegram.ts, composio.ts, doctrine-ci.mjs, ai-tells-scanner.mjs, portal-shell-template.html | .claude/ and apps/studio shell |
| Job queue | harvest/Agentic-Agency/worker/src/crew.ts (agent_jobs spine) | reference for Trigger.dev task shapes |
| Money | harvest/clipform stripe lib, harvest/myreceptionistnet dunning-worker, kaldr-money-layer skill | packages/money (later, when the studio bills clients) |
| Events and audit | harvest/ai-junkies-university src/lib/audit.ts, queries/events.ts | schema system: system_events immutable ledger |
| Tenant | harvest/Clockwork lib/tenant.server.ts, tenant-guard.ts | one org per universe from day one |
| Admin | harvest/ai-junkies-university admin-auth, admin-openapi; harvest/Pulpit api/admin | apps/studio admin |
| Self healing seed | harvest/thickandfit .github/workflows/support-fix.yml, agent-guard.yml | .github/workflows |
| Knowledge | knowledge/skills (kb-content, kb-algorithms, kb-video-production, kb-design, kb-prompting, kb-smart-systems, kb-credit-repair from local) | embedded into schema knowledge at ingest |

## New organs (exist nowhere yet)
1. packages/canon: characters, character_generation_profiles, loras, wardrobe, voice identities, locations, props, relationships, canon_facts with supersession, universes.
2. packages/generation-router: ai_models registry, GenerationRouter (image, video, talking head, voice, utility), providers fal, replicate, runway, heygen, hedra, elevenlabs, benchmark lab.
3. packages/qa-gate media tier: frame sampler, identity and style similarity, vision LLM judge, repair router, retry budgets, qa_scorecards.
4. packages/assembly: FFmpeg plus Remotion compositions (captions, lower thirds, intro, outro, CTA, credit score graphics), packaging engine per platform.
5. packages/publisher: Blotato adapter first, YouTube and IG Graph adapters second, TikTok Direct Post after audit.
6. packages/grounding: credit claim extraction, authority ranked retrieval, verify, rewrite loop, compliance blocklist and disclosure injector.
