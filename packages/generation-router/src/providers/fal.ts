// fal.ai adapter. Primary gateway per DECISIONS D5.
//
// Ported in spirit from the laseanpickens generation calls, rebuilt around the registry so
// no endpoint is hardcoded in a caller. Every response is parsed with Zod before it leaves
// this file: fal returns different shapes per endpoint and a silent shape change would
// otherwise write an undefined URL into canon.

import { fal } from "@fal-ai/client";
import { z } from "zod";
import {
  GenerationError,
  type GenerationResult,
  type ImageRequest,
  type ModelRow,
  type TranscriptionRequest,
} from "../types.ts";

// fal image endpoints all return an images array; fields beyond these are ignored on purpose.
const FalImageResponse = z.object({
  images: z
    .array(
      z.object({
        url: z.string().url(),
        width: z.number().int().optional(),
        height: z.number().int().optional(),
        content_type: z.string().optional(),
      }),
    )
    .min(1, "fal returned no images"),
  // fal returns seeds above Number.MAX_SAFE_INTEGER, so no int bound here.
  seed: z.number().optional(),
});

const FalWhisperResponse = z.object({
  text: z.string(),
  chunks: z
    .array(z.object({ text: z.string(), timestamp: z.array(z.number().nullable()).length(2) }))
    .optional(),
});

export class FalProvider {
  readonly name = "fal";

  constructor(apiKey: string) {
    if (!apiKey) throw new GenerationError("FAL_KEY is required", "fal", "-");
    fal.config({ credentials: apiKey });
  }

  async image(model: ModelRow, req: ImageRequest): Promise<GenerationResult> {
    const started = Date.now();

    // flux-general is the LoRA / ControlNet endpoint (RESEARCH.md, image and LoRA section).
    // Passing loras to an endpoint that does not support them silently ignores identity,
    // which is exactly the failure that produces an off model character, so refuse instead.
    const supportsLora = Boolean(model.supports["lora"]) || model.provider_model_id.includes("flux-general");
    if (req.loras.length > 0 && !supportsLora) {
      throw new GenerationError(
        `${model.provider_model_id} does not support LoRA, but ${req.loras.length} were supplied. ` +
          `Character shots must use a LoRA capable endpoint such as fal-ai/flux-general.`,
        this.name,
        model.provider_model_id,
      );
    }

    const input: Record<string, unknown> = {
      prompt: req.prompt,
      image_size: req.imageSize,
      num_images: req.numImages,
      num_inference_steps: req.steps,
      guidance_scale: req.guidanceScale,
      enable_safety_checker: true,
    };
    if (req.negativePrompt) input.negative_prompt = req.negativePrompt;
    if (req.seed !== null) input.seed = req.seed;
    if (req.loras.length > 0) input.loras = req.loras.map((l) => ({ path: l.path, scale: l.scale }));
    if (req.referenceImageUrls.length > 0) input.image_urls = req.referenceImageUrls;

    // Reference conditioning. flux-general takes a single canonical reference plus a strength,
    // which is the mechanism DECISIONS calls for on every character shot.
    if (req.referenceImageUrl) {
      input.reference_image_url = req.referenceImageUrl;
      input.reference_strength = req.referenceStrength;
    }

    let data: unknown;
    try {
      const out = await fal.subscribe(model.provider_model_id, { input, logs: false });
      data = (out as { data: unknown }).data;
    } catch (e) {
      throw new GenerationError(
        `fal call failed: ${e instanceof Error ? e.message : String(e)}`,
        this.name,
        model.provider_model_id,
        e,
      );
    }

    const parsed = FalImageResponse.safeParse(data);
    if (!parsed.success) {
      throw new GenerationError(
        `fal response did not match the expected image shape: ${parsed.error.issues
          .map((i) => `${i.path.join(".")} ${i.message}`)
          .join("; ")}`,
        this.name,
        model.provider_model_id,
      );
    }

    // Images are billed per megapixel. Measure the pixels actually returned rather than
    // trusting the requested size, because endpoints round to their own buckets.
    const megapixels = parsed.data.images.reduce(
      (sum, i) => sum + ((i.width ?? 0) * (i.height ?? 0)) / 1_000_000,
      0,
    );
    const units = megapixels > 0 ? megapixels : parsed.data.images.length;
    const unitKind = megapixels > 0 ? "megapixel" : "image";

    return {
      capability: "image",
      provider: this.name,
      model: model.provider_model_id,
      assets: parsed.data.images.map((i) => ({
        url: i.url,
        contentType: i.content_type ?? null,
        width: i.width ?? null,
        height: i.height ?? null,
      })),
      raw: data,
      units,
      unitKind,
      costUsd: Number(((model.estimated_cost ?? 0) * units).toFixed(6)),
      seed: parsed.data.seed ?? null,
      durationMs: Date.now() - started,
    };
  }

  async transcription(model: ModelRow, req: TranscriptionRequest): Promise<GenerationResult> {
    const started = Date.now();
    let data: unknown;
    try {
      const out = await fal.subscribe(model.provider_model_id, {
        input: {
          audio_url: req.audioUrl,
          task: "transcribe",
          chunk_level: req.wordTimestamps ? "word" : "segment",
        },
        logs: false,
      });
      data = (out as { data: unknown }).data;
    } catch (e) {
      throw new GenerationError(
        `fal transcription failed: ${e instanceof Error ? e.message : String(e)}`,
        this.name,
        model.provider_model_id,
        e,
      );
    }

    const parsed = FalWhisperResponse.safeParse(data);
    if (!parsed.success) {
      throw new GenerationError(
        `fal whisper response did not match the expected shape`,
        this.name,
        model.provider_model_id,
      );
    }

    // Whisper bills per minute of audio; the last chunk timestamp is the honest duration.
    const lastEnd = parsed.data.chunks?.at(-1)?.timestamp?.[1] ?? null;
    const minutes = typeof lastEnd === "number" ? lastEnd / 60 : 0;

    return {
      capability: "transcription",
      provider: this.name,
      model: model.provider_model_id,
      assets: [],
      raw: data,
      units: minutes,
      unitKind: "minute",
      costUsd: Number(((model.estimated_cost ?? 0) * minutes).toFixed(6)),
      seed: null,
      durationMs: Date.now() - started,
    };
  }
}
