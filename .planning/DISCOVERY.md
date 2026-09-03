# Discovery Summary: UncleCred

Written 2026-09-03 in Claude Code session 1, per KICKOFF.md ("write .planning/DISCOVERY.md from DECISIONS.md").

Source key on every line: D = DECISIONS.md, R = RESEARCH.md, S = STORY-BIBLE.md,
O = ONBOARDING.md, H = HARVEST-MAP.md, V = VERIFICATION-01.md, P = phases/PHASES.md.
OPEN means the doctrine template requires a value that no locked decision supplies.
Nothing here is invented to fill a blank.

Doctrine note: the doctrine calls this file DISCOVERY-SUMMARY.md. KICKOFF.md names it
DISCOVERY.md, so it ships under the name KICKOFF asked for. See the version note at the end.

## Product Identity
- Product: Uncle Cred (two words everywhere a human reads it). (D)
- Codename: unclecred. Repo slug and code identifiers stay UncleCred / unclecred. (D)
- Company: Kaldr Business Group, platform.organizations id 00000000-0000-0000-0000-000000000001. (V)
- Brand positioning: an autonomous studio that produces a serialized credit drama and publishes it, where the operator only approves. (D click law, S)

## Target User
Two distinct users. The doctrine template assumes one, so both are recorded.
- Primary (the software's user): Boss, LaSean Pickens. Operator only. Nobody else logs in at v1. (D click law)
- Skill level: expert in the domain, deliberately shielded from the pipeline. "Click, click, click, output." (D)
- Device: OPEN. The click law implies mobile-first review, but no device target is locked. Needed for the Design Brief. (D)
- Audience (the show's viewers): people denied, people building credit, people funding a business. (O step 2)

## Core Problem
Credit education that reaches people does not exist as serialized drama, and producing it by hand does not scale. The studio writes, generates, QAs, assembles, publishes, and learns from a credit show without the operator touching a vendor dashboard. Every episode teaches exactly one verified credit truth and moves exactly one relationship. (S, P 04)

## Market
- Vertical approach: single vertical, one universe at v1. (D 7)
- Verticals: consumer credit repair and rebuilding, personal funding, business funding. (V knowledge base topics)
- Universe two (Year One, from the LaSeanPickens project) migrates in later. (D 2)

## Competitive Positioning
- #1 differentiator: real lead in a generated world. Uncle Cred is LaSean, 27, playing himself. Hero closeups can be the real man at zero generation cost. (D identity v2.0)
- #2 differentiator: it is a drama, not a feed. The season ending is written before episode one; canon facts carry across episodes and a continuity supervisor fails any episode that contradicts one. (S)
- #3 differentiator: every credit claim is verified against a 7,424 chunk credit knowledge base before it can ship, with a compliance blocklist and disclosure injector in the path. (V, D9, P 03)

## Monetization
- Model: the show sells {PRODUCT_NAME}, the credit and funding software. Every episode ends on a CTA frame. (D 10, O step 2)
- The studio itself is not billed to anyone at v1. packages/money lands later, when the studio bills clients. (H)
- Trial: OPEN, belongs to {PRODUCT_NAME}, not to the studio.
- Tiers: OPEN, same reason.

## Feature Scope
- MVP modules, in phase order: Spine, Canon and characters, Showrunner and grounding, Production line, Publish and learn, Proof and hardening. (P)
- Out of scope v1: Trigger.dev, Railway, Cloudflare R2, Remotion, own TikTok audit (v2 track), Year One as universe two. (D 3, D 4, D 7 assembly, D10 storage, D 6)

## AI Usage
- Showrunner, continuity, credit claim verifier: Fable 5.1. (D 9)
- Writers room, metadata: Sonnet 5. (D 9)
- Classification, extraction, vision QA judging: Haiku 4.5. (D 9)
- Image and LoRA: FLUX.1 dev and FLUX.2 via fal. flux-lora-fast-training for character LoRAs. (D 11, R)
- Video by shot type: Hedra Character-3 for dialogue closeups, Kling 3.0 for two shots and action, Veo 3.1 or Seedance for establishing, cheapest passing option for b roll. Sora is deprecated 2026-09-24 and is never wired. (D 4)
- Voice: ElevenLabs, one persistent voice_id per character, never regenerated. (D voice)
- Embeddings: gte-small, 384 dimensions, run inside the Supabase edge runtime. No external embedding key. (ported worker; knowledge.document_chunks column is extensions.vector(384))
- Law: no vendor call outside the GenerationRouter. JSON schemas (Zod) on every AI output. (KICKOFF laws)
- CONFLICT TO RESOLVE: doctrine non-negotiables say all model calls route through OpenRouter with no direct provider keys in products, while D 9 names providers directly and .env.example carries both ANTHROPIC_API_KEY and OPENROUTER_API_KEY. The GenerationRouter is the intended single seam. Which side of it OpenRouter sits on is not locked. Raise before Phase 03.

## Integrations
- Payments: none at v1. (H, money is later)
- SMS: none at v1.
- Email: none at v1.
- Voice: ElevenLabs. (D voice)
- Maps: not applicable.
- Calendar: not applicable.
- Storage: Supabase Storage, one bucket per asset class, public bucket behind the Supabase CDN for finals. No R2. (D10)
- Analytics: YouTube Analytics, IG Insights, Blotato, plus CSV import for what no API returns. (D analytics)
- Publishing: Blotato behind the Publisher adapter first, then native YouTube Data API and IG Graph adapters. (D 6)
- Generation gateways: fal.ai primary, Replicate secondary and utility, direct APIs for Runway, HeyGen, Hedra, ElevenLabs. (D 5)
- Observability: Langfuse self hosted for traces and cost. Sentry DSN reserved in .env.example. (D 9)
- Ops: Telegram ops bot reserved in .env.example. (H kaldr-core doctrine assets)

## API and Connectivity
- Build Profile: OPEN. This is a hard gate in the doctrine and no locked decision sets it. The shape on the ground is closest to Profile C (one off build, operator only), but "one org per universe from day one" (H) and the Year One migration (D 2) both point at multi-tenant. Boss must pick before Blueprint.
- Who holds API keys: operator only. Boss is the only principal at v1. (D click law)
- API Settings UI in dashboard: OPEN.
- API access pricing: not applicable at v1.
- External tools to connect: Claude via remote MCP. (P 01)
- OpenAPI docs: OPEN.
- MCP scope: OPEN. The MCP port from laseanpickens kaldr-mcp is still outstanding. (V not yet done)
- Shipped and proven already: system.api_keys with hash storage and revoke, edge function api-v1 with /health, /whoami, /events, key revocation returning 401. (V)

## Tech Stack
- Frontend: OPEN until Blueprint. Doctrine locks Path A vs Path B at Step 3, not here. The command center is a Vercel project; apps/studio-mockups are static HTML mockups, not the app. (D naming, repo)
- Styling: OPEN, follows the path decision.
- Backend: Supabase only. Postgres 17.6, us-west-2, project pdficpdfrituqjzaleen. Edge functions are the workers. pg_cron plus pgmq plus the SQL state machine is the workflow engine. No always on containers. (D 2, D 3, D 4, V)
- Hosting: Vercel. Command center at content.unclecred.app, CNAME already resolving to Vercel. (D naming)

## Reuse Sources
- Primary: DreTheGeek/laseanpickens (the DRE content engine) for the data model, gates, planner, worker spine, production, analytics, auth and MCP, budget. (H)
- Secondary: DreTheGeek/kaldr-core for doctrine, job queue shapes, events and audit, tenant guard, admin, self healing workflows, knowledge. (H)
- Priority: maximize. Rule is take the winner, cite the path, make it better on the way in. Raw copies stay reference; packages/ is the deliverable. (H)
- New organs that exist nowhere yet: canon, generation-router, qa-gate media tier, assembly, publisher, grounding. (H)

## Multi-Tenancy
- Model: one organization per universe from day one, ported from the Clockwork tenant guard. (H)
- Cross-company: no.
- Status: platform.organizations and platform.universes seeded. RLS enabled on 151 of 151 tables. (V)

## RBAC
- Roles: OPEN. Only service_role and a minted API key principal exist today. (V)
- Invite permissions: not applicable at v1, single operator.

## Auth
- Methods: OPEN. Doctrine baseline is email/password plus Google plus Apple OAuth. No decision recorded.
- MFA: not at baseline per doctrine.
- BLOCKER ON RECORD: owner RLS policies for authenticated users against platform.organization_members do not exist. Every table is service_role only today, so a real login cannot be authorized yet. (V not yet done)

## Compliance
- Show law: the show does not give legal advice. Education about how credit and funding work, never what a viewer should legally do. (D show law)
- CROA: no upfront fees, no guarantees, no claim of removing accurate information, 3 day cancellation language when promoting the paid service. (D9, R)
- FTC Reviews and Testimonials Rule: no character ever poses as a real customer or gives a results testimonial. (D9, R)
- AI disclosure auto appended, with double disclosure in the first 3 to 5 seconds when a post is both paid and AI. (D9)
- Hard blocklist: guaranteed, we will delete, erase your debt, instant approval, any numeric score promise, you should sue, file a lawsuit, legally you, your rights are, any statute citation delivered as instruction. (D9, D show law)
- Likeness and voice consent recorded in canon metadata. Confirmed present on the Uncle Cred row as metadata.likeness_consent. (D identity v2.0, verified live 2026-09-03)
- Lawyer signs off before the first public post. State CSO registration and bond status in TX, GA, CA, FL is a lawyer question, not research. (D9, STATE known unknowns)
- Data residency: us-west-2. (V)

## White-Label
- Need: none at v1. Single operator, single brand.
- Tier: not applicable.

## Mobile
- PWA: on by default per doctrine. Not opted out anywhere in DECISIONS.
- Native apps: none.
- Native phase: not scheduled.

## Design Intake
Doctrine hard gate, 11 fields. STATE records Step 2 as pending and kb-design loads before the
first pixel, so most of this is legitimately OPEN. What the identity board already locks is recorded.
- Aesthetic direction: OPEN. Step 2 pending. (STATE)
- Color temperature: OPEN, but the locked palette is warm and dark.
- Primary color: #641E2C, with #351018 as the deep companion. (D identity v1.0 board)
- Accent color: #9A633B and #B39562. Neutrals #F7F3EB and #161616. (D identity v1.0 board)
- Headline font vibe: OPEN.
- Scroll intensity: OPEN.
- Navigation pattern: OPEN. Home screen is the Review Room when anything waits on Boss, Command Center otherwise. (D click law)
- Build for: OPEN. See Target User device.
- Reference sites: none recorded. Boss supplies frames as reference plates. (STATE step 2)
- Banned patterns confirmed: OPEN, set at Step 2 from DESIGN-DOCTRINE.
- Voice/tone: Uncle Cred voice is locked as canon (ElevenLabs b2DJJJVITlSI2seQjLf5). UI copy tone is OPEN.

## Success Metrics
- Launch definition: first episode live on all five platforms with disclosure, metrics landing in analytics, one learning row produced. (P 05 gate)
- Activation: a new owner goes from login to an approved Episode 1 without typing anything except the product name, in under 20 minutes wall time. Over 20 minutes means a step is too heavy. (O gate)
- Retention: OPEN for the studio. Show side retention comes from the analytics pullback in Phase 05.
- Per phase: every phase ends with VERIFICATION.md evidence, doctrine-ci green, zero em dashes. (P)

## Timeline
- AI timelines only. Each phase is one to three focused Claude Code sessions, not weeks. (P)
- MVP: through Phase 04, one full episode rendered end to end with no human touching a vendor dashboard.
- Launch: Phase 05 gate, then Phase 06 lawyer sign off before public launch.
- Deadlines: none recorded.

## Team
- Builders: Claude Code sessions plus Boss.
- Operators: Boss, single operator. (D click law)

## Support
- Channel: OPEN.
- By tier: not applicable at v1.

## Affiliate
- Include: no.
- Commission: not applicable.

## Operator Panel
- Review Room: three actions per episode, one tap each. Approve, Send back, Kill. Approve schedules and publishes with no second screen. (D click law)
- Command Center: reports and offers one primary button. Never asks for input. (D click law)
- Character intake is a picker, not a form. (D click law)
- Any screen needing more than three taps to produce an output fails the operator reality audit and is redesigned. (D click law)
- Approval: READY FOR LASEAN on every episode. Auto approve threshold enabled only from QA data. (D 8)

## Onboarding
- Steps: 9. Welcome, The Show, The Cast, The Look, The Voice, The Story, The Platforms, The Rules, First Episode. (O)
- First actions: the only text field in the entire flow is {PRODUCT_NAME} at step 2. Everything else is a tap or a picker. Progress saves per step in platform.organizations.metadata.onboarding so a refresh resumes. (O)
- Ends inside the Review Room with Episode 1 waiting and approved. (O step 9)

## Notifications
- Channels: OPEN. Telegram ops bot is reserved in .env.example but no decision wires it.
- Preferences: OPEN.

## Analytics
- User analytics: not applicable, single operator.
- Content analytics: raw rows never summaries, into the analytics schema. CSV import accepted for retention curves, completion, TikTok watch time and reach, Facebook Reels reach. (D analytics)
- Exports: OPEN.

## Fort Knox Specifics
- Immutable event ledger: system.system_events, never updated, never deleted, update and delete revoked from authenticated and anon. Live and in use. (migration 202609020010, verified live)
- Audit on destructive actions: every destructive route uses confirm-destructive. (KICKOFF laws)
- Consent capture: likeness and voice consent recorded in canon metadata, confirmed present. (D identity v2.0)
- API keys: hash stored, prefix indexed, shown once, never logged, revocable. Proven by revoke returning 401. (V)
- Recording consent: not applicable, no calls recorded.
- Data retention: OPEN.
- No secrets in code, prompts, or the database. Env names live in .env.example only. (KICKOFF laws)

## Open items that block a downstream gate
1. Build Profile (Category 11) is unset and is a hard doctrine gate before Blueprint.
2. Design Intake is 8 of 11 fields OPEN. Step 2 must run with kb-design before any UI.
3. {PRODUCT_NAME} is unnamed and is required at onboarding step 2.
4. Auth method and owner RLS policies are undecided and unbuilt, so no real login exists.
5. OpenRouter versus direct provider keys is contradictory between doctrine and D 9.

## Version note
KICKOFF.md and STATE.md both say kaldr-build-system v6.4. The doctrine in
DreTheGeek/kaldr-core is v6.9. The kaldr-build-system skill installed locally is v3.2.
This document follows the v6.9 Discovery Summary template from kaldr-core, because
HARVEST-MAP names kaldr-core the doctrine source. Three way version drift is on record
and needs a ruling.
