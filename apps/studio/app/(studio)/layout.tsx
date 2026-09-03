import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { READY_FOR_LASEAN } from "@/lib/constants";
import { SignOutButton } from "@/components/SignOutButton";

// Shell ported from apps/studio-mockups (sidebar 224px, main, no right rail at v1).
// Nav items with no page yet are rendered as plain text, not dead links. The click law
// says a screen never dead-ends; a link that goes nowhere is a dead end.
const NAV: Array<{ group: string; items: Array<{ label: string; href?: string }> }> = [
  {
    group: "",
    items: [
      { label: "Command Center", href: "/command-center" },
      { label: "Review Room", href: "/review" },
      { label: "Setup", href: "/onboarding" },
    ],
  },
  {
    group: "Universe",
    items: [{ label: "Characters" }, { label: "Canon" }, { label: "Locations & Props" }],
  },
  {
    group: "Production",
    items: [{ label: "Writers Room" }, { label: "Episodes" }, { label: "Pipeline" }, { label: "Asset Library" }],
  },
  {
    group: "Distribution",
    items: [{ label: "Calendar" }, { label: "Publishing" }, { label: "Analytics" }],
  },
  {
    group: "Intelligence",
    items: [{ label: "Learnings" }, { label: "Experiments" }, { label: "Knowledge" }, { label: "AI Ops & Cost" }],
  },
];

export default async function StudioLayout({ children }: { children: React.ReactNode }) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const { count: waiting } = await supabase
    .schema("studio")
    .from("episodes")
    .select("id", { count: "exact", head: true })
    .eq("status", READY_FOR_LASEAN);

  const email = user?.email ?? "";
  const initials = email ? email.slice(0, 2).toUpperCase() : "??";

  return (
    <div className="grid min-h-screen grid-cols-1 md:grid-cols-[224px_1fr]">
      <aside className="sticky top-0 hidden h-screen flex-col overflow-y-auto border-r border-line bg-panel2 px-3 py-4 md:flex">
        <div className="px-2.5 pb-0.5 pt-1">
          <div className="disp text-[26px] leading-none text-cred">UNCLE CRED</div>
          <div className="mono mt-0.5 text-[10px] tracking-[0.14em] text-dim">
            STUDIO / KALDR BUSINESS GROUP
          </div>
        </div>

        <div className="mb-2 mt-3.5 flex items-center gap-2.5 border-b border-line px-2.5 pb-3.5">
          <div className="disp grid h-9 w-9 place-items-center rounded-[10px] bg-gradient-to-br from-accent to-[#0b2a6b] text-[16px] text-white">
            {initials}
          </div>
          <div className="min-w-0">
            <b className="block truncate text-[13px]">{email || "Signed in"}</b>
            <span className="text-[11px] text-dim">Owner, Executive Producer</span>
          </div>
        </div>

        <div className="mx-2.5 mb-3.5 flex justify-between rounded-lg border border-line bg-panel px-2.5 py-2 text-[12px]">
          <span>Universe</span>
          <em className="mono not-italic text-[11px] text-cred">uncle_cred</em>
        </div>

        <nav className="flex-1">
          {NAV.map((section) => (
            <div key={section.group || "top"}>
              {section.group ? (
                <div className="mono mx-2.5 mb-1.5 mt-3.5 text-[10px] uppercase tracking-[0.14em] text-dim">
                  {section.group}
                </div>
              ) : null}
              {section.items.map((item) =>
                item.href ? (
                  <Link
                    key={item.label}
                    href={item.href}
                    className="mb-0.5 flex items-center justify-between rounded-lg px-2.5 py-1.5 text-[13px] text-dim hover:bg-panel hover:text-txt"
                  >
                    {item.label}
                    {item.href === "/review" && (waiting ?? 0) > 0 ? (
                      <span className="mono rounded-[5px] bg-cred/20 px-1.5 py-px text-[10px] text-cred">
                        {waiting}
                      </span>
                    ) : null}
                  </Link>
                ) : (
                  <div
                    key={item.label}
                    className="mb-0.5 flex cursor-default items-center justify-between rounded-lg px-2.5 py-1.5 text-[13px] text-dim/50"
                    title="Not built yet"
                  >
                    {item.label}
                    <span className="mono text-[9px] tracking-[0.1em] text-dim/50">SOON</span>
                  </div>
                ),
              )}
            </div>
          ))}
        </nav>

        <div className="mt-4 flex justify-between px-2.5 pt-3 text-[12px] text-dim">
          <SignOutButton />
        </div>
      </aside>

      <main className="min-w-0 px-4 pb-20 pt-4 md:px-6">{children}</main>

      <nav className="fixed inset-x-0 bottom-0 z-10 flex justify-around border-t border-line bg-panel2 px-1.5 py-2 md:hidden">
        <Link href="/command-center" className="mono text-[10px] uppercase tracking-[0.08em] text-dim">
          Home
        </Link>
        <Link href="/review" className="mono text-[10px] uppercase tracking-[0.08em] text-cred">
          Review{(waiting ?? 0) > 0 ? ` (${waiting})` : ""}
        </Link>
      </nav>
    </div>
  );
}
