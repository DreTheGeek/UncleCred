"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { decideEpisode } from "./actions";

// Three actions, one tap each. The note is optional and never blocks a decision.
export function DecisionBar({ episodeId }: { episodeId: string }) {
  const [note, setNote] = useState("");
  const [error, setError] = useState("");
  const [pending, startTransition] = useTransition();
  const router = useRouter();

  function decide(decision: "approve" | "send_back" | "kill") {
    setError("");
    startTransition(async () => {
      const res = await decideEpisode(episodeId, decision, note);
      if (!res.ok) {
        setError(res.error ?? "That did not go through.");
        return;
      }
      if (res.error) setError(res.error);
      setNote("");
      router.refresh();
    });
  }

  return (
    <div className="mt-4 border-t border-line pt-3.5">
      <div className="flex flex-col gap-2 sm:flex-row sm:items-center">
        <textarea
          value={note}
          onChange={(e) => setNote(e.target.value)}
          disabled={pending}
          placeholder="Note for the writers room or the director (optional)"
          className="h-[38px] flex-1 resize-none rounded-lg border border-line bg-panel2 px-2.5 py-2 text-[12.5px] text-txt placeholder:text-dim disabled:opacity-60"
        />
        <div className="flex gap-2">
          <button
            type="button"
            onClick={() => decide("kill")}
            disabled={pending}
            className="rounded-lg border border-line bg-panel px-3.5 py-2 text-[12.5px] font-semibold text-dim disabled:opacity-50"
          >
            Kill
          </button>
          <button
            type="button"
            onClick={() => decide("send_back")}
            disabled={pending}
            className="rounded-lg border border-line bg-panel px-3.5 py-2 text-[12.5px] font-semibold text-txt disabled:opacity-50"
          >
            Send back
          </button>
          <button
            type="button"
            onClick={() => decide("approve")}
            disabled={pending}
            className="rounded-lg border border-accent bg-accent px-3.5 py-2 text-[12.5px] font-semibold text-white disabled:opacity-50"
          >
            {pending ? "Working..." : "Approve"}
          </button>
        </div>
      </div>
      <p role="status" aria-live="polite" className="mt-2 min-h-[16px] text-[12px] text-bad">
        {error}
      </p>
    </div>
  );
}
