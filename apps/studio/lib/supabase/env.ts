// Resolves the Supabase URL and publishable (anon) key.
//
// The Supabase Vercel integration sets several spellings of the same two values, and the
// newer integration uses PUBLISHABLE_KEY where the older one used ANON_KEY. Accept all of
// them rather than depending on which integration version provisioned the project.
//
// NEXT_PUBLIC_* is inlined at build time and is the only spelling the browser can see.
// Server and middleware code can also read the non-public spellings at runtime, so a
// missing NEXT_PUBLIC_* does not have to take the whole app down server side.
//
// Values are never logged. Only variable NAMES appear in errors.

const URL_NAMES = ["NEXT_PUBLIC_SUPABASE_URL", "SUPABASE_URL"] as const;
const KEY_NAMES = [
  "NEXT_PUBLIC_SUPABASE_ANON_KEY",
  "NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY",
  "SUPABASE_ANON_KEY",
  "SUPABASE_PUBLISHABLE_KEY",
] as const;

export type SupabaseEnv = { url: string; key: string };

function firstSet(names: readonly string[]): { value?: string; from?: string } {
  for (const n of names) {
    const v = process.env[n];
    if (typeof v === "string" && v.length > 0) return { value: v, from: n };
  }
  return {};
}

/** Returns the env, or a list of what is missing. Never throws. */
export function resolveSupabaseEnv():
  | { ok: true; env: SupabaseEnv; urlFrom: string; keyFrom: string }
  | { ok: false; missing: string[] } {
  const url = firstSet(URL_NAMES);
  const key = firstSet(KEY_NAMES);
  const missing: string[] = [];
  if (!url.value) missing.push(`one of: ${URL_NAMES.join(", ")}`);
  if (!key.value) missing.push(`one of: ${KEY_NAMES.join(", ")}`);
  if (missing.length) return { ok: false, missing };
  return { ok: true, env: { url: url.value!, key: key.value! }, urlFrom: url.from!, keyFrom: key.from! };
}

/** Throws a message that names the variables, never their values. */
export function requireSupabaseEnv(): SupabaseEnv {
  const r = resolveSupabaseEnv();
  if (!r.ok) {
    throw new Error(
      `Supabase is not configured. Missing ${r.missing.join(" and ")}. ` +
        `Set these on the Vercel project (Production) and redeploy. ` +
        `The browser needs the NEXT_PUBLIC_ spelling specifically, because it is inlined at build time.`,
    );
  }
  return r.env;
}
