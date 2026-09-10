import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { admin, fail, ok, principalFrom, type Principal } from "../_shared/api.ts";
import {
  buildInitialSceneBlueprint,
  createSceneShow,
  getActiveSceneBlueprint,
  getSceneShow,
  listSceneShows,
  principalCanUseOrganization,
} from "../_shared/scene-story.ts";

function hasScope(principal: Principal, scope: string) {
  return principal.kind === "user" || principal.scopes.includes(scope) || principal.scopes.includes("admin");
}

function requestId(req: Request) {
  return req.headers.get("x-request-id")?.trim() || crypto.randomUUID();
}

function organizationIdFrom(req: Request, body?: Record<string, unknown>) {
  const url = new URL(req.url);
  const fromQuery = url.searchParams.get("organization_id")?.trim();
  const fromBody = typeof body?.organization_id === "string" ? body.organization_id.trim() : "";
  return fromBody || fromQuery || "";
}

async function hashJson(value: unknown) {
  const bytes = new TextEncoder().encode(JSON.stringify(value));
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function reserve(principal: Principal, orgId: string, operation: string, key: string, body: unknown) {
  const { data, error } = await admin().schema("system").rpc("reserve_external_idempotency", {
    p_organization_id: orgId,
    p_principal_kind: principal.kind,
    p_principal_id: principal.id,
    p_operation: operation,
    p_key: key,
    p_request_hash: await hashJson(body),
  });
  if (error) throw new Error(`idempotency_reserve_failed:${error.message}`);
  return data as Record<string, unknown>;
}

async function complete(id: string, status: number, body: unknown, resourceType?: string, resourceId?: string, failed = false) {
  const { error } = await admin().schema("system").rpc("complete_external_idempotency", {
    p_id: id,
    p_status: status,
    p_body: body,
    p_resource_type: resourceType ?? null,
    p_resource_id: resourceId ?? null,
    p_failed: failed,
  });
  if (error) console.error("scene-api idempotency completion failed", error.message);
}

async function audit(input: {
  principal: Principal;
  organizationId: string;
  requestId: string;
  operation: string;
  method: string;
  status: number;
  startedAt: number;
  resourceType?: string;
  resourceId?: string;
  metadata?: Record<string, unknown>;
}) {
  try {
    await admin().schema("system").rpc("record_external_request", {
      p_organization_id: input.organizationId,
      p_principal_kind: input.principal.kind,
      p_principal_id: input.principal.id,
      p_transport: "rest",
      p_request_id: input.requestId,
      p_operation: input.operation,
      p_method: input.method,
      p_resource_type: input.resourceType ?? null,
      p_resource_id: input.resourceId ?? null,
      p_response_status: input.status,
      p_duration_ms: Date.now() - input.startedAt,
      p_metadata: input.metadata ?? {},
    });
  } catch (error) {
    console.error("scene-api audit failed", error instanceof Error ? error.message : String(error));
  }
}

function response(data: unknown, status: number, reqId: string) {
  return new Response(JSON.stringify(data), { status, headers: { "content-type": "application/json", "x-request-id": reqId } });
}

function parsePath(req: Request) {
  const path = new URL(req.url).pathname.replace(/^\/scene-api/, "").replace(/^\/functions\/v1\/scene-api/, "") || "/";
  return path.replace(/\/+$/, "") || "/";
}

Deno.serve(async (req: Request) => {
  const startedAt = Date.now();
  const reqId = requestId(req);
  const path = parsePath(req);

  if (req.method === "OPTIONS") return new Response(null, { status: 204 });
  if (req.method === "GET" && path === "/health") {
    return response({ ok: true, data: { service: "scene-api", apiVersion: "v1", status: "ok" }, requestId: reqId }, 200, reqId);
  }

  const principal = await principalFrom(req);
  if (!principal) return response({ ok: false, error: { code: "unauthorized", message: "Valid bearer credential required" }, requestId: reqId }, 401, reqId);

  if (req.method === "GET" && path === "/whoami") {
    return response({ ok: true, data: principal, requestId: reqId }, 200, reqId);
  }

  let body: Record<string, unknown> = {};
  if (req.method !== "GET") {
    try { body = await req.json(); }
    catch { return response({ ok: false, error: { code: "invalid_json", message: "Request body must be valid JSON" }, requestId: reqId }, 400, reqId); }
  }

  const orgId = organizationIdFrom(req, body);
  if (!orgId) return response({ ok: false, error: { code: "organization_required", message: "organization_id is required" }, requestId: reqId }, 400, reqId);
  if (!(await principalCanUseOrganization(principal, orgId))) return response({ ok: false, error: { code: "forbidden", message: "Organization access denied" }, requestId: reqId }, 403, reqId);

  try {
    if (req.method === "GET" && path === "/shows") {
      if (!hasScope(principal, "shows:read")) return response({ ok: false, error: { code: "forbidden", message: "shows:read scope required" }, requestId: reqId }, 403, reqId);
      const shows = await listSceneShows(principal, orgId);
      await audit({ principal, organizationId: orgId, requestId: reqId, operation: "shows.list", method: "GET", status: 200, startedAt });
      return response({ ok: true, data: shows, requestId: reqId }, 200, reqId);
    }

    if (req.method === "POST" && path === "/shows") {
      if (!hasScope(principal, "shows:write")) return response({ ok: false, error: { code: "forbidden", message: "shows:write scope required" }, requestId: reqId }, 403, reqId);
      const idemKey = req.headers.get("idempotency-key")?.trim() || "";
      if (idemKey.length < 8 || idemKey.length > 200) return response({ ok: false, error: { code: "idempotency_key_required", message: "Valid Idempotency-Key header required" }, requestId: reqId }, 400, reqId);
      const reservation = await reserve(principal, orgId, "shows.create", idemKey, body);
      if (reservation.state === "conflict") return response({ ok: false, error: { code: "idempotency_conflict", message: "Idempotency key reused with different input" }, requestId: reqId }, 409, reqId);
      if (reservation.state === "in_progress") return response({ ok: false, error: { code: "request_in_progress", message: "Matching request is still in progress" }, requestId: reqId }, 409, reqId);
      if (reservation.state === "replay") return response(reservation.body, Number(reservation.status) || 200, reqId);

      const title = typeof body.title === "string" ? body.title.trim() : "";
      const initialRequest = typeof body.initial_request === "string" ? body.initial_request.trim() : "";
      if (!title || !initialRequest) {
        const out = { ok: false, error: { code: "invalid_show", message: "title and initial_request are required" }, requestId: reqId };
        await complete(String(reservation.id), 400, out, undefined, undefined, true);
        return response(out, 400, reqId);
      }
      const show = await createSceneShow(principal, orgId, {
        title,
        initialRequest,
        format: typeof body.format === "string" ? body.format : null,
        productionMode: typeof body.production_mode === "string" ? body.production_mode as "cinematic" | "anime" | "stylized_3d" | "cartoon" | "comic" | "stick_figure" : undefined,
        guidanceMode: typeof body.guidance_mode === "string" ? body.guidance_mode as "follow_closely" | "build_with_me" | "take_the_wheel" : undefined,
        universeId: typeof body.universe_id === "string" ? body.universe_id : null,
        creatorInputState: typeof body.creator_input_state === "object" && body.creator_input_state ? body.creator_input_state as Record<string, unknown> : {},
      });
      const out = { ok: true, data: show, requestId: reqId };
      await complete(String(reservation.id), 201, out, "story.show", show.id);
      await audit({ principal, organizationId: orgId, requestId: reqId, operation: "shows.create", method: "POST", status: 201, startedAt, resourceType: "story.show", resourceId: show.id });
      return response(out, 201, reqId);
    }

    const showMatch = path.match(/^\/shows\/([0-9a-f-]{36})$/i);
    if (req.method === "GET" && showMatch) {
      if (!hasScope(principal, "shows:read")) return response({ ok: false, error: { code: "forbidden", message: "shows:read scope required" }, requestId: reqId }, 403, reqId);
      const show = await getSceneShow(principal, orgId, showMatch[1]);
      const status = show ? 200 : 404;
      await audit({ principal, organizationId: orgId, requestId: reqId, operation: "shows.get", method: "GET", status, startedAt, resourceType: "story.show", resourceId: showMatch[1] });
      return show ? response({ ok: true, data: show, requestId: reqId }, 200, reqId) : response({ ok: false, error: { code: "show_not_found", message: "Show not found" }, requestId: reqId }, 404, reqId);
    }

    const blueprintMatch = path.match(/^\/shows\/([0-9a-f-]{36})\/blueprint$/i);
    if (req.method === "GET" && blueprintMatch) {
      if (!hasScope(principal, "story:read")) return response({ ok: false, error: { code: "forbidden", message: "story:read scope required" }, requestId: reqId }, 403, reqId);
      const blueprint = await getActiveSceneBlueprint(principal, orgId, blueprintMatch[1]);
      const status = blueprint ? 200 : 404;
      await audit({ principal, organizationId: orgId, requestId: reqId, operation: "story.blueprint.get", method: "GET", status, startedAt, resourceType: "story.show", resourceId: blueprintMatch[1] });
      return blueprint ? response({ ok: true, data: blueprint, requestId: reqId }, 200, reqId) : response({ ok: false, error: { code: "blueprint_not_found", message: "Active blueprint not found" }, requestId: reqId }, 404, reqId);
    }

    if (req.method === "POST" && blueprintMatch) {
      if (!hasScope(principal, "story:write")) return response({ ok: false, error: { code: "forbidden", message: "story:write scope required" }, requestId: reqId }, 403, reqId);
      const idemKey = req.headers.get("idempotency-key")?.trim() || "";
      if (idemKey.length < 8 || idemKey.length > 200) return response({ ok: false, error: { code: "idempotency_key_required", message: "Valid Idempotency-Key header required" }, requestId: reqId }, 400, reqId);
      const reservation = await reserve(principal, orgId, "story.blueprint.build", idemKey, { showId: blueprintMatch[1] });
      if (reservation.state === "conflict") return response({ ok: false, error: { code: "idempotency_conflict", message: "Idempotency key reused with different input" }, requestId: reqId }, 409, reqId);
      if (reservation.state === "in_progress") return response({ ok: false, error: { code: "request_in_progress", message: "Matching request is still in progress" }, requestId: reqId }, 409, reqId);
      if (reservation.state === "replay") return response(reservation.body, Number(reservation.status) || 200, reqId);

      try {
        const result = await buildInitialSceneBlueprint(principal, orgId, blueprintMatch[1]);
        const out = { ok: true, data: result, requestId: reqId };
        await complete(String(reservation.id), 201, out, "story.show", blueprintMatch[1]);
        await audit({ principal, organizationId: orgId, requestId: reqId, operation: "story.blueprint.build", method: "POST", status: 201, startedAt, resourceType: "story.show", resourceId: blueprintMatch[1], metadata: { provider: result.provider, model: result.model } });
        return response(out, 201, reqId);
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        const out = { ok: false, error: { code: "showrunner_failed", message }, requestId: reqId };
        await complete(String(reservation.id), 500, out, "story.show", blueprintMatch[1], true);
        await audit({ principal, organizationId: orgId, requestId: reqId, operation: "story.blueprint.build", method: "POST", status: 500, startedAt, resourceType: "story.show", resourceId: blueprintMatch[1], metadata: { error: message.slice(0, 300) } });
        return response(out, 500, reqId);
      }
    }

    return response({ ok: false, error: { code: "not_found", message: `No route ${req.method} ${path}` }, requestId: reqId }, 404, reqId);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return response({ ok: false, error: { code: "internal", message }, requestId: reqId }, 500, reqId);
  }
});
