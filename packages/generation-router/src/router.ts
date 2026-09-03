// The single seam. KICKOFF law: no vendor call outside the GenerationRouter.
//
// Everything a vendor call needs to be safe happens here, once, for every capability:
//   request validated  -> model chosen from the registry  -> provider called
//   -> response validated -> cost written to system.ai_cost_ledger -> event emitted
//
// The cost write is deliberately not conditional. DECISIONS commits to cost per episode and
// ROI per character in Phase 06, and those numbers are only trustworthy if every call is
// recorded, including the ones that fail.

import type { SupabaseClient } from "@supabase/supabase-js";
import { ModelRegistry, type ModelFilter } from "./registry.ts";
import { FalProvider } from "./providers/fal.ts";
import {
  GenerationError,
  GenerationRequest,
  GenerationResult,
  RequestContext,
  type Capability,
} from "./types.ts";

export type RouterKeys = { falKey?: string; elevenLabsKey?: string };

export class GenerationRouter {
  readonly #registry: ModelRegistry;
  readonly #fal: FalProvider | null;

  readonly sb: SupabaseClient;

  constructor(sb: SupabaseClient, keys: RouterKeys) {
    this.sb = sb;
    this.#registry = new ModelRegistry(sb);
    this.#fal = keys.falKey ? new FalProvider(keys.falKey) : null;
  }

  async generate(
    rawRequest: unknown,
    rawContext: unknown,
    filter?: Partial<ModelFilter>,
  ): Promise<GenerationResult> {
    const request = GenerationRequest.parse(rawRequest);
    const context = RequestContext.parse(rawContext);

    const model = await this.#registry.select({
      capability: request.capability as Capability,
      ...filter,
    });

    let result: GenerationResult;
    try {
      result = await this.#dispatch(model, request);
    } catch (e) {
      // Record the attempt even though it produced nothing. A failed vendor call still
      // costs wall clock and often money, and an invisible failure is how a budget drifts.
      await this.#logCost({
        context,
        provider: model.provider,
        model: model.provider_model_id,
        units: 0,
        unitKind: model.cost_unit ?? "unknown",
        costUsd: 0,
        purposeSuffix: ".failed",
      });
      throw e;
    }

    const validated = GenerationResult.parse(result);
    await this.#logCost({
      context,
      provider: validated.provider,
      model: validated.model,
      units: validated.units,
      unitKind: validated.unitKind,
      costUsd: validated.costUsd,
    });

    const { error: evErr } = await this.sb.schema("system").rpc("emit_event", {
      p_org: context.organizationId,
      p_type: `generation.${validated.capability}.completed`,
      p_table: null,
      p_id: null,
      p_payload: {
        provider: validated.provider,
        model: validated.model,
        purpose: context.purpose,
        character_code: context.characterCode,
        assets: validated.assets.length,
        cost_usd: validated.costUsd,
        duration_ms: validated.durationMs,
      },
      p_actor: "generation-router",
    });
    if (evErr) console.error("generation-router ledger write failed:", evErr.message);

    return validated;
  }

  async #dispatch(
    model: Awaited<ReturnType<ModelRegistry["select"]>>,
    request: GenerationRequest,
  ): Promise<GenerationResult> {
    if (model.provider === "fal") {
      if (!this.#fal) throw new GenerationError("FAL_KEY not configured", "fal", model.provider_model_id);
      if (request.capability === "image") return this.#fal.image(model, request);
      if (request.capability === "transcription") return this.#fal.transcription(model, request);
    }
    if (request.capability === "voice") {
      throw new GenerationError(
        "Voice is not wired yet. ElevenLabs needs ELEVENLABS_API_KEY and a provider adapter; " +
          "the voice_id per character is already locked in canon metadata.",
        model.provider,
        model.provider_model_id,
      );
    }
    throw new GenerationError(
      `No adapter for provider=${model.provider} capability=${request.capability}`,
      model.provider,
      model.provider_model_id,
    );
  }

  async #logCost(args: {
    context: RequestContext;
    provider: string;
    model: string;
    units: number;
    unitKind: string;
    costUsd: number;
    purposeSuffix?: string;
  }): Promise<void> {
    const { error } = await this.sb
      .schema("system")
      .from("ai_cost_ledger")
      .insert({
        organization_id: args.context.organizationId,
        provider: args.provider,
        model: args.model,
        purpose: args.context.purpose + (args.purposeSuffix ?? ""),
        episode_id: args.context.episodeId,
        character_code: args.context.characterCode,
        units: args.units,
        unit_kind: args.unitKind,
        cost_usd: args.costUsd,
        trace_id: args.context.traceId,
      });
    // Never fail a generation because the ledger write failed, but never hide it either.
    if (error) console.error("ai_cost_ledger write failed:", error.message);
  }
}
