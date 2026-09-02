# DECISIONS (locked 2026-09-02)

Source for each: R = Step 0 research, B = Boss default accepted, S = standard default.

## Stack intake (Assumption Law batch, accepted by Boss)
1. Repo: DreTheGeek/UncleCred. Spine from kaldr-core, organs from laseanpickens. (B)
2. Database: NEW Supabase project for the studio. LaSeanPickens project stays as is. Year One migrates in later as universe two. (B)
3. Workflow engine: Trigger.dev v4 Cloud (Free then Hobby), self host on Railway later. Not Temporal. pg_cron only for simple schedules. (R, D1)
4. Workers: Railway containers for FFmpeg and Remotion and vendor polling. Vercel for the command center. (B, D7)
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
- D7 Remotion: Remotion for Automators license (0.01 per render, 100 per month minimum). Automation is the trigger, not headcount. Render on Railway, Lambda only for parallel scale.
- D8 QA gate: sample 3 to 5 frames per clip. Identity via LoRA anchored CLIP-I plus DINOv2 (ArcFace is human face trained and its pretrained weights are non commercial; validate before use). Vision LLM (Haiku 4.5) judges anatomy, artifacts, text legibility, wardrobe, prop, location. Thresholds per character and per shot importance, tuned from data. Fail routes to repair, not blanket regenerate. max_auto_regenerations = 4 then escalate.
- D9 Compliance guardrails in code: no guarantees or score jump promises, never claim removal of accurate info, no upfront fee solicitation, characters never pose as real customers or give results testimonials, education framing only, AI disclosure auto appended and double disclosure in first 3 to 5 seconds when paid plus AI, CROA 3 day cancellation language when promoting the paid service, hard blocklist (guaranteed, we will delete, erase your debt, instant approval, any numeric score promise). Lawyer signs off before first public post.
- D10 Storage: Cloudflare R2 for published and CDN video from day one (0 egress). Supabase Storage for private working files and render intermediates.
- Analytics store accepts CSV import for what no API returns: retention curves (except YouTube), completion, TikTok watch time and reach, Facebook Reels reach.
- Voice: ElevenLabs Creator tier minimum (professional voice cloning, commercial license). One persistent voice_id per character, never regenerated.
