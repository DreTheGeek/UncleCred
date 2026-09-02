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

## Naming and domain (Boss, 2026-09-02)
- Display name is two words: Uncle Cred. Everywhere a human reads it. The repo slug and code identifiers stay UncleCred / unclecred.
- Command center lives at content.unclecred.app (Vercel project apps/studio, CNAME at GoDaddy). Add the domain in the Phase 01 Claude Code session.

## The click law (Boss, 2026-09-02)
Boss's whole job in this software is click, click, click, output. Nothing he touches asks him to think about the pipeline.
- Daily driver is the Review Room. Three actions per episode, one tap each: Approve, Send back, Kill. Approve schedules and publishes with no second screen.
- Every "needs you" item is a one tap decision with a default already picked: pick A or B, approve the inpaint, confirm the wardrobe. Never a form.
- Character intake is a picker, not a form: the studio generates candidates, Boss taps the one he likes, the rest is automatic.
- The command center never asks for input. It reports and offers one primary button.
- Any screen that needs more than three taps to produce an output fails the operator reality audit and gets redesigned.
- Home screen is Review Room when anything is waiting on Boss, Command Center otherwise.

## Uncle Cred identity v1.0 (Boss, 2026-09-02, from the visual identity board)
- Uncle Cred is a PHOTOREAL digital actor, not a stylized character. Round 1 stylized candidates rejected. This supersedes the "stylized" assumption in D3, D4, and D8.
- Consequence for D8: ArcFace identity scoring is now valid (photoreal human face). Identity threshold 0.95 hard gate. Photorealism is its own gate at 0.94 (skin texture, pores, asymmetry, eye moisture, individual hairs, no wax or CGI look, no uncanny teeth, no oversharpening).
- Board traits locked in studio.visual_characters: age 45 to 52, 5'10", athletic solid build, short tapered waves, well groomed salt and pepper beard, gold or bronze frames, palette #641E2C #351018 #F7F3EB #161616 #9A633B #B39562.
- Wardrobe is an asset, not a prompt: UC_WARDROBE_001 cream knit quarter zip polo, UC_PANTS_001 dark tailored trousers, UC_SHOES_001 brown leather loafers, UC_GLASSES_001 gold frames, UC_WATCH_001 gold watch. Office is LOCATION UC_OFFICE_001, built as a virtual set with approved plates per camera direction.
- Identity pipeline, in order, nothing skipped: Face Master 001 (one photoreal casting portrait Boss points at) -> reference pack of 30 to 60 same-photoshoot images (front, 3/4s, profiles, full body, sitting, expressions, talking mouth positions, lighting variations) -> LoRA UC_LORA_V1 with trigger token UNCLECRED_V1 -> reference conditioned generation (LoRA + canonical ref + locked spec + wardrobe ref + scene ref) -> approved keyframe -> image to video -> identity QA. Never text to video for a character shot.
- The board itself is direction, not a training source. The board has minor facial variation between panels; training on it would bake inconsistency in.
- Tables this implies (Claude Code, Phase 02): character_versions, character_traits, character_references, character_loras, character_wardrobes, character_accessories, character_voices, character_generation_recipes, character_expressions, character_qa_profiles, character_relationships. Extend studio.visual_characters rather than replace it; the current jsonb fields are the interim.
