import { createServerClient, type CookieOptions } from "@supabase/ssr";
import { cookies } from "next/headers";
import { requireSupabaseEnv } from "./env";

type CookieToSet = { name: string; value: string; options: CookieOptions };

// Anon key only. RLS is the authorization boundary; the 436 owner_* policies are gated on
// platform.is_org_member(), so a session with no organization_members row reads nothing.
export async function createClient() {
  const cookieStore = await cookies();
  const { url, key } = requireSupabaseEnv();
  return createServerClient(
    url,
    key,
    {
      cookies: {
        getAll() {
          return cookieStore.getAll();
        },
        setAll(cookiesToSet: CookieToSet[]) {
          try {
            for (const { name, value, options } of cookiesToSet) {
              cookieStore.set(name, value, options);
            }
          } catch {
            // Called from a Server Component. The middleware refreshes the session instead.
          }
        },
      },
    },
  );
}
