import { createServerClient, type CookieOptions } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";
import { resolveSupabaseEnv } from "./env";

type CookieToSet = { name: string; value: string; options: CookieOptions };

const PUBLIC_PATHS = ["/login", "/auth/callback", "/auth/error"];

const NOT_CONFIGURED = [
  "Uncle Cred Studio is deployed but not configured.",
  "",
  "MISSING: {missing}",
  "",
  "Set these on the Vercel project for Production and redeploy.",
  "The browser needs the NEXT_PUBLIC_ spelling specifically, because Next inlines",
  "those values at build time rather than reading them at runtime.",
  "",
].join("\n");

export async function updateSession(request: NextRequest) {
  // A misconfigured environment must not turn every route into an opaque 500.
  const resolved = resolveSupabaseEnv();
  if (!resolved.ok) {
    console.error("Supabase env missing in middleware:", resolved.missing.join(" and "));
    return new NextResponse(NOT_CONFIGURED.replace("{missing}", resolved.missing.join("  AND  ")), {
      status: 503,
      headers: { "content-type": "text/plain; charset=utf-8" },
    });
  }

  let response = NextResponse.next({ request });

  const supabase = createServerClient(resolved.env.url, resolved.env.key, {
    cookies: {
      getAll() {
        return request.cookies.getAll();
      },
      setAll(cookiesToSet: CookieToSet[]) {
        for (const { name, value } of cookiesToSet) request.cookies.set(name, value);
        response = NextResponse.next({ request });
        for (const { name, value, options } of cookiesToSet) {
          response.cookies.set(name, value, options);
        }
      },
    },
  });

  // getUser, never getSession. getSession trusts the client JWT without revalidating it.
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const path = request.nextUrl.pathname;
  const isPublic = PUBLIC_PATHS.some((p) => path === p || path.startsWith(p + "/"));

  if (!user && !isPublic) {
    const url = request.nextUrl.clone();
    url.pathname = "/login";
    url.searchParams.set("next", path);
    return NextResponse.redirect(url);
  }
  if (user && path === "/login") {
    const url = request.nextUrl.clone();
    url.pathname = "/";
    url.search = "";
    return NextResponse.redirect(url);
  }
  return response;
}
