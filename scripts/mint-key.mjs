#!/usr/bin/env node
// Mint an operator API key. Prints the raw key ONCE. Requires SUPABASE_DB_URL.
import { randomBytes, createHash } from "node:crypto";
import postgres from "postgres";
const name = process.argv[2] ?? "operator";
const org = process.argv[3] ?? "00000000-0000-0000-0000-000000000001";
const raw = "uc_" + randomBytes(32).toString("base64url");
const hash = createHash("sha256").update(raw).digest("hex");
const sql = postgres(process.env.SUPABASE_DB_URL);
await sql`insert into system.api_keys (organization_id, name, key_prefix, key_hash, scopes) values (${org}, ${name}, ${raw.slice(0, 8)}, ${hash}, ${["read", "write"]})`;
await sql.end();
console.log(raw);
