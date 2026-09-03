"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { saveState, saveProductName, acknowledgeRules } from "./actions";
import type { OnboardingState } from "./state";

// The nine steps from ONBOARDING.md. Every step is a tap or a picker; the only text field in
// the whole flow is the product name at step 2, and that is deliberate.
//
// Steps whose organs are not built yet do not pretend. They say what is missing and what will
// fill them, and they let Boss move on. A flow that blocks on a thing that does not exist is
// worse than one that is honest about where the build actually is.

export type CastMember = {
  code: string;
  name: string;
  role: string;
  description: string;
  prohibited: string[];
  loraId: string | null;
  voiceId: string | null;
};

export type StudioFacts = {
  universeName: string;
  premise: string;
  chunks: number;
  embedded: number;
  episodes: number;
};

const STEPS = [
  "Welcome",
  "The Show",
  "The Cast",
  "The Look",
  "The Voice",
  "The Story",
  "The Platforms",
  "The Rules",
  "First Episode",
] as const;

const PLATFORM_LABELS: Record<keyof OnboardingState["platforms"], string> = {
  tiktok: "TikTok",
  reels: "Instagram Reels",
  shorts: "YouTube Shorts",
  facebook: "Facebook",
  linkedin: "LinkedIn",
};

export function OnboardingFlow({
  initialState,
  cast,
  facts,
}: {
  initialState: OnboardingState;
  cast: CastMember[];
  facts: StudioFacts;
}) {
  const router = useRouter();
  const [state, setState] = useState(initialState);
  const [productName, setProductName] = useState(initialState.productName);
  const [error, setError] = useState("");
  const [pending, startTransition] = useTransition();

  const step = state.step;

  function go(patch: Partial<OnboardingState>) {
    setError("");
    startTransition(async () => {
      const res = await saveState(patch);
      if (!res.ok) return setError(res.error ?? "That did not save.");
      if (res.state) setState(res.state);
      router.refresh();
    });
  }

  function submitProductName() {
    setError("");
    startTransition(async () => {
      const res = await saveProductName(productName);
      if (!res.ok) return setError(res.error ?? "That did not save.");
      setState((s) => ({ ...s, productName: productName.trim(), step: 3 }));
      router.refresh();
    });
  }

  function ackRules() {
    setError("");
    startTransition(async () => {
      const res = await acknowledgeRules();
      if (!res.ok) return setError(res.error ?? "That did not save.");
      setState((s) => ({ ...s, rulesAcknowledged: true, step: 9 }));
      router.refresh();
    });
  }

  const confirmed = new Set(state.castConfirmed);
  const uc = cast.find((c) => c.code === "uncle_cred");

  return (
    <div className="mx-auto max-w-[720px]">
      <div className="mb-6">
        <div className="mono mb-2 text-[10px] tracking-[0.14em] text-dim">
          STEP {step} OF 9 · {STEPS[step - 1].toUpperCase()}
        </div>
        <div className="flex gap-1">
          {STEPS.map((s, i) => (
            <button
              key={s}
              type="button"
              onClick={() => go({ step: i + 1 })}
              disabled={pending}
              title={s}
              aria-label={`Step ${i + 1}, ${s}`}
              className={`h-1.5 flex-1 rounded-full transition-colors ${
                i + 1 === step ? "bg-cred" : i + 1 < step ? "bg-accent" : "bg-line"
              }`}
            />
          ))}
        </div>
      </div>

      <div className="rounded-[13px] border border-line bg-panel px-5 pb-4 pt-5">
        {step === 1 ? (
          <Step title="THIS IS YOUR STUDIO">
            <P>
              It writes a credit show, generates it, checks every claim against a knowledge base,
              and publishes it. Your job is three taps per episode: approve, send back, or kill.
            </P>
            <Facts
              rows={[
                ["Universe", facts.universeName],
                ["Cast in canon", `${cast.length} characters`],
                ["Credit knowledge", `${facts.embedded.toLocaleString()} of ${facts.chunks.toLocaleString()} chunks embedded`],
              ]}
            />
            <Primary onClick={() => go({ step: 2 })} pending={pending}>
              Start
            </Primary>
          </Step>
        ) : null}

        {step === 2 ? (
          <Step title="THE SHOW">
            <P>
              {facts.premise || "Education disguised as entertainment about credit and funding."}
            </P>
            <P dim>
              Every episode ends on a CTA frame naming the product this show sells. That is the one
              thing the studio cannot decide for you, and it is the only thing you have to type.
            </P>
            <label className="mono mb-2 mt-4 block text-[10px] tracking-[0.14em] text-dim">
              WHAT IS THE PRODUCT CALLED?
            </label>
            <input
              value={productName}
              onChange={(e) => setProductName(e.target.value)}
              disabled={pending}
              autoFocus
              placeholder="the credit and funding software"
              className="w-full rounded-lg border border-line bg-panel2 px-3 py-2.5 text-[13px] text-txt outline-none placeholder:text-dim disabled:opacity-60"
            />
            <Primary onClick={submitProductName} pending={pending} disabled={!productName.trim()}>
              Save and continue
            </Primary>
          </Step>
        ) : null}

        {step === 3 ? (
          <Step title="THE CAST">
            <P>
              Five characters, already written into canon with their relationships and the things
              that must never change about them. Tap each one to confirm.
            </P>
            <div className="mt-4 grid gap-2">
              {cast.map((c) => {
                const on = confirmed.has(c.code);
                return (
                  <button
                    key={c.code}
                    type="button"
                    disabled={pending}
                    onClick={() =>
                      go({
                        castConfirmed: on
                          ? state.castConfirmed.filter((x) => x !== c.code)
                          : [...state.castConfirmed, c.code],
                      })
                    }
                    className={`rounded-lg border px-3.5 py-3 text-left transition-colors ${
                      on ? "border-ok bg-panel2" : "border-line bg-panel2 hover:border-accent"
                    }`}
                  >
                    <div className="flex items-center justify-between">
                      <span className="disp text-[17px]">{c.name}</span>
                      <span className={`mono text-[10px] ${on ? "text-ok" : "text-dim"}`}>
                        {on ? "CONFIRMED" : "TAP TO CONFIRM"}
                      </span>
                    </div>
                    <div className="mt-1 text-[12px] text-dim">{c.description || c.role}</div>
                    {c.prohibited.length > 0 ? (
                      <div className="mono mt-1.5 text-[10px] text-warn">
                        NEVER: {c.prohibited.slice(0, 3).join(" · ")}
                      </div>
                    ) : null}
                  </button>
                );
              })}
            </div>
            <Primary
              onClick={() => go({ step: 4 })}
              pending={pending}
              disabled={confirmed.size < cast.length}
            >
              {confirmed.size < cast.length
                ? `Confirm all ${cast.length} to continue (${confirmed.size} done)`
                : "Continue"}
            </Primary>
          </Step>
        ) : null}

        {step === 4 ? (
          <Step title="THE LOOK">
            <P>
              A locked face per character. Uncle Cred is done: trained on your reference shoot and
              locked into canon, so every shot of him comes from the same identity.
            </P>
            <Facts
              rows={[
                ["Uncle Cred", uc?.loraId ? `LoRA ${uc.loraId} locked` : "not trained"],
                [
                  "The other four",
                  `${cast.filter((c) => !c.loraId).length} characters still need a face`,
                ],
              ]}
            />
            <NotBuilt
              what="Candidate generation for the other four"
              needs="The generation router is live and proven on Uncle Cred. Generating and picking faces for Auntie APR, Repo Reggie, Mr. Denied and Funding Frank is the next piece of Phase 02."
            />
            <Primary onClick={() => go({ step: 5 })} pending={pending}>
              Continue
            </Primary>
          </Step>
        ) : null}

        {step === 5 ? (
          <Step title="THE VOICE">
            <P>One voice per character, locked once and never regenerated.</P>
            <Facts
              rows={[
                ["Uncle Cred", uc?.voiceId ? `voice ${uc.voiceId} locked` : "not set"],
                [
                  "The other four",
                  `${cast.filter((c) => !c.voiceId).length} characters still need a voice`,
                ],
              ]}
            />
            <NotBuilt
              what="Voice generation"
              needs="ElevenLabs is not wired yet. It needs ELEVENLABS_API_KEY on the studio; the adapter slot already exists in the generation router."
            />
            <Primary onClick={() => go({ step: 6 })} pending={pending}>
              Continue
            </Primary>
          </Step>
        ) : null}

        {step === 6 ? (
          <Step title="THE STORY">
            <P>
              The season knows its ending before episode one is written. That is what makes it a
              drama and not a feed.
            </P>
            <Facts
              rows={[
                ["Premise", "Uncle Cred is LaSean, a retired crane operator who learned the system"],
                ["Midpoint", "Repo Reggie gets approved for the first time and nearly blows it"],
                ["Ending", "Mr. Denied stamps APPROVED, on Uncle Cred himself"],
              ]}
            />
            <NotBuilt
              what="The showrunner writing the arc into the database"
              needs="Phase 03. The arc above is written in STORY-BIBLE.md and needs studio.content_series rows with tracks and a locked ending before episodes can be scheduled against it."
            />
            <Primary onClick={() => go({ storyApproved: true, step: 7 })} pending={pending}>
              Approve this arc
            </Primary>
          </Step>
        ) : null}

        {step === 7 ? (
          <Step title="THE PLATFORMS">
            <P>Where the show goes. All on by default. Tap to turn one off.</P>
            <div className="mt-4 grid gap-2 sm:grid-cols-2">
              {(Object.keys(PLATFORM_LABELS) as Array<keyof OnboardingState["platforms"]>).map((k) => {
                const on = state.platforms[k];
                return (
                  <button
                    key={k}
                    type="button"
                    disabled={pending}
                    onClick={() => go({ platforms: { ...state.platforms, [k]: !on } })}
                    className={`flex items-center justify-between rounded-lg border px-3.5 py-2.5 text-left ${
                      on ? "border-ok bg-panel2" : "border-line bg-panel2 opacity-60"
                    }`}
                  >
                    <span className="text-[13px]">{PLATFORM_LABELS[k]}</span>
                    <span className={`mono text-[10px] ${on ? "text-ok" : "text-dim"}`}>
                      {on ? "ON" : "OFF"}
                    </span>
                  </button>
                );
              })}
            </div>
            <div className="mono mb-2 mt-4 text-[10px] tracking-[0.14em] text-dim">
              EPISODES PER DAY
            </div>
            <div className="flex gap-2">
              {[1, 2, 3].map((n) => (
                <button
                  key={n}
                  type="button"
                  disabled={pending}
                  onClick={() => go({ cadencePerDay: n })}
                  className={`flex-1 rounded-lg border px-3 py-2.5 text-[13px] font-semibold ${
                    state.cadencePerDay === n
                      ? "border-accent bg-accent text-white"
                      : "border-line bg-panel2 text-txt"
                  }`}
                >
                  {n}
                </button>
              ))}
            </div>
            <Primary onClick={() => go({ step: 8 })} pending={pending}>
              Continue
            </Primary>
          </Step>
        ) : null}

        {step === 8 ? (
          <Step title="THE RULES">
            <P>What the show never does. Already enforced in code, not left to a prompt.</P>
            <ul className="mt-4 grid gap-1.5">
              {[
                "Never gives legal advice. It teaches how credit works, never what you should legally do.",
                "Never guarantees a result or promises a score jump.",
                "Never claims accurate information can be removed.",
                "No character ever poses as a real customer or gives a testimonial.",
                "Every post carries an AI disclosure, doubled in the first seconds when it is paid.",
              ].map((r) => (
                <li
                  key={r}
                  className="rounded-lg border border-line bg-panel2 px-3.5 py-2.5 text-[12.5px] leading-relaxed"
                >
                  {r}
                </li>
              ))}
            </ul>
            <P dim>
              A lawyer signs off on these before the first public post. Acknowledging records a
              consent row in the ledger with your name on it.
            </P>
            <Primary onClick={ackRules} pending={pending}>
              {state.rulesAcknowledged ? "Acknowledged, continue" : "I understand"}
            </Primary>
          </Step>
        ) : null}

        {step === 9 ? (
          <Step title="FIRST EPISODE">
            <P>
              The last step writes your first episode on screen: title, hook, beats, and every
              credit claim verified against the knowledge base one at a time.
            </P>
            <Facts
              rows={[
                ["Knowledge ready", `${facts.embedded.toLocaleString()} chunks embedded and searchable`],
                ["Retrieval", "hybrid vector and full text, authority weighted"],
                ["Episodes so far", String(facts.episodes)],
              ]}
            />
            <NotBuilt
              what="The writers room"
              needs="Phase 03. Claim extraction, the verify loop and the compliance blocklist have to exist before an episode can be written, because nothing ships that has not been grounded."
            />
            <Primary
              onClick={() => go({ completed: true, completedAt: new Date().toISOString() })}
              pending={pending}
            >
              Finish setup and open the studio
            </Primary>
          </Step>
        ) : null}

        <p role="status" aria-live="polite" className="mt-3 min-h-[16px] text-[12px] text-bad">
          {error}
        </p>
      </div>

      <div className="mt-3 flex justify-between text-[12px] text-dim">
        <button
          type="button"
          disabled={pending || step === 1}
          onClick={() => go({ step: Math.max(1, step - 1) })}
          className="disabled:opacity-40"
        >
          Back
        </button>
        <span className="mono text-[10px] tracking-[0.12em]">
          PROGRESS SAVES AFTER EVERY TAP
        </span>
      </div>
    </div>
  );
}

function Step({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <>
      <h2 className="disp mb-3 text-[30px] leading-none">{title}</h2>
      {children}
    </>
  );
}

function P({ children, dim }: { children: React.ReactNode; dim?: boolean }) {
  return (
    <p className={`mt-2 text-[13.5px] leading-relaxed ${dim ? "text-dim" : "text-txt"}`}>{children}</p>
  );
}

function Facts({ rows }: { rows: Array<[string, string]> }) {
  return (
    <dl className="mt-4 grid gap-1.5">
      {rows.map(([k, v]) => (
        <div
          key={k}
          className="flex flex-wrap items-baseline justify-between gap-2 border-t border-dashed border-line pt-1.5 first:border-t-0 first:pt-0"
        >
          <dt className="mono text-[10px] tracking-[0.12em] text-dim">{k.toUpperCase()}</dt>
          <dd className="text-[12.5px]">{v}</dd>
        </div>
      ))}
    </dl>
  );
}

/** Honest about what does not exist yet, instead of a button that quietly does nothing. */
function NotBuilt({ what, needs }: { what: string; needs: string }) {
  return (
    <div className="mt-4 rounded-lg border border-dashed border-warn/50 bg-panel2 px-3.5 py-3">
      <div className="mono text-[10px] tracking-[0.12em] text-warn">NOT BUILT YET</div>
      <div className="mt-1 text-[12.5px] font-semibold">{what}</div>
      <p className="mt-1 text-[12px] leading-relaxed text-dim">{needs}</p>
    </div>
  );
}

function Primary({
  onClick,
  children,
  pending,
  disabled,
}: {
  onClick: () => void;
  children: React.ReactNode;
  pending: boolean;
  disabled?: boolean;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={pending || disabled}
      className="mt-5 w-full rounded-lg border border-accent bg-accent px-3 py-2.5 text-[12.5px] font-semibold text-white disabled:opacity-50"
    >
      {pending ? "Saving..." : children}
    </button>
  );
}
