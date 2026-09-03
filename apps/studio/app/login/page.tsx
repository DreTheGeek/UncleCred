"use client";

import { useState } from "react";
import { createClient } from "@/lib/supabase/client";

// One email box, one button. No password field, no signup page, per the ruling.
// First signup becomes owner through the uc_bootstrap_first_owner trigger on auth.users,
// so there is nothing for this screen to branch on.
export default function LoginPage() {
  const [email, setEmail] = useState("");
  const [state, setState] = useState<"idle" | "sending" | "sent" | "error">("idle");
  const [message, setMessage] = useState("");

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!email.trim()) return;
    setState("sending");
    const supabase = createClient();
    const siteUrl = process.env.NEXT_PUBLIC_SITE_URL ?? window.location.origin;
    const next = new URLSearchParams(window.location.search).get("next") ?? "/";
    const { error } = await supabase.auth.signInWithOtp({
      email: email.trim(),
      options: { emailRedirectTo: `${siteUrl}/auth/callback?next=${encodeURIComponent(next)}` },
    });
    if (error) {
      // Sanitized. The real error goes to the server log, not the screen.
      console.error("signInWithOtp failed", error);
      setMessage("That did not send. Try again in a moment.");
      setState("error");
      return;
    }
    setMessage(`Link sent to ${email.trim()}. Open it on this device.`);
    setState("sent");
  }

  return (
    <main className="grid min-h-screen place-items-center px-5">
      <div className="w-full max-w-[380px]">
        <div className="mb-8 text-center">
          <div className="disp text-[34px] leading-none text-cred">UNCLE CRED</div>
          <div className="mono mt-1 text-[10px] tracking-[0.14em] text-dim">
            STUDIO / KALDR BUSINESS GROUP
          </div>
        </div>

        <form
          onSubmit={onSubmit}
          className="rounded-[13px] border border-line bg-panel p-5"
          noValidate
        >
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
            disabled={state === "sending"}
            placeholder="you@kaldrbusiness.com"
            className="w-full rounded-lg border border-line bg-panel2 px-3 py-2.5 text-[13px] text-txt outline-none placeholder:text-dim disabled:opacity-60"
          />
          <button
            type="submit"
            disabled={state === "sending" || !email.trim()}
            className="mt-3 w-full rounded-lg border border-accent bg-accent px-3 py-2.5 text-[12.5px] font-semibold text-white disabled:opacity-50"
          >
            {state === "sending" ? "Sending..." : "Send me a link"}
          </button>

          <p
            role="status"
            aria-live="polite"
            className={`mt-3 min-h-[18px] text-center text-[12px] ${
              state === "error" ? "text-bad" : "text-dim"
            }`}
          >
            {message}
          </p>
        </form>

        <p className="mt-4 text-center text-[11.5px] text-dim">
          No password. The link signs you in and expires.
        </p>
      </div>
    </main>
  );
}
