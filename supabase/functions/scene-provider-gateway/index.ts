// Scene provider gateway. Provider credentials stay inside Supabase runtime.
// Authenticates a target-Supabase user JWT or shared platform API key.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { admin, fail, ok, principalFrom, type Principal } from "../_shared/api.ts";
import { sceneOpenRouterCompletion, type SceneProviderMessage } from "../_shared/scene-provider.ts";

type Json = Record<string, unknown>;

type CompletionRequest = {
  task: "showrunner.initial_blueprint";
  organization_id: string;
  messages: SceneProviderMessage[];
  temperature?: number;
  max_tokens?: number;
  response_format?: Json;
};

function stringValue(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
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
    // Provider execution must not fail solely because audit recording failed.
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

  try {
    const result = await sceneOpenRouterCompletion({
      messages: body.messages,
      temperature: body.temperature,
      maxTokens: body.max_tokens,
      responseFormat: body.response_format,
    });
    await emitAudit(principal, organizationId, body.task, startedAt, true);
    return ok({
      provider: result.provider,
      model: result.model,
      provider_request_id: result.providerRequestId,
      content: result.content,
      usage: result.usage,
    }, 200, { task: body.task });
  } catch (error) {
    await emitAudit(principal, organizationId, body.task, startedAt, false);
    const message = error instanceof Error ? error.message : String(error);
    return fail("provider_execution_failed", message, 502);
  }
});
