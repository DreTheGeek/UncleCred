import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { READY_FOR_LASEAN } from "@/lib/constants";
import { EmptyState, NoMembershipState } from "@/components/EmptyState";

export const dynamic = "force-dynamic";

// The Command Center reports and offers one primary button. It never asks for input.
export default async function CommandCenter() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  // Returns null when the query itself fails, so "not readable" renders differently from zero.
  const toCount = async (
    q: PromiseLike<{ count: number | null; error: unknown }>,
  ): Promise<number | null> => {
    const { count, error } = await q;
    return error ? null : (count ?? 0);
  };
  const head = { count: "exact" as const, head: true };

  const [waiting, episodes, characters, chunks, embedded, stages, events] = await Promise.all([
    toCount(supabase.schema("studio").from("episodes").select("id", head).eq("status", READY_FOR_LASEAN)),
    toCount(supabase.schema("studio").from("episodes").select("id", head)),
    toCount(supabase.schema("studio").from("visual_characters").select("id", head)),
    toCount(supabase.schema("knowledge").from("document_chunks").select("id", head)),
    toCount(supabase.schema("knowledge").from("document_chunks").select("id", head).not("embedding", "is", null)),
    toCount(supabase.schema("studio").from("pipeline_stages").select("id", head)),
    toCount(supabase.schema("system").from("system_events").select("id", head)),
  ]);

  // Every readable table returning zero is the signature of a session with no org membership.
  const invisible =
    (episodes ?? 0) === 0 && (characters ?? 0) === 0 && (chunks ?? 0) === 0 && (events ?? 0) === 0;

  if (invisible) {
    return (
      <>
        <h1 className="disp mb-5 text-[28px] leading-none">COMMAND CENTER</h1>
        <NoMembershipState email={user?.email ?? undefined} />
      </>
    );
  }

  const embedPct = chunks && chunks > 0 ? Math.round(((embedded ?? 0) / chunks) * 100) : 0;

  return (
    <>
      <div className="mb-5">
        <h1 className="disp text-[28px] leading-none">COMMAND CENTER</h1>
        <div className="mt-4 flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
          <div>
            <h2 className="disp text-[40px] leading-[0.95]">
              {(waiting ?? 0) > 0 ? `${waiting} WAITING ON YOU.` : "NOTHING WAITING ON YOU."}
            </h2>
            <p className="mt-2 max-w-[640px] text-[13.5px] text-dim">
              The studio runs itself. This screen tells you what it did and what it needs.
            </p>
          </div>
          {(waiting ?? 0) > 0 ? (
            <Link
              href="/review"
              className="rounded-lg border border-accent bg-accent px-3.5 py-2.5 text-center text-[12.5px] font-semibold text-white"
            >
              Open the Review Room
            </Link>
          ) : null}
        </div>
      </div>

      <div className="mb-4 grid grid-cols-2 gap-3 md:grid-cols-4">
        <Kpi k="WAITING ON YOU" v={waiting} c="episodes past every gate" />
        <Kpi k="CAST" v={characters} c="characters in canon" />
        <Kpi
          k="CREDIT KNOWLEDGE"
          v={embedPct}
          suffix="%"
          c={`${(embedded ?? 0).toLocaleString()} of ${(chunks ?? 0).toLocaleString()} chunks embedded`}
        />
        <Kpi k="LEDGER" v={events} c="events recorded, never edited" />
      </div>

      <section className="mb-4 rounded-[13px] border border-line bg-panel px-4 pb-3 pt-3.5">
        <div className="mb-3 flex items-center justify-between">
          <h3 className="disp text-[20px] tracking-[0.03em]">THE LINE</h3>
          <span className="mono text-[10.5px] text-dim">
            {(stages ?? 0).toLocaleString()} STAGES
          </span>
        </div>
        {(stages ?? 0) === 0 ? (
          <EmptyState
            title="THE LINE IS COLD"
            fills="A pipeline run is created when an asset enters the assembly line. It lays down 14 stages, from intake through human review to publish, and the cron workers walk them one at a time. The moment the first run starts, every stage shows up here with who claimed it and how long it took."
            hint="NO PIPELINE RUNS YET"
          />
        ) : (
          <p className="text-[12.5px] text-dim">
            {stages} stages exist. The stage board lands with the production line in Phase 04.
          </p>
        )}
      </section>

      <section className="rounded-[13px] border border-line bg-panel px-4 pb-3 pt-3.5">
        <div className="mb-3 flex items-center justify-between">
          <h3 className="disp text-[20px] tracking-[0.03em]">EPISODES</h3>
          <span className="mono text-[10.5px] text-dim">{(episodes ?? 0).toLocaleString()}</span>
        </div>
        {(episodes ?? 0) === 0 ? (
          <EmptyState
            title="NO EPISODES YET"
            fills="The writers room produces an episode blueprint from the season arc and the credit knowledge base: title, hook, beats, and every claim checked against a source before it can ship. The first one is written during onboarding, on screen, while you watch."
            hint="ONBOARDING STEP 9 WRITES THE FIRST ONE"
          />
        ) : (
          <p className="text-[12.5px] text-dim">
            {episodes} episodes in the studio, {waiting ?? 0} waiting on you.
          </p>
        )}
      </section>
    </>
  );
}

function Kpi({
  k,
  v,
  c,
  suffix = "",
}: {
  k: string;
  v: number | null;
  c: string;
  suffix?: string;
}) {
  return (
    <div className="rounded-xl border border-line bg-panel px-3.5 pb-2.5 pt-3">
      <div className="mono text-[10px] uppercase tracking-[0.14em] text-dim">{k}</div>
      <div className="disp my-1.5 text-[34px] leading-none">
        {v === null ? "--" : v.toLocaleString()}
        {v === null ? "" : suffix}
      </div>
      <div className="text-[11.5px] text-dim">{v === null ? "not readable" : c}</div>
    </div>
  );
}
