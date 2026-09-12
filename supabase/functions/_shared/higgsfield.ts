import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const HIGGSFIELD_API_BASE = "https://platform.higgsfield.ai";

export type HiggsfieldRequestStatus =
  | "queued"
  | "processing"
  | "completed"
  | "failed"
  | "nsfw"
  | "canceled"
  | string;

export type HiggsfieldSubmitInput = {
  endpoint: string;
  payload: Record<string, unknown>;
};

export type HiggsfieldSubmitResult = {
  provider: "higgsfield";
  requestId: string;
  status: HiggsfieldRequestStatus;
  statusUrl: string;
  cancelUrl: string;
  raw: Record<string, unknown>;
};

function credentials() {
  // Higgsfield uses a key id + secret pair. Accept the aliases already used in
  // our Supabase environments so we can migrate without rotating credentials.
  const keyId = Deno.env.get("HF_API_KEY_ID")?.trim()
    || Deno.env.get("HIGGSFIELD_API_KEY_ID")?.trim();
  const keySecret = Deno.env.get("HF_API_SECRET")?.trim()
    || Deno.env.get("HF_API_KEY_SECRET")?.trim()
    || Deno.env.get("HIGGSFIELD_API_KEY_SECRET")?.trim();
  if (!keyId) throw new Error("provider_secret_missing:HF_API_KEY_ID");
  if (!keySecret) throw new Error("provider_secret_missing:HF_API_SECRET");
  return { keyId, keySecret };
}

function authHeader() {
  const { keyId, keySecret } = credentials();
  return `Key ${keyId}:${keySecret}`;
}

function normalizeModelEndpoint(endpoint: string) {
  const trimmed = endpoint.trim();
  if (!trimmed) throw new Error("higgsfield_endpoint_required");
  if (/^https?:\/\//i.test(trimmed)) throw new Error("higgsfield_endpoint_must_be_relative");
  const normalized = trimmed.replace(/^\/+/, "");
  if (!normalized || normalized.includes("..") || normalized.startsWith("requests/")) {
    throw new Error("higgsfield_invalid_endpoint");
  }
  return `${HIGGSFIELD_API_BASE}/${normalized}`;
}

function requestUrl(requestId: string, action: "status" | "cancel") {
  const id = requestId.trim();
  if (!id || id.includes("/") || id.includes("..")) throw new Error("higgsfield_invalid_request_id");
  return `${HIGGSFIELD_API_BASE}/requests/${encodeURIComponent(id)}/${action}`;
}

function asRecord(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
}

function nonEmptyString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

async function parseJsonResponse(response: Response, errorPrefix: string) {
  const bodyText = await response.text();
  let body: Record<string, unknown> = {};
  try {
    body = asRecord(bodyText ? JSON.parse(bodyText) : {});
  } catch {
    if (!response.ok) throw new Error(`${errorPrefix}:${response.status}:${bodyText.slice(0, 300)}`);
    throw new Error(`${errorPrefix}:invalid_json_response`);
  }

  if (!response.ok) {
    const detail = nonEmptyString(body.detail) || nonEmptyString(body.message) || bodyText.slice(0, 300);
    throw new Error(`${errorPrefix}:${response.status}:${detail}`);
  }
  return body;
}

export function isHiggsfieldTerminalStatus(status: string) {
  return status === "completed" || status === "failed" || status === "nsfw" || status === "canceled";
}

export async function submitHiggsfieldGeneration(input: HiggsfieldSubmitInput): Promise<HiggsfieldSubmitResult> {
  const response = await fetch(normalizeModelEndpoint(input.endpoint), {
    method: "POST",
    headers: {
      Authorization: authHeader(),
      "Content-Type": "application/json",
    },
    body: JSON.stringify(input.payload),
  });

  const raw = await parseJsonResponse(response, "higgsfield_submit_failed");
  const requestId = nonEmptyString(raw.request_id);
  const statusUrl = nonEmptyString(raw.status_url);
  const cancelUrl = nonEmptyString(raw.cancel_url);
  const status = nonEmptyString(raw.status) || "queued";

  if (!requestId) throw new Error("higgsfield_submit_missing_request_id");
  if (!statusUrl) throw new Error("higgsfield_submit_missing_status_url");
  if (!cancelUrl) throw new Error("higgsfield_submit_missing_cancel_url");

  return {
    provider: "higgsfield",
    requestId,
    status,
    statusUrl,
    cancelUrl,
    raw,
  };
}

export async function getHiggsfieldRequestStatus(requestId: string) {
  const response = await fetch(requestUrl(requestId, "status"), {
    headers: { Authorization: authHeader() },
  });
  const raw = await parseJsonResponse(response, "higgsfield_status_failed");
  const status = nonEmptyString(raw.status);
  return {
    provider: "higgsfield" as const,
    requestId,
    status,
    terminal: isHiggsfieldTerminalStatus(status),
    raw,
  };
}

export async function cancelHiggsfieldRequest(requestId: string) {
  const response = await fetch(requestUrl(requestId, "cancel"), {
    method: "POST",
    headers: { Authorization: authHeader() },
  });

  if (!response.ok) {
    const body = await response.text().catch(() => "");
    throw new Error(`higgsfield_cancel_failed:${response.status}:${body.slice(0, 300)}`);
  }

  return {
    provider: "higgsfield" as const,
    requestId,
    canceled: true,
  };
}
