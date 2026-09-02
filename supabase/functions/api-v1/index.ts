// /api/v1 surface. Phase 01 ships health and whoami; each later phase registers its routes here.
import { ok, fail, principalFrom, admin } from "../_shared/api.ts";

const routes: Record<string, (req: Request, p: Awaited<ReturnType<typeof principalFrom>>) => Promise<Response>> = {
  "GET /health": async () => ok({ service: "Uncle Cred", time: new Date().toISOString() }),
  "GET /whoami": async (_req, p) => (p ? ok(p) : fail("unauthorized", "Bearer key or session required", 401)),
  "GET /events": async (req, p) => {
    if (!p) return fail("unauthorized", "Bearer key or session required", 401);
    const limit = Math.min(Number(new URL(req.url).searchParams.get("limit") ?? 50), 200);
    const { data, error } = await admin().schema("system").from("system_events").select("*").order("id", { ascending: false }).limit(limit);
    return error ? fail("db_error", error.message, 500) : ok(data, 200, { limit });
  },
};

Deno.serve(async (req) => {
  const url = new URL(req.url);
  const path = url.pathname.replace(/^\/api-v1/, "") || "/";
  const key = `${req.method} ${path}`;
  const handler = routes[key];
  if (!handler) return fail("not_found", `No route ${key}`, 404);
  const principal = await principalFrom(req);
  try {
    const res = await handler(req, principal);
    if (principal && req.method !== "GET") {
      await admin().schema("system").rpc("emit_event", { p_org: principal.kind === "api_key" ? principal.organizationId : null, p_type: "api.call", p_table: null, p_id: null, p_payload: { route: key, principal: principal.id }, p_actor: principal.kind });
    }
    return res;
  } catch (e) {
    return fail("internal", e instanceof Error ? e.message : String(e), 500);
  }
});
