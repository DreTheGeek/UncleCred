// Contracts for every generation request and every vendor response.
//
// KICKOFF law: "No vendor call outside the GenerationRouter" and "JSON schemas (Zod) on
// every AI output". Vendor payloads are external input, so nothing is trusted on shape.
// A vendor that changes its response fails loudly here rather than writing a malformed
// asset URL into canon.

import { z } from "zod";

// The seeded org id is 00000000-0000-0000-0000-000000000001, which is a valid Postgres uuid
// but not a valid RFC 4122 uuid: the version nibble is 0. Zod's .uuid() enforces the RFC, so
// it rejects the real id. Validate the shape Postgres actually accepts.
const uuidLike = z
  .string()
  .regex(/^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/, "must be a uuid");

export const Capability = z.enum([
  "image",
  "video",
  "voice",
  "talking_head",
  "transcription",
  "lora_training",
  "llm",
]);
export type Capability = z.infer<typeof Capability>;

/** Every request carries who it is for and why, so the cost ledger is never orphaned. */
export const RequestContext = z.object({
  organizationId: uuidLike,
  purpose: z.string().min(1),
  episodeId: uuidLike.nullable().default(null),
  characterCode: z.string().nullable().default(null),
  traceId: z.string().nullable().default(null),
});
export type RequestContext = z.infer<typeof RequestContext>;

export const ImageRequest = z.object({
  capability: z.literal("image"),
  prompt: z.string().min(1),
  negativePrompt: z.string().optional(),
  /** Character LoRA. Identity work must always pass one; text to image is never used for a character shot. */
  loras: z
    .array(z.object({ path: z.string().url(), scale: z.number().min(0).max(2).default(1) }))
    .default([]),
  referenceImageUrls: z.array(z.string().url()).default([]),
  imageSize: z
    .enum(["square_hd", "square", "portrait_4_3", "portrait_16_9", "landscape_4_3", "landscape_16_9"])
    .default("portrait_16_9"),
  numImages: z.number().int().min(1).max(4).default(1),
  seed: z.number().int().nullable().default(null),
  steps: z.number().int().min(1).max(60).default(28),
  guidanceScale: z.number().min(0).max(20).default(3.5),
});
export type ImageRequest = z.infer<typeof ImageRequest>;

export const VoiceRequest = z.object({
  capability: z.literal("voice"),
  text: z.string().min(1),
  /** Locked per character in canon. Never regenerated, never chosen at call time. */
  voiceId: z.string().min(1),
  modelId: z.string().default("eleven_multilingual_v2"),
});
export type VoiceRequest = z.infer<typeof VoiceRequest>;

export const TranscriptionRequest = z.object({
  capability: z.literal("transcription"),
  audioUrl: z.string().url(),
  wordTimestamps: z.boolean().default(true),
});
export type TranscriptionRequest = z.infer<typeof TranscriptionRequest>;

export const GenerationRequest = z.discriminatedUnion("capability", [
  ImageRequest,
  VoiceRequest,
  TranscriptionRequest,
]);
export type GenerationRequest = z.infer<typeof GenerationRequest>;

/** What every provider must return, whatever its native shape. */
export const GenerationResult = z.object({
  capability: Capability,
  provider: z.string(),
  model: z.string(),
  assets: z.array(
    z.object({
      url: z.string().url(),
      contentType: z.string().nullable().default(null),
      width: z.number().int().nullable().default(null),
      height: z.number().int().nullable().default(null),
    }),
  ),
  raw: z.unknown(),
  units: z.number().nonnegative(),
  unitKind: z.string(),
  costUsd: z.number().nonnegative(),
  seed: z.number().nullable().default(null),
  durationMs: z.number().int().nonnegative(),
});
export type GenerationResult = z.infer<typeof GenerationResult>;

/** A registry row. Selection reads this, never a hardcoded model id. */
export const ModelRow = z.object({
  id: uuidLike,
  provider: z.string(),
  provider_model_id: z.string(),
  capability: z.string(),
  model_family: z.string().nullable(),
  version: z.string().nullable(),
  supports: z.record(z.string(), z.unknown()),
  limits: z.record(z.string(), z.unknown()),
  cost_unit: z.string().nullable(),
  estimated_cost: z.coerce.number().nullable(),
  status: z.string(),
  enabled: z.boolean(),
});
export type ModelRow = z.infer<typeof ModelRow>;

export class GenerationError extends Error {
  readonly provider: string;
  readonly model: string;
  readonly detail: unknown;

  constructor(message: string, provider: string, model: string, detail?: unknown) {
    super(message);
    this.name = "GenerationError";
    this.provider = provider;
    this.model = model;
    this.detail = detail;
  }
}
