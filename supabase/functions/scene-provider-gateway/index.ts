// Scene provider gateway. Keeps provider secrets inside Supabase runtime.
// Explicitly authenticates either a Supabase user JWT or a valid platform API key.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { admin, fail, ok, principalFrom, type Principal } from "../_shared/api.ts";

type Json = Record<string, unknown>;

type CompletionMessage = {
  role: "system" | "user" | "assistant";
  content: string;
};

type CompletionRequest = {
  task: "showrunner.initial_blueprint";
  organization_id: string;
  messages: CompletionMessage[];
  temperature?: number;
  max_tokens?: number;
  response_format?: Json;
};

function stringValue(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function safeNumber(value: unknown, fallback: number, min: number, max: number): number {
  const n = Number(value);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(min, Math.min(max, n));
}

async function canUseOrganization(principal: Principal, organizationId: string): Promise<boolean> {
  if (!organizationId) return false;
  if (principal.kind === "api_key") {
    if (principal.organizationId !== organizationId) return false;
    return principal.scopes.includes("story:write") || principal.scopes.includes("production:write") || principal.scopes.includes("admin");
  }

  const { data, error } = await admin()
    .schema("platform")
    .from("organization_members")
    .select("organization_id")
    .eq("organization_id", organizationId)
    .eq("user_id", principal.id)
    .eq("status", "active")
    .maybeSingle();

  return !error && Boolean(data);
}

function storyModel(): string {
  return Deno.env.get("SCENE_STORY_MODEL")?.trim() || "openrouter/auto";
}

async function openRouterCompletion(input: CompletionRequest) {
  const apiKey = Deno.env.get("OPENROUTER_API_KEY")?.trim();
  if (!apiKey) throw new Error("provider_secret_missing:OPENROUTER_API_KEY");

  const response = await fetch("https://openrouter.ai/api/v1/chat/completions", {
    method: "POST",
    headers: {
      authorization: `Bearer ${apiKey}`,
      "content-type": "application/json",
      "x-openrouter-title": "Scene",
    },
    body: JSON.stringify({
      model: storyModel(),
      messages: input.messages,
      temperature: safeNumber(input.temperature, 0.55, 0, 1.5),
      max_tokens: Math.floor(safeNumber(input.max_tokens, 12000, 256, 16000)),
      ...(input.response_format ? { response_format: input.response_format } : {}),
    }),
  });

  if (!response.ok) {
    const body = await response.text().catch(() => "");
    throw new Error(`openrouter_request_failed:${response.status}:${body.slice(0, 300)}`);
  }

  const payload = await response.json() as Json;
  const choices = Array.isArray(payload.choices) ? payload.choices as Json[] : [];
  const message = choices[0]?.message as Json | undefined;
  const content = stringValue(message?.content);
  if (!content) throw new Error("openrouter_empty_response");

  return {
    provider: "openrouter",
    model: stringValue(payload.model) || storyModel(),
    provider_request_id: stringValue(payload.id) || null,
    content,
    usage: payload.usage ?? null,
  };
}

async function emitAudit(principal: Principal, organizationId: string, task: string, startedAt: number, success: boolean) {
  try {
    await admin().schema("system").rpc("emit_event", {
      p_org: organizationId,
      p_type: success ? "scene.provider.completed" : "scene.provider.failed",
      p_table: null,
      p_id: null,
      p_payload: {
        task,
        principal_kind: principal.kind,
        principal_id: principal.id,
        duration_ms: Date.now() - startedAt,
      },
      p_actor: "scene-provider-gateway",
    });
  } catch {
    // Provider execution must not be failed solely by an audit-write problem.
  }
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return fail("method_not_allowed", "POST required", 405);

  const principal = await principalFrom(req);
  if (!principal) return fail("unauthorized", "Valid bearer credential required", 401);

  const startedAt = Date.now();
  let body: CompletionRequest;
  try {
    body = await req.json();
  } catch {
    return fail("invalid_json", "Request body must be valid JSON", 400);
  }

  const organizationId = stringValue(body.organization_id);
  if (!organizationId) return fail("organization_required", "organization_id is required", 400);
  if (!(await canUseOrganization(principal, organizationId))) {
    return fail("forbidden", "Principal cannot use providers for this organization", 403);
  }

  if (body.task !== "showrunner.initial_blueprint") {
    return fail("unsupported_task", "Unsupported provider task", 400);
  }
  if (!Array.isArray(body.messages) || body.messages.length < 1 || body.messages.length > 20) {
    return fail("invalid_messages", "messages must contain 1 to 20 items", 400);
  }

  try {
    const result = await openRouterCompletion(body);
    await emitAudit(principal, organizationId, body.task, startedAt, true);
    return ok(result, 200, { task: body.task });
  } catch (error) {
    await emitAudit(principal, organizationId, body.task, startedAt, false);
    const message = error instanceof Error ? error.message : String(error);
    return fail("provider_execution_failed", message, 502);
  }
});
