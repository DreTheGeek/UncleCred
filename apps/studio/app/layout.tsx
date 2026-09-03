import type { Metadata, Viewport } from "next";
import "./globals.css";
import { resolveSupabaseEnv } from "@/lib/supabase/env";

export const metadata: Metadata = {
  title: "Uncle Cred Studio",
  description: "The studio that writes, shoots, and ships the show.",
  robots: { index: false, follow: false },
};

// Every route renders per request so the layout can read runtime env and hand it to the
// browser. Nothing here benefits from static prerendering: it is a single operator tool
// whose every screen is live data behind auth.
export const dynamic = "force-dynamic";

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  themeColor: "#0a0d12",
};

// Runtime config handoff.
//
// NEXT_PUBLIC_* is inlined at build time. On this project those values are not visible to
// the build (Vercel keeps sensitive variables runtime-only), so the browser bundle comes
// out with no Supabase config and every client call throws. The server can still read the
// values at runtime, so it writes them into the document for the browser to pick up.
//
// This exposes only the publishable (anon) key, which is designed to be public: it is
// shipped to browsers in every Supabase app and is powerless without RLS granting access.
// The service role key is never read here and never reaches the client.
//
// Emitted as application/json rather than executable JS, and "<" is escaped, so page
// content cannot break out of the tag.
function RuntimeConfig() {
  const resolved = resolveSupabaseEnv();
  if (!resolved.ok) return null;
  const json = JSON.stringify({ url: resolved.env.url, key: resolved.env.key }).replace(
    /</g,
    "\\u003c",
  );
  return (
    <script
      id="__uc_runtime_config"
      type="application/json"
      dangerouslySetInnerHTML={{ __html: json }}
    />
  );
}

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" data-mode="night">
      <head>
        <RuntimeConfig />
      </head>
      <body className="min-h-screen bg-bg text-txt antialiased">{children}</body>
    </html>
  );
}
