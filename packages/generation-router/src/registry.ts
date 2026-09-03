// Model selection reads system.ai_models. No model id is ever hardcoded in a caller.
//
// Swapping Kling for Seedance, or promoting HeyGen over Hedra, is a row update and a
// redeploy of nothing. That is the point of the registry: D4 and D5 in DECISIONS.md are
// expected to change once the benchmark lab has data, and they must change in one place.

import type { SupabaseClient } from "@supabase/supabase-js";
import { ModelRow, GenerationError, type Capability } from "./types.ts";

export type ModelFilter = {
  capability: Capability;
  /** Exact provider_model_id when the caller must pin one, e.g. the LoRA endpoint. */
  modelId?: string;
  provider?: string;
  /** Require a truthy key in the model's supports jsonb, e.g. "lora" or "photoreal". */
  requires?: string[];
  /** Allow candidate rows. Off by default so only proven models run in production. */
  allowCandidate?: boolean;
};

export class ModelRegistry {
  #cache = new Map<string, ModelRow[]>();
  readonly sb: SupabaseClient;

  constructor(sb: SupabaseClient) {
    this.sb = sb;
  }

  async load(capability: Capability): Promise<ModelRow[]> {
    const hit = this.#cache.get(capability);
    if (hit) return hit;
    const { data, error } = await this.sb
      .schema("system")
      .from("ai_models")
      .select(
        "id, provider, provider_model_id, capability, model_family, version, supports, limits, cost_unit, estimated_cost, status, enabled",
      )
      .eq("capability", capability);
    if (error) throw new GenerationError(`registry read failed: ${error.message}`, "registry", capability);
    const rows = (data ?? []).map((r) => ModelRow.parse(r));
    this.#cache.set(capability, rows);
    return rows;
  }

  /**
   * Cheapest model that satisfies the filter. Cost is the tiebreak because DECISIONS D4
   * says b roll takes "the cheapest that clears QA"; anything that must not be cheap
   * pins its model id explicitly.
   */
  async select(filter: ModelFilter): Promise<ModelRow> {
    const rows = await this.load(filter.capability);
    const candidates = rows
      .filter((r) => (filter.modelId ? r.provider_model_id === filter.modelId : true))
      .filter((r) => (filter.provider ? r.provider === filter.provider : true))
      .filter((r) => (filter.allowCandidate ? true : r.enabled && r.status === "active"))
      .filter((r) => (filter.requires ?? []).every((k) => Boolean(r.supports[k])))
      .sort((a, b) => (a.estimated_cost ?? Infinity) - (b.estimated_cost ?? Infinity));

    if (candidates.length === 0) {
      const detail = [
        `capability=${filter.capability}`,
        filter.modelId ? `model=${filter.modelId}` : null,
        filter.provider ? `provider=${filter.provider}` : null,
        filter.requires?.length ? `requires=${filter.requires.join(",")}` : null,
        filter.allowCandidate ? "candidates allowed" : "active+enabled only",
      ]
        .filter(Boolean)
        .join(", ");
      throw new GenerationError(
        `no model in system.ai_models matches: ${detail}. ` +
          `Seed or enable a row rather than hardcoding a model id in the caller.`,
        "registry",
        filter.modelId ?? filter.capability,
      );
    }
    return candidates[0];
  }
}
