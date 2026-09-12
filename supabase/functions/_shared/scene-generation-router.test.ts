import { assertEquals, assertThrows } from "jsr:@std/assert@1";
import { chooseGenerationRoute, type CapabilityRow, type HealthRow } from "./scene-generation-router.ts";
import type { SceneGenerationRequest } from "./scene-generation-contracts.ts";

const request: SceneGenerationRequest = {
  requirements: {
    task: "image_to_video",
    productionMode: "cinematic",
    targetDurationSeconds: 5,
    referenceCount: 1,
    qualityClass: "cinematic",
    latencyClass: "normal",
    cameraRequirements: ["dolly_in"],
    costCeilingCents: 200,
  },
  prompt: "A controlled cinematic push-in toward the subject.",
  referenceUrls: ["https://example.com/reference.jpg"],
};

function capability(overrides: Partial<CapabilityRow> = {}): CapabilityRow {
  return {
    provider: "higgsfield",
    route_key: "higgsfield.dop_turbo.image_to_video",
    task_type: "image_to_video",
    endpoint: "v1/image2video/dop",
    active: true,
    priority: 100,
    production_modes: ["cinematic"],
    quality_classes: ["cinematic", "hero"],
    supports_references: true,
    supports_dialogue: false,
    supports_lipsync: false,
    supports_camera_control: true,
    max_duration_seconds: null,
    expected_cost_cents: 100,
    expected_latency_seconds: 60,
    metadata: { model: "dop-turbo" },
    ...overrides,
  };
}

function health(overrides: Partial<HealthRow> = {}): HealthRow {
  return {
    provider: "higgsfield",
    route_key: "higgsfield.dop_turbo.image_to_video",
    status: "healthy",
    consecutive_failures: 0,
    ...overrides,
  };
}

Deno.test("router selects Higgsfield when it satisfies cinematic requirements", () => {
  const route = chooseGenerationRoute({ request, capabilities: [capability()], health: [health()] });
  assertEquals(route.provider, "higgsfield");
  assertEquals(route.routeKey, "higgsfield.dop_turbo.image_to_video");
});

Deno.test("router excludes unavailable provider routes", () => {
  assertThrows(
    () => chooseGenerationRoute({ request, capabilities: [capability()], health: [health({ status: "unavailable" })] }),
    Error,
    "generation_route_unavailable",
  );
});

Deno.test("router enforces known hard cost ceiling", () => {
  assertThrows(
    () => chooseGenerationRoute({ request, capabilities: [capability({ expected_cost_cents: 250 })], health: [health()] }),
    Error,
    "generation_route_not_found",
  );
});

Deno.test("router prefers healthy Higgsfield over lower-priority fallback", () => {
  const fallback = capability({
    provider: "fal",
    route_key: "fal.example.image_to_video",
    endpoint: "fal/example",
    priority: 90,
  });
  const route = chooseGenerationRoute({
    request,
    capabilities: [fallback, capability()],
    health: [
      health(),
      { provider: "fal", route_key: "fal.example.image_to_video", status: "healthy", consecutive_failures: 0 },
    ],
  });
  assertEquals(route.provider, "higgsfield");
});

Deno.test("router rejects provider-neutral request missing image-to-video reference", () => {
  assertThrows(
    () => chooseGenerationRoute({
      request: { ...request, referenceUrls: [] },
      capabilities: [capability()],
      health: [health()],
    }),
    Error,
    "generation_request_invalid",
  );
});
