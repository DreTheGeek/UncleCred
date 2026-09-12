export type SceneGenerationTask =
  | "image"
  | "reference_image"
  | "video"
  | "image_to_video"
  | "lip_sync"
  | "voice"
  | "audio";

export type SceneQualityClass = "draft" | "standard" | "cinematic" | "hero";
export type SceneLatencyClass = "interactive" | "normal" | "batch";
export type SceneCriticality = "low" | "medium" | "high" | "locked";
export type SceneComplexity = "low" | "medium" | "high";

export type SceneGenerationRequirements = {
  task: SceneGenerationTask;
  productionMode: "cinematic" | "anime" | "stylized_3d" | "cartoon" | "comic" | "stick_figure";
  aspectRatio?: string;
  targetDurationSeconds?: number;
  referenceCount?: number;
  identityCriticality?: SceneCriticality;
  environmentCriticality?: SceneCriticality;
  propCriticality?: SceneCriticality;
  motionComplexity?: SceneComplexity;
  cameraRequirements?: string[];
  dialogueRequired?: boolean;
  lipSyncRequired?: boolean;
  qualityClass: SceneQualityClass;
  latencyClass: SceneLatencyClass;
  costCeilingCents?: number | null;
  retryBudgetCents?: number | null;
};

export type SceneProviderName = "higgsfield" | "fal" | "elevenlabs";

export type SceneProviderRoute = {
  provider: SceneProviderName;
  capability: SceneGenerationTask;
  routeKey: string;
  modelOrEndpoint: string;
  rationale: string[];
  expectedCostCents: number | null;
  expectedLatencySeconds: number | null;
  fallbackRouteKeys: string[];
};

export type SceneGenerationAttempt = {
  provider: SceneProviderName;
  routeKey: string;
  providerRequestId: string | null;
  submittedAt: string;
  completedAt?: string | null;
  estimatedCostCents: number | null;
  actualCostCents?: number | null;
  latencyMs?: number | null;
  accepted?: boolean | null;
  rejectionReason?: string | null;
  repairAction?: string | null;
  qa?: Record<string, unknown>;
  provenance?: Record<string, unknown>;
};

export function validateGenerationRequirements(input: SceneGenerationRequirements) {
  const issues: string[] = [];

  if (input.targetDurationSeconds != null && input.targetDurationSeconds <= 0) {
    issues.push("targetDurationSeconds must be positive");
  }
  if (input.referenceCount != null && input.referenceCount < 0) {
    issues.push("referenceCount cannot be negative");
  }
  if (input.costCeilingCents != null && input.costCeilingCents < 0) {
    issues.push("costCeilingCents cannot be negative");
  }
  if (input.retryBudgetCents != null && input.retryBudgetCents < 0) {
    issues.push("retryBudgetCents cannot be negative");
  }
  if (input.lipSyncRequired && !input.dialogueRequired) {
    issues.push("lipSyncRequired requires dialogueRequired");
  }
  if ((input.task === "video" || input.task === "image_to_video") && input.targetDurationSeconds == null) {
    issues.push("video generation requires targetDurationSeconds");
  }

  return { valid: issues.length === 0, issues };
}
