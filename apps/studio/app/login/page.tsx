"use client";

import { useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

// One email box, one button. No password field, no signup page, per the ruling.
// First signup becomes owner through the uc_bootstrap_first_owner trigger on auth.users.
//
// The code box is the fallback for the PKCE failure mode: the magic link's verifier lives in
// a cookie on the browser that requested it, so opening the email somewhere else breaks the
// link through no fault of the user. The same email carries a numeric code that works from
// any browser, so a failed link offers the box rather than dead ending.
export default function LoginPage() {
  const router = useRouter();
  const params = useSearchParams();

  // Derived during render, not in an effect, so the code box and the failure reason are in
  // the first HTML rather than appearing a frame later. Someone whose link just failed should
  // not watch the fix pop in after the fact.
  const reason = params.get("reason") ?? "";

  const [email, setEmail] = useState(params.get("email") ?? "");
  const [code, setCode] = useState("");
  const [showCode, setShowCode] = useState(params.get("otp") === "1");
  const [state, setState] = useState<"idle" | "sending" | "sent" | "verifying" | "error">(
    reason ? "error" : "idle",
  );
  const [message, setMessage] = useState(reason);
  const [isError, setIsError] = useState(Boolean(reason));

  const next = params.get("next") ?? "/";

  async function sendLink(e: React.FormEvent) {
    e.preventDefault();
    if (!email.trim()) return;
    setState("sending");
    setIsError(false);
    const supabase = createClient();
    const siteUrl = process.env.NEXT_PUBLIC_SITE_URL ?? window.location.origin;
    const { error } = await supabase.auth.signInWithOtp({
      email: email.trim(),
      options: { emailRedirectTo: `${siteUrl}/auth/callback?next=${encodeURIComponent(next)}` },
    });
    if (error) {
      console.error("signInWithOtp failed", error);
      setMessage(error.message);
      setIsError(true);
      setState("error");
      return;
    }
    setMessage(`Sent to ${email.trim()}. Open the link, or paste the code from that email below.`);
    setIsError(false);
    setShowCode(true);
    setState("sent");
  }

  async function verifyCode(e: React.FormEvent) {
    e.preventDefault();
    const token = code.replace(/\s+/g, "");
    if (!email.trim() || !token) return;
    setState("verifying");
    setIsError(false);
    const supabase = createClient();
    const { error } = await supabase.auth.verifyOtp({
      email: email.trim(),
      token,
      type: "email",
    });
    if (error) {
      console.error("verifyOtp failed", error);
      setMessage(error.message);
      setIsError(true);
      setState("error");
      return;
    }
    router.push(next.startsWith("/") && !next.startsWith("//") ? next : "/");
    router.refresh();
  }

  const busy = state === "sending" || state === "verifying";

  return (
    <main className="grid min-h-screen place-items-center px-5">
      <div className="w-full max-w-[380px]">
        <div className="mb-8 text-center">
          <div className="disp text-[34px] leading-none text-cred">UNCLE CRED</div>
          <div className="mono mt-1 text-[10px] tracking-[0.14em] text-dim">
            STUDIO / KALDR BUSINESS GROUP
          </div>
        </div>

        <form onSubmit={sendLink} className="rounded-[13px] border border-line bg-panel p-5" noValidate>
          <label htmlFor="email" className="mono mb-2 block text-[10px] tracking-[0.14em] text-dim">
            EMAIL
          </label>
          <input
            id="email"
            name="email"
            type="email"
            autoComplete="email"
            autoFocus
            required
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            disabled={busy}
            placeholder="you@kaldrbusiness.com"
            className="w-full rounded-lg border border-line bg-panel2 px-3 py-2.5 text-[13px] text-txt outline-none placeholder:text-dim disabled:opacity-60"
          />
          <button
            type="submit"
            disabled={busy || !email.trim()}
            className="mt-3 w-full rounded-lg border border-accent bg-accent px-3 py-2.5 text-[12.5px] font-semibold text-white disabled:opacity-50"
          >
            {state === "sending" ? "Sending..." : state === "sent" ? "Send another link" : "Send me a link"}
          </button>
        </form>

        {showCode ? (
          <form onSubmit={verifyCode} className="mt-3 rounded-[13px] border border-line bg-panel p-5">
            <label htmlFor="code" className="mono mb-2 block text-[10px] tracking-[0.14em] text-dim">
              OR PASTE THE CODE FROM THE EMAIL
            </label>
            <input
              id="code"
              name="code"
              inputMode="numeric"
              autoComplete="one-time-code"
              value={code}
              onChange={(e) => setCode(e.target.value)}
              disabled={busy}
              placeholder="123456"
              className="mono w-full rounded-lg border border-line bg-panel2 px-3 py-2.5 text-center text-[16px] tracking-[0.3em] text-txt outline-none placeholder:tracking-normal placeholder:text-dim disabled:opacity-60"
            />
            <button
              type="submit"
              disabled={busy || !code.trim() || !email.trim()}
              className="mt-3 w-full rounded-lg border border-line bg-panel2 px-3 py-2.5 text-[12.5px] font-semibold text-txt disabled:opacity-50"
            >
              {state === "verifying" ? "Checking..." : "Sign in with code"}
            </button>
            <p className="mt-2 text-center text-[11.5px] text-dim">
              The code works from any browser. The link only works in the one that asked for it.
            </p>
          </form>
        ) : null}

        <p
          role="status"
          aria-live="polite"
          className={`mt-3 min-h-[18px] px-1 text-center text-[12px] leading-relaxed ${
            isError ? "text-bad" : "text-dim"
          }`}
        >
          {message}
        </p>

        <p className="mt-3 text-center text-[11.5px] text-dim">
          No password. Both the link and the code expire.
        </p>
      </div>
    </main>
  );
}
