"use client";
import { createBrowserClient } from "@supabase/ssr";

// Order matters:
//   1. NEXT_PUBLIC_* if the build managed to inline it (the normal Next path).
//   2. The runtime config the server wrote into the document, for deployments where the
//      values are runtime-only and therefore invisible to the build.
// Only the publishable (anon) key ever appears here. It is meant to be public and is
// powerless without an RLS policy granting access.
function readRuntimeConfig(): { url?: string; key?: string } {
  if (typeof document === "undefined") return {};
  const el = document.getElementById("__uc_runtime_config");
  if (!el?.textContent) return {};
  try {
    const parsed: unknown = JSON.parse(el.textContent);
    if (parsed && typeof parsed === "object") {
      const { url, key } = parsed as { url?: unknown; key?: unknown };
      return {
        url: typeof url === "string" ? url : undefined,
        key: typeof key === "string" ? key : undefined,
      };
    }
  } catch {
    // Malformed config is the same as no config: fall through to the clear error below.
  }
  return {};
}

export function createClient() {
  const runtime = readRuntimeConfig();
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL || runtime.url;
  const key =
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ||
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ||
    runtime.key;

  if (!url || !key) {
    throw new Error(
      "Supabase is not configured for the browser. Either set NEXT_PUBLIC_SUPABASE_URL and " +
        "NEXT_PUBLIC_SUPABASE_ANON_KEY as build-visible variables, or make sure the server " +
        "can read SUPABASE_URL and SUPABASE_ANON_KEY at runtime so the layout can hand them " +
        "to the browser.",
    );
  }
  return createBrowserClient(url, key);
}
