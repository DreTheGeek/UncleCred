import type {
  SceneGenerationRequest,
  SceneProviderRoute,
} from "./scene-generation-contracts.ts";
import { validateGenerationRequest } from "./scene-generation-contracts.ts";

export type CapabilityRow = {
  provider: string;
  route_key: string;
  task_type: string;
  endpoint: string;
  active: boolean;
  priority: number;
  production_modes: string[] | null;
  quality_classes: string[] | null;
  supports_references: boolean;
  supports_dialogue: boolean;
  supports_lipsync: boolean;
  supports_camera_control: boolean;
  max_duration_seconds: number | string | null;
  expected_cost_cents: number | string | null;
  expected_latency_seconds: number | string | null;
  metadata: Record<string, unknown> | null;
};

export type HealthRow = {
  provider: string;
  route_key: string;
  status: "unknown" | "healthy" | "degraded" | "unavailable" | string;
  consecutive_failures: number;
};

function numeric(value: number | string | null | undefined): number | null {
  if (value == null) return null;
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
}

function supports(capability: CapabilityRow, request: SceneGenerationRequest) {
  const r = request.requirements;
  if (!capability.active || capability.task_type !== r.task) return false;
  if (capability.production_modes?.length && !capability.production_modes.includes(r.productionMode)) return false;
  if (capability.quality_classes?.length && !capability.quality_classes.includes(r.qualityClass)) return false;
  if ((r.referenceCount ?? 0) > 0 && !capability.supports_references) return false;
  if (r.dialogueRequired && !capability.supports_dialogue) return false;
  if (r.lipSyncRequired && !capability.supports_lipsync) return false;
  if ((r.cameraRequirements?.length ?? 0) > 0 && !capability.supports_camera_control) return false;

  const maxDuration = numeric(capability.max_duration_seconds);
  if (maxDuration != null && r.targetDurationSeconds != null && r.targetDurationSeconds > maxDuration) return false;

  const expectedCost = numeric(capability.expected_cost_cents);
  if (expectedCost != null && r.costCeilingCents != null && expectedCost > r.costCeilingCents) return false;
  return true;
}

function providerPreference(provider: string) {
  // Higgsfield is the current cinematic quality anchor. This is only a tie-breaker
  // after capability, health, and hard requirement filters have passed.
  if (provider === "higgsfield") return 30;
  if (provider === "fal") return 20;
  if (provider === "elevenlabs") return 10;
  return 0;
}

export function chooseGenerationRoute(input: {
  request: SceneGenerationRequest;
  capabilities: CapabilityRow[];
  health: HealthRow[];
}): SceneProviderRoute {
  const validation = validateGenerationRequest(input.request);
  if (!validation.valid) throw new Error(`generation_request_invalid:${validation.issues.join("|")}`);

  const healthByRoute = new Map(input.health.map((row) => [`${row.provider}:${row.route_key}`, row]));
  const candidates = input.capabilities.filter((capability) => supports(capability, input.request));
  if (!candidates.length) throw new Error("generation_route_not_found");

  const ranked = candidates
    .filter((capability) => healthByRoute.get(`${capability.provider}:${capability.route_key}`)?.status !== "unavailable")
    .map((capability) => {
      const health = healthByRoute.get(`${capability.provider}:${capability.route_key}`);
      const healthScore = health?.status === "healthy" ? 20 : health?.status === "degraded" ? -20 : 0;
      const failurePenalty = Math.min(Number(health?.consecutive_failures ?? 0), 10) * 5;
      return {
        capability,
        score: capability.priority + providerPreference(capability.provider) + healthScore - failurePenalty,
      };
    })
    .sort((a, b) => b.score - a.score || a.capability.route_key.localeCompare(b.capability.route_key));

  const winner = ranked[0]?.capability;
  if (!winner) throw new Error("generation_route_unavailable");

  const fallbacks = ranked.slice(1).map((entry) => entry.capability.route_key);
  const reasons = [
    `matches task:${input.request.requirements.task}`,
    `matches production_mode:${input.request.requirements.productionMode}`,
    `matches quality:${input.request.requirements.qualityClass}`,
  ];
  if (winner.provider === "higgsfield") reasons.push("primary cinematic quality route");

  return {
    provider: winner.provider as SceneProviderRoute["provider"],
    capability: input.request.requirements.task,
    routeKey: winner.route_key,
    modelOrEndpoint: winner.endpoint,
    rationale: reasons,
    expectedCostCents: numeric(winner.expected_cost_cents),
    expectedLatencySeconds: numeric(winner.expected_latency_seconds),
    fallbackRouteKeys: fallbacks,
  };
}
