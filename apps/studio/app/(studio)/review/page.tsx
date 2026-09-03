import { createClient } from "@/lib/supabase/server";
import { READY_FOR_LASEAN } from "@/lib/constants";
import { EmptyState, ErrorState, NoMembershipState } from "@/components/EmptyState";
import { DecisionBar } from "./DecisionBar";

export const dynamic = "force-dynamic";

type Episode = {
  id: string;
  episode_code: string;
  working_title: string;
  status: string;
  cta: string | null;
  viewer_promise: string | null;
  opening: string | null;
  first_payoff: string | null;
  retention_beats: unknown;
  created_at: string;
};

export default async function ReviewRoom({
  searchParams,
}: {
  searchParams: Promise<{ ep?: string }>;
}) {
  const { ep } = await searchParams;
  const supabase = await createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();

  const { data, error } = await supabase
    .schema("studio")
    .from("episodes")
    .select(
      "id, episode_code, working_title, status, cta, viewer_promise, opening, first_payoff, retention_beats, created_at",
    )
    .eq("status", READY_FOR_LASEAN)
    .order("created_at", { ascending: true });

  if (error) {
    console.error("review room query failed", error);
    return (
      <>
        <Header count={0} />
        <ErrorState what="the review queue" />
      </>
    );
  }

  const episodes = (data ?? []) as Episode[];

  if (episodes.length === 0) {
    // Distinguish "nothing waiting" from "RLS is hiding everything". A signed in owner with
    // no membership row sees zero rows on every table, which is not the same as an empty queue.
    const { count: anyEpisodes } = await supabase
      .schema("studio")
      .from("episodes")
      .select("id", { count: "exact", head: true });
    const { count: anyCharacters } = await supabase
      .schema("studio")
      .from("visual_characters")
      .select("id", { count: "exact", head: true });

    const invisible = (anyEpisodes ?? 0) === 0 && (anyCharacters ?? 0) === 0;

    return (
      <>
        <Header count={0} />
        {invisible ? (
          <NoMembershipState email={user?.email ?? undefined} />
        ) : (
          <EmptyState
            title="NOTHING WAITING ON YOU"
            fills={
              "Episodes land here after they clear every gate: grounding verifies each claim, the blocklist passes, shot QA clears identity and photorealism, and the disclosure frame is injected. When one finishes, it appears here with three buttons and nothing else to decide."
            }
            hint={`QUEUE IS EMPTY, ${anyEpisodes ?? 0} EPISODES IN THE STUDIO`}
          />
        )}
      </>
    );
  }

  const selected = episodes.find((e) => e.id === ep) ?? episodes[0];

  return (
    <>
      <Header count={episodes.length} />
      <div className="grid gap-4 lg:grid-cols-[300px_1fr]">
        <div className="flex gap-2 overflow-x-auto lg:block lg:overflow-visible">
          {episodes.map((e) => {
            const on = e.id === selected.id;
            return (
              <a
                key={e.id}
                href={`/review?ep=${e.id}`}
                className={`mb-2 block min-w-[220px] rounded-lg border bg-panel px-2.5 py-2.5 lg:min-w-0 ${
                  on ? "border-cred shadow-[0_0_0_1px_var(--cred)]" : "border-line"
                }`}
              >
                <div className="text-[12.5px] font-semibold leading-tight">{e.working_title}</div>
                <div className="mono mt-1.5 flex justify-between text-[10.5px] text-dim">
                  <span>{e.episode_code}</span>
                  <span className="rounded-[5px] bg-cred/20 px-1.5 py-px text-cred">YOU</span>
                </div>
              </a>
            );
          })}
        </div>

        <div className="rounded-[13px] border border-line bg-panel px-4 pb-3 pt-3.5">
          <div className="mb-3">
            <div className="mono text-[10.5px] tracking-[0.12em] text-dim">
              {selected.episode_code}
            </div>
            <h3 className="disp text-[26px] leading-tight">{selected.working_title}</h3>
          </div>

          <dl className="grid gap-2 text-[12.5px]">
            <Field label="VIEWER PROMISE" value={selected.viewer_promise} />
            <Field label="OPENING" value={selected.opening} />
            <Field label="FIRST PAYOFF" value={selected.first_payoff} />
            <Field label="CTA" value={selected.cta} />
          </dl>

          <DecisionBar episodeId={selected.id} />
        </div>
      </div>
    </>
  );
}

function Header({ count }: { count: number }) {
  return (
    <div className="mb-5">
      <h1 className="disp text-[28px] leading-none">REVIEW ROOM</h1>
      <div className="mt-4">
        <h2 className="disp text-[40px] leading-[0.95]">
          {count > 0 ? `${count} WAITING ON YOU.` : "NOTHING WAITING ON YOU."}
        </h2>
        <p className="mt-2 max-w-[640px] text-[13.5px] text-dim">
          Everything here passed every gate. Your job is taste, not QA. Approve, send back with a
          note, or kill.
        </p>
      </div>
    </div>
  );
}

function Field({ label, value }: { label: string; value: string | null }) {
  return (
    <div className="border-t border-dashed border-line pt-2 first:border-t-0 first:pt-0">
      <dt className="mono text-[10px] tracking-[0.12em] text-dim">{label}</dt>
      <dd className="mt-1">{value ?? <span className="text-dim">Not written yet.</span>}</dd>
    </div>
  );
}
