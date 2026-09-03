import { NextResponse, type NextRequest } from "next/server";
import { createClient } from "@/lib/supabase/server";
import type { EmailOtpType } from "@supabase/supabase-js";

// Handles both magic link shapes: the PKCE "code" flow and the "token_hash" flow.
//
// PKCE stores its verifier in a cookie on the browser that STARTED the sign in. Open the
// email in a different browser (or a webmail preview, or a link scanner) and the verifier
// is missing, so exchangeCodeForSession fails through no fault of the user. That is not an
// error state worth a dead end: the same email also carries a numeric code, so we hand the
// reason back to /login and it offers the code box.
export async function GET(request: NextRequest) {
  const { searchParams, origin } = request.nextUrl;
  const code = searchParams.get("code");
  const tokenHash = searchParams.get("token_hash");
  const type = searchParams.get("type") as EmailOtpType | null;

  // Supabase can also redirect here with its own error, e.g. an expired link.
  const providerError = searchParams.get("error_description") ?? searchParams.get("error");

  // Open redirect guard: only same-origin relative paths are honoured.
  const rawNext = searchParams.get("next") ?? "/";
  const next = rawNext.startsWith("/") && !rawNext.startsWith("//") ? rawNext : "/";

  const fail = (reason: string, email?: string | null) => {
    const url = new URL(`${origin}/login`);
    url.searchParams.set("reason", reason.slice(0, 300));
    url.searchParams.set("next", next);
    // Offer the code box straight away; the user already has the email open.
    url.searchParams.set("otp", "1");
    if (email) url.searchParams.set("email", email);
    return NextResponse.redirect(url);
  };

  if (providerError) return fail(providerError);

  const supabase = await createClient();

  if (code) {
    const { error } = await supabase.auth.exchangeCodeForSession(code);
    if (!error) return NextResponse.redirect(`${origin}${next}`);
    console.error("exchangeCodeForSession failed:", error.message);
    return fail(
      error.message.toLowerCase().includes("verifier") || error.message.toLowerCase().includes("code")
        ? "This link was opened in a different browser from the one that requested it, so the sign in could not be completed. Use the code from the same email instead."
        : error.message,
    );
  }

  if (tokenHash && type) {
    const { error } = await supabase.auth.verifyOtp({ type, token_hash: tokenHash });
    if (!error) return NextResponse.redirect(`${origin}${next}`);
    console.error("verifyOtp failed:", error.message);
    return fail(error.message);
  }

  return fail("That sign in link was missing its code. Request a new one, or paste the code from the email.");
}
