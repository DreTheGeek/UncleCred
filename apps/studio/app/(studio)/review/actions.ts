"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

// The three decisions, one tap each. Approve, Send back, Kill.
// Every one writes the episode row and one immutable ledger event, in that order.
// Nothing here asks a second question; the note is optional and free text.

type Decision = "approve" | "send_back" | "kill";

const TARGET: Record<Decision, { status: string; event: string }> = {
  approve: { status: "approved", event: "episode.approved" },
  send_back: { status: "in_progress", event: "episode.sent_back" },
  kill: { status: "killed", event: "episode.killed" },
};

export async function decideEpisode(
  episodeId: string,
  decision: Decision,
  note?: string,
): Promise<{ ok: boolean; error?: string }> {
  const target = TARGET[decision];
  if (!target) return { ok: false, error: "Unknown decision." };

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return { ok: false, error: "Not signed in." };

  // Read first so the ledger event can carry the org and the prior status.
  const { data: episode, error: readErr } = await supabase
    .schema("studio")
    .from("episodes")
    .select("id, organization_id, status, episode_code, working_title")
    .eq("id", episodeId)
    .single();
  if (readErr || !episode) {
    console.error("decideEpisode read failed", readErr);
    return { ok: false, error: "That episode is no longer there. Reload." };
  }

  const { data: updated, error: updErr } = await supabase
    .schema("studio")
    .from("episodes")
    .update({ status: target.status, updated_at: new Date().toISOString() })
    .eq("id", episodeId)
    .select("id");
  if (updErr) {
    console.error("decideEpisode update failed", updErr);
    return { ok: false, error: "The studio did not accept that. Nothing changed." };
  }
  if (!updated || updated.length !== 1) {
    // RLS returning zero rows looks identical to a missing row. Say so plainly.
    return { ok: false, error: "Nothing was updated. You may not have write access yet." };
  }

  const { error: evErr } = await supabase.schema("system").rpc("emit_event", {
    p_org: episode.organization_id,
    p_type: target.event,
    p_table: "studio.episodes",
    p_id: episode.id,
    p_payload: {
      episode_code: episode.episode_code,
      working_title: episode.working_title,
      from_status: episode.status,
      to_status: target.status,
      note: note?.trim() || null,
    },
    p_actor: user.email ?? "owner",
  });
  if (evErr) {
    // The decision landed. Say so, but do not pretend the ledger is complete.
    console.error("decideEpisode emit_event failed", evErr);
    return { ok: true, error: "Decision saved, but it did not reach the ledger." };
  }

  revalidatePath("/review");
  revalidatePath("/command-center");
  return { ok: true };
}
