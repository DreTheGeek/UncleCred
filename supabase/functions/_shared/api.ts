// API envelope and key validation per API-STANDARD. Key is never logged.
import { createClient } from "jsr:@supabase/supabase-js@2";

export const admin = () => createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });

export type Principal = { kind: "api_key"; id: string; organizationId: string | null; scopes: string[] } | { kind: "user"; id: string };

export const ok = (data: unknown, status = 200, meta: Record<string, unknown> = {}) =>
  new Response(JSON.stringify({ ok: true, data, meta }), { status, headers: { "content-type": "application/json" } });

export const fail = (code: string, message: string, status = 400) =>
  new Response(JSON.stringify({ ok: false, error: { code, message } }), { status, headers: { "content-type": "application/json" } });

export async function validateApiKey(req: Request): Promise<Principal | null> {
  const auth = req.headers.get("authorization") ?? "";
  const raw = auth.startsWith("Bearer ") ? auth.slice(7).trim() : "";
  if (!raw.startsWith("uc_")) return null;
  const { data, error } = await admin().schema("system").rpc("validate_api_key", { p_raw: raw });
  if (error || !data || data.length === 0) return null;
  const row = data[0];
  return { kind: "api_key", id: row.id, organizationId: row.organization_id, scopes: row.scopes ?? [] };
}

export async function principalFrom(req: Request): Promise<Principal | null> {
  const viaKey = await validateApiKey(req);
  if (viaKey) return viaKey;
  const jwt = (req.headers.get("authorization") ?? "").replace("Bearer ", "");
  if (!jwt) return null;
  const { data } = await admin().auth.getUser(jwt);
  return data.user ? { kind: "user", id: data.user.id } : null;
}
