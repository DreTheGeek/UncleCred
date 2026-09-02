# DECISIONS (locked 2026-09-02)

Source for each: R = Step 0 research, B = Boss default accepted, S = standard default.

## Stack intake (Assumption Law batch, accepted by Boss)
1. Repo: DreTheGeek/UncleCred. Spine from kaldr-core, organs from laseanpickens. (B)
2. Database: NEW Supabase project for the studio. LaSeanPickens project stays as is. Year One migrates in later as universe two. (B)
3. Workflow engine: Supabase native. pg_cron + pgmq + the SQL state machine already ported from the content engine (system.autonomy_sweep, advance_media_assembly_lines, claim_pipeline_stage, complete_pipeline_stage, recover_*). Edge functions are the workers. Boss ruling 2026-09-02: no Trigger.dev. Change trigger: a single vendor wait that cannot be modeled as a polled pipeline_stage. (B)
4. Workers: no always on containers. Everything runs as Supabase edge functions on cron. Heavy render (concat, mux, captions, overlays) is bought per job from a render API through the GenerationRouter instead of hosted FFmpeg. Boss ruling 2026-09-02: no Railway. (B)
5. Generation gateways: fal.ai primary, Replicate secondary and utility, direct APIs for Runway, HeyGen, Hedra, ElevenLabs. One GenerationRouter, one ai_models registry. (R, D2)
6. Publishing v1: Blotato behind the Publisher adapter (pre audited TikTok). Native adapters for YouTube Data API (100 uploads per day now) and IG Graph come second. Own TikTok audit runs as a v2 track. (R, D6)
7. Universe v1: Uncle Cred, Auntie APR, Repo Reggie, Mr. Denied, Funding Frank. Locations: Financial District bank, Uncle Cred office, house, dealership, tow yard. (B)
8. Approval: READY FOR LASEAN on every episode. Auto approve threshold enabled only from QA data. (B)
9. LLM routing: Fable 5.1 for showrunner, continuity, and credit claim verifier. Sonnet 5 for writers room and metadata. Haiku 4.5 for classification, extraction, and vision QA judging. Langfuse self hosted for traces and cost. (R, D10 obs)
10. Product CTA: token {PRODUCT_NAME} until Boss names it. (B)
11. LoRA: one per major character, FLUX.1 dev via fal flux-lora-fast-training (about 2 dollars per run), 15 to 30 images each, unique trigger word, versioned in the asset registry. Upgrade to FLUX.2 trainer only if quality fails. (R, D3)

## Research decisions
- D4 Video routing by shot type: dialogue closeup = LoRA still + Hedra Character-3 lip sync (HeyGen Avatar IV fallback). Two shot dialogue = Kling 3.0 with singles and over the shoulder coverage, never two mouths in frame. Action = Kling 3.0 Pro or Seedance 2.0. Establishing = Veo 3.1 (photoreal) or Seedance (stylized). B roll = cheapest that clears QA: Wan 2.2, Veo 3.1 Fast, Seedance Fast. Sora is deprecated 2026-09-24, never wire it.
- D5 Talking head: Hedra Character-3 primary (built for illustrated faces, about 6 credits per second at 720p). HeyGen promoted if Hedra reliability fails at volume.
- D7 Assembly: no Remotion, no Railway. Render is a provider behind the router: fal ffmpeg endpoints for concat, trim, mux, and subtitle burn; a template render API (Creatomate or Shotstack, pick by benchmark) for intro, outro, lower thirds, CTA, credit graphics. Change trigger: a composition the render APIs cannot express.
- D8 QA gate: sample 3 to 5 frames per clip. Identity via LoRA anchored CLIP-I plus DINOv2 (ArcFace is human face trained and its pretrained weights are non commercial; validate before use). Vision LLM (Haiku 4.5) judges anatomy, artifacts, text legibility, wardrobe, prop, location. Thresholds per character and per shot importance, tuned from data. Fail routes to repair, not blanket regenerate. max_auto_regenerations = 4 then escalate.
- Show law (Boss, 2026-09-02): the show does not give legal advice. Education about how credit and funding work, never what a viewer should legally do. Blocklist gains: 'you should sue', 'file a lawsuit', 'legally you', 'your rights are', any statute citation delivered as instruction.
- D9 Compliance guardrails in code: no guarantees or score jump promises, never claim removal of accurate info, no upfront fee solicitation, characters never pose as real customers or give results testimonials, education framing only, AI disclosure auto appended and double disclosure in first 3 to 5 seconds when paid plus AI, CROA 3 day cancellation language when promoting the paid service, hard blocklist (guaranteed, we will delete, erase your debt, instant approval, any numeric score promise). Lawyer signs off before first public post.
- D10 Storage: Supabase Storage for everything, one bucket per asset class, public bucket behind Supabase CDN for finals. Boss ruling 2026-09-02: no Cloudflare. Change trigger: egress cost on the Supabase invoice exceeds what R2 would cost for the same month.
- Analytics store accepts CSV import for what no API returns: retention curves (except YouTube), completion, TikTok watch time and reach, Facebook Reels reach.
- Voice: ElevenLabs Creator tier minimum (professional voice cloning, commercial license). One persistent voice_id per character, never regenerated.

## Canon locked
- Uncle Cred voice: ElevenLabs voice_id b2DJJJVITlSI2seQjLf5, locked, never regenerated. Stored in studio.visual_characters.metadata.voice (row created 2026-09-02).
