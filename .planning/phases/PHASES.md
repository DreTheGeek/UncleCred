# PHASES (AI timelines: each phase is one to three focused Claude Code sessions, not weeks)

Order never changes. Every phase ends with VERIFICATION.md evidence, doctrine-ci green, zero em dashes.

## 01 Spine
- New Supabase project, 7 schema split: platform, canon, studio, production, publishing, intelligence, knowledge, system. RLS on every table including vectors.
- Port dre_media, dre_intelligence, dre_knowledge, dre_system into the split. Migrations written fresh; laseanpickens migrations are the reference.
- api_keys, /api/v1, remote MCP (reuse kaldr-mcp OAuth), system_events ledger, ai_budget gate, Langfuse wired.
- pg_cron jobs registered for autonomy_sweep, pipeline_advance, recovery, embedding queue. One edge function worker claims a pipeline_stage and completes it.
- Gate: login on a live URL, MCP answering from Claude, one pipeline_stage claimed and completed by an edge function on cron, one object written to Supabase Storage.

## 02 Canon and characters
- packages/canon tables and admin screens (kb-design loaded first, Boss frames as plates).
- Character bibles for Uncle Cred, Auntie APR, Repo Reggie, Mr. Denied, Funding Frank. Locations and props.
- Generation router with fal, replicate, runway, hedra, heygen, elevenlabs providers. ai_models registry seeded from RESEARCH.md.
- LoRA pipeline: dataset curation, train on fal, version, store. Turnaround and expression sheets via flux-general ControlNet.
- Voice: one ElevenLabs voice_id per character, locked.
- Gate: five characters with locked turnarounds, expression sheets, LoRA v1, and voice. Benchmark lab scores stored for scenes A through E.

## 03 Showrunner and grounding
- Port the planner and gates from kaldr-content-api into packages/showrunner and packages/qa-gate. Model routing per role.
- packages/grounding: claim extraction, authority ranked retrieval over the credit KB, verify loop, compliance blocklist, disclosure injector.
- Writers room outputs JSON only (episode blueprint: scenes, shots, dialogue, beats, clip points).
- Gate: one Uncle Cred episode blueprint generated, every claim verified or rewritten, blocklist proven by test.

## 04 Production line
- Pipeline stages: blueprint to shots to generation to QA to repair to assembly to episode QA to READY FOR LASEAN, each a pipeline_stage row advanced by cron and edge workers.
- Media QA gate with scorecards, repair router, retry budget 4.
- Render API templates: captions from word level Whisper, lower thirds, intro, outro, CTA with {PRODUCT_NAME} token, credit graphics.
- Packaging engine: master to TikTok, Reels, Shorts, Facebook, LinkedIn variants with per platform caption, hook, CTA, safe zones.
- Gate: one full episode rendered end to end without a human touching a vendor dashboard, QA scorecards persisted for every shot.

## 05 Publish and learn
- Blotato adapter, publishing_jobs, scheduled posting, AI disclosure applied per platform.
- Analytics pullback (YouTube Analytics, IG Insights, Blotato, CSV import for the rest), raw rows never summaries.
- Learning loop: observation, hypothesis, evidence, confidence, policy. Experiments table.
- Gate: first episode live on all five platforms with disclosure, metrics landing in analytics, one learning row produced.

## 06 Proof and hardening
- Operator reality audit, chaos harness, self healing workflow, cost per episode dashboard, ROI per character.
- Approval ladder: enable auto approve above threshold when the data supports it.
- Lawyer sign off on guardrails and state CSO status before public launch.
