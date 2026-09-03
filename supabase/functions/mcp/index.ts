// Remote MCP server for the studio. JSON-RPC 2.0 over HTTP POST.
//
// Per API-STANDARD the MCP server authenticates with the same uc_ API key as the REST API.
// No separate OAuth. This is deliberately not a port of laseanpickens kaldr-mcp, which
// carries its own mcp_oauth_clients / mcp_auth_codes / mcp_access_tokens tables; UncleCred
// already has system.api_keys and system.validate_api_key, and a second auth system would
// be a second thing to get wrong.
//
// Semantic search runs entirely inside the edge runtime: Supabase.ai gte-small embeds the
// query to 384 dims, pgvector does cosine on knowledge.document_chunks. Same model that
// wrote the column, so the vectors are comparable. No external embedding key.
//
// eslint-disable-next-line @typescript-eslint/triple-slash-reference
/// <reference path="../_shared/supabase-ai.d.ts" />
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import postgres from "https://deno.land/x/postgresjs@v3.4.5/mod.js";
import { admin, validateApiKey, type Principal } from "../_shared/api.ts";

const model = new Supabase.ai.Session("gte-small");
const dbUrl = Deno.env.get("SUPABASE_DB_URL");
if (!dbUrl) throw new Error("SUPABASE_DB_URL unavailable");
const sql = postgres(dbUrl, { prepare: false });

const SERVER = { name: "unclecred-studio", version: "0.1.0" };

type JsonRpcId = string | number | null;
type ToolDef = {
  name: string;
  description: string;
  inputSchema: Record<string, unknown>;
  run: (args: Record<string, unknown>, p: Principal) => Promise<unknown>;
};

function str(v: unknown, fallback = ""): string {
  return typeof v === "string" ? v : fallback;
}
function num(v: unknown, fallback: number, max: number): number {
  const n = Number(v);
  return Number.isFinite(n) ? Math.max(1, Math.min(n, max)) : fallback;
}

const TOOLS: ToolDef[] = [
  {
    name: "search_credit_knowledge",
    description:
      "Semantic search over the credit knowledge base (7,424 chunks from 167 documents covering credit fundamentals, repair, dispute rounds, cards strategy, personal and business funding). Returns the passages a claim can be grounded against. Use this before asserting anything about how credit works.",
    inputSchema: {
      type: "object",
      properties: {
        query: { type: "string", description: "What to look up, in plain language." },
        limit: { type: "number", description: "How many passages, 1 to 20. Default 5." },
      },
      required: ["query"],
    },
    run: async (args) => {
      const query = str(args.query).trim();
      if (!query) throw new Error("query is required");
      const limit = num(args.limit, 5, 20);
      const vector = await model.run(query, { mean_pool: true, normalize: true });
      const rows = await sql`
        select c.id::text, c.content, c.heading_path, d.title as document_title,
               round((1 - (c.embedding <=> ${JSON.stringify(vector)}::extensions.vector(384)))::numeric, 4) as similarity
        from knowledge.document_chunks c
        join knowledge.documents d on d.id = c.document_id
        where c.embedding is not null
        order by c.embedding <=> ${JSON.stringify(vector)}::extensions.vector(384)
        limit ${limit}
      `;
      return { query, matches: rows };
    },
  },
  {
    name: "list_characters",
    description: "Every character in canon, with the traits and prohibited changes that the writers room and the QA gate must not violate.",
    inputSchema: { type: "object", properties: {} },
    run: async () => {
      const { data, error } = await admin()
        .schema("studio")
        .from("visual_characters")
        .select("character_code, name, public_name, description, age_range, prohibited_changes, active")
        .order("character_code");
      if (error) throw new Error(error.message);
      return { characters: data };
    },
  },
  {
    name: "get_character",
    description: "One character in full, including wardrobe, physical traits, personality, and the canon metadata that holds the locked LoRA and voice.",
    inputSchema: {
      type: "object",
      properties: { character_code: { type: "string", description: "For example uncle_cred." } },
      required: ["character_code"],
    },
    run: async (args) => {
      const code = str(args.character_code).trim();
      if (!code) throw new Error("character_code is required");
      const { data, error } = await admin()
        .schema("studio")
        .from("visual_characters")
        .select("*")
        .eq("character_code", code)
        .maybeSingle();
      if (error) throw new Error(error.message);
      if (!data) throw new Error(`No character with character_code ${code}`);
      return data;
    },
  },
  {
    name: "studio_status",
    description: "What the studio currently holds: cast size, episode counts by status, knowledge base embedding coverage, pipeline depth, and ledger size. Use this instead of guessing at state.",
    inputSchema: { type: "object", properties: {} },
    run: async () => {
      const [counts] = await sql`
        select
          (select count(*) from studio.visual_characters) as characters,
          (select count(*) from studio.episodes) as episodes,
          (select count(*) from studio.pipeline_runs) as pipeline_runs,
          (select count(*) from studio.pipeline_stages) as pipeline_stages,
          (select count(*) from knowledge.documents) as documents,
          (select count(*) from knowledge.document_chunks) as chunks,
          (select count(*) from knowledge.document_chunks where embedding is not null) as chunks_embedded,
          (select count(*) from system.system_events) as ledger_events
      `;
      const byStatus = await sql`
        select status::text, count(*)::int as n from studio.episodes group by status order by n desc
      `;
      return { ...counts, episodes_by_status: byStatus };
    },
  },
  {
    name: "recent_events",
    description: "The immutable ledger, newest first. Every meaningful thing the studio did is a row here and rows are never edited or deleted.",
    inputSchema: {
      type: "object",
      properties: {
        limit: { type: "number", description: "1 to 200. Default 25." },
        event_type: { type: "string", description: "Optional exact filter, for example canon.lora.trained." },
      },
    },
    run: async (args) => {
      const limit = num(args.limit, 25, 200);
      const type = str(args.event_type).trim();
      let q = admin()
        .schema("system")
        .from("system_events")
        .select("id, event_type, subject_table, subject_id, actor, payload, occurred_at")
        .order("id", { ascending: false })
        .limit(limit);
      if (type) q = q.eq("event_type", type);
      const { data, error } = await q;
      if (error) throw new Error(error.message);
      return { events: data };
    },
  },
];

const rpc = (id: JsonRpcId, result: unknown) =>
  new Response(JSON.stringify({ jsonrpc: "2.0", id, result }), {
    headers: { "content-type": "application/json" },
  });

const rpcError = (id: JsonRpcId, code: number, message: string, status = 200) =>
  new Response(JSON.stringify({ jsonrpc: "2.0", id, error: { code, message } }), {
    status,
    headers: { "content-type": "application/json" },
  });

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method Not Allowed", { status: 405 });
  }

  const principal = await validateApiKey(req);
  if (!principal) {
    // 401 before parsing the body. The key itself is never echoed or logged.
    return rpcError(null, -32001, "A uc_ API key is required in the Authorization header.", 401);
  }

  let body: { id?: JsonRpcId; method?: string; params?: Record<string, unknown> };
  try {
    body = await req.json();
  } catch {
    return rpcError(null, -32700, "Parse error");
  }
  const id = body.id ?? null;
  const method = body.method ?? "";

  switch (method) {
    case "initialize":
      return rpc(id, {
        protocolVersion: "2024-11-05",
        capabilities: { tools: {} },
        serverInfo: SERVER,
      });
    case "notifications/initialized":
      return new Response(null, { status: 204 });
    case "ping":
      return rpc(id, {});
    case "tools/list":
      return rpc(id, {
        tools: TOOLS.map(({ name, description, inputSchema }) => ({ name, description, inputSchema })),
      });
    case "tools/call": {
      const name = str(body.params?.name);
      const tool = TOOLS.find((t) => t.name === name);
      if (!tool) return rpcError(id, -32602, `Unknown tool ${name}`);
      const args = (body.params?.arguments ?? {}) as Record<string, unknown>;
      try {
        const result = await tool.run(args, principal);
        // Audit every call. Fort Knox wants the trail, and the ledger is the trail.
        // supabase-js rpc() returns a thenable, not a Promise, so it has no .catch().
        // A failed audit write must never fail the tool call, hence the try/catch.
        try {
          const { error: auditErr } = await admin().schema("system").rpc("emit_event", {
            p_org: principal.organizationId,
            p_type: "mcp.tool.called",
            p_table: null,
            p_id: null,
            p_payload: { tool: name, principal: principal.id },
            p_actor: "mcp",
          });
          if (auditErr) console.error("mcp audit write failed:", auditErr.message);
        } catch (auditThrow) {
          console.error("mcp audit write threw:", errText(auditThrow));
        }
        return rpc(id, {
          content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
          isError: false,
        });
      } catch (e) {
        const message = e instanceof Error ? e.message : String(e);
        return rpc(id, { content: [{ type: "text", text: message }], isError: true });
      }
    }
    default:
      return rpcError(id, -32601, `Method not found: ${method}`);
  }
});
