# RESEARCH (Step 0 summary, full report in the chat artifact dated 2026-09-02)

Numbers checked 2026-09-02 unless noted. Verify vendor pages at wiring time; aggregator numbers are directional.

## Image and LoRA
- FLUX.2 on fal: dev 0.012 per MP, pro 0.03 per MP, up to 10 reference images. Flash 0.005 per MP.
- FLUX.1 dev control stack (LoRA, ControlNet, IP-Adapter): fal-ai/flux-general at 0.075 per MP. This is the turnaround and expression sheet endpoint.
- LoRA training: flux-lora-fast-training 2 dollars per run. flux-2-trainer-v2 25.50 per 1000 steps. Dataset 15 to 30 images at 1024, varied pose, light, expression.
- Alternatives (Ideogram Character, Midjourney cref, gpt-image, Imagen): pricing not verified this pass.

## Video (fal per second unless noted)
- Kling 3.0 Pro: conflicting, 0.112 to 0.336 depending on audio and tier. Best character consistency and multi shot.
- Veo 3.1 Fast 0.10 (720p), Standard about 0.40. Native audio.
- Seedance 2.0: 0.022 (fast, third party) to 0.682 (1080p). Native audio video sync.
- Runway Gen-4 Turbo 0.05 per second direct. Gen-4.5 text to video only. References take 1 to 3 images.
- Wan 2.2 0.10. Hailuo 2.3 Pro about 0.49 per clip.
- Sora 2 deprecated 2026-09-24. Do not use.
- Multi person in frame dialogue is weak everywhere. Shoot singles.

## Talking head
- Hedra Character-3: 6 credits per second 720p, 3 at 540p. Creator 30 per month 5400 credits, Pro 75 per month 14400. Built for cartoon and illustrated faces. Trustpilot 1.9 (billing and support, not output).
- HeyGen Avatar IV API: pay as you go, conflicting rates (4 per minute vs credit based). Verify.

## Voice
- ElevenLabs: Starter 6 (commercial), Creator 22 (PVC), Pro 99, Scale 299. About 1000 credits per minute on Multilingual v2. Voice Design, SFX, Music APIs live.

## Assembly
- Remotion: free only for up to 3 people AND no automation. Automators license 0.01 per render, 100 per month minimum. Telemetry mandatory from 5.0.
- Railway: 20 per vCPU month, 10 per GB RAM month, 0.05 per GB egress. Hobby 5, Pro 20.
- Subtitles: Whisper via fal or Replicate cheapest, word level timestamps. Deepgram and AssemblyAI pricing not verified this pass.

## QA
- ArcFace via InsightFace is the identity standard for humans; pretrained buffalo weights are non commercial. CLIP-I plus DINOv2 for stylized characters. Vision LLM judge on Haiku 4.5 costs well under a cent per clip.

## Orchestration
- Trigger.dev v4: Apache 2.0. Free 20 concurrent, Hobby 10 per month, Pro 50. Waits over 5 seconds are checkpointed and not billed. Cloud max run 14 days. 1500 API req per minute cap.
- Temporal Cloud about 200 per month low volume. Inngest Pro 99.

## Publishing
- TikTok Content Posting API: unaudited posts forced SELF_ONLY forever, 5 users per 24h, audit 2 to 4 weeks, 6 req per minute per token.
- YouTube Data API: uploads moved to a 1 unit bucket capped at 100 per day (2026-06-01).
- Instagram Reels via Graph API needs Business or Creator account plus instagram_manage_insights.
- LinkedIn needs Community Management API approval.
- Blotato: 29 per month flat, 9 platforms, analytics on 8, hosted MCP with 35 tools, pre audited TikTok.

## Analytics via API
- YouTube: full, including retention curve. Instagram: views, reach, saves, shares, avg watch time ms, skip rate. TikTok: counts only, no watch time. Facebook: Reels reach removed 2026-06-15. LinkedIn: VIDEO_VIEW, VIEWER, TIME_WATCHED, 6 month expiry.

## LLM
- Anthropic Sept 2026: Opus 5 (5/25), Sonnet 5 (2/10), Haiku 4.5 (1/5), Fable 5.1 (10/50). Cache reads 0.1x. Batch 50 percent off.
- Langfuse MIT, self host free. Helicone Apache 2.0 proxy. Braintrust Pro 249.

## Compliance
- CROA: no upfront fees, no guarantees, no removal of accurate info, 3 day cancel right, written contract terms. Advice for pay can pull software into scope.
- FTC Reviews and Testimonials Rule stands (Rytr order set aside Dec 2025, rule intact). No fictional character as a real customer.
- AI labels: TikTok AIGC (C2PA auto), YouTube synthetic declaration, Meta AI Info. Labels are disclosure, not ranking signals per TikTok; audiences can reduce AI content via a slider.
- State CSO statutes TX, GA, CA, FL: registration and bonds vary. Legal review required.

## Storage
- R2: 0.015 per GB month, 0 egress, Class A 4.50 per million, Class B 0.36 per million, 10 GB free.
