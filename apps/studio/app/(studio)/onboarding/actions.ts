"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { ORG_ID } from "@/lib/constants";
import { OnboardingState } from "./state";

// Progress lives in platform.organizations.metadata.onboarding so a refresh resumes exactly
// where Boss left off (ONBOARDING.md). It is a merge, never a replace: that column is shared
// and the LoRA lesson from train-lora applies here too.

export async function readState(): Promise<OnboardingState> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .schema("platform")
    .from("organizations")
    .select("metadata")
    .eq("id", ORG_ID)
    .single();
  if (error) {
    console.error("onboarding read failed:", error.message);
    return OnboardingState.parse({});
  }
  const raw = (data?.metadata as Record<string, unknown> | null)?.onboarding;
  const parsed = OnboardingState.safeParse(raw ?? {});
  return parsed.success ? parsed.data : OnboardingState.parse({});
}

export async function saveState(
  patch: Partial<OnboardingState>,
): Promise<{ ok: boolean; error?: string; state?: OnboardingState }> {
  const supabase = await createClient();

  const { data: row, error: readErr } = await supabase
    .schema("platform")
    .from("organizations")
    .select("metadata")
    .eq("id", ORG_ID)
    .single();
  if (readErr) return { ok: false, error: "Could not read your studio settings." };

  const metadata = (row?.metadata as Record<string, unknown>) ?? {};
  const current = OnboardingState.safeParse(metadata.onboarding ?? {});
  const merged = OnboardingState.parse({
    ...(current.success ? current.data : {}),
    ...patch,
  });

  // Merge into metadata, never replace it.
  const { data: updated, error: updErr } = await supabase
    .schema("platform")
    .from("organizations")
    .update({ metadata: { ...metadata, onboarding: merged } })
    .eq("id", ORG_ID)
    .select("id");
  if (updErr) {
    console.error("onboarding save failed:", updErr.message);
    return { ok: false, error: "That did not save. Nothing was lost, try again." };
  }
  if (!updated || updated.length !== 1) {
    return { ok: false, error: "Nothing saved. You may not have write access to the studio yet." };
  }

  revalidatePath("/onboarding");
  revalidatePath("/command-center");
  return { ok: true, state: merged };
}

/** Step 2 writes the product name into canon so every CTA frame can read one value. */
export async function saveProductName(name: string): Promise<{ ok: boolean; error?: string }> {
  const clean = name.trim();
  if (!clean) return { ok: false, error: "The product needs a name. Every episode ends on it." };
  if (clean.length > 80) return { ok: false, error: "Keep it under 80 characters." };

  const supabase = await createClient();
  const { data: u, error: uErr } = await supabase
    .schema("platform")
    .from("universes")
    .select("id, metadata")
    .eq("code", "uncle_cred")
    .single();
  if (uErr) return { ok: false, error: "Could not find the universe row." };

  const meta = (u?.metadata as Record<string, unknown>) ?? {};
  const { error } = await supabase
    .schema("platform")
    .from("universes")
    .update({ metadata: { ...meta, product_name: clean } })
    .eq("id", u.id);
  if (error) {
    console.error("product name write failed:", error.message);
    return { ok: false, error: "Could not save the product name." };
  }

  const saved = await saveState({ productName: clean, step: 3 });
  if (!saved.ok) return saved;

  const { data: { user } } = await supabase.auth.getUser();
  await supabase.schema("system").rpc("emit_event", {
    p_org: ORG_ID,
    p_type: "onboarding.product_named",
    p_table: "platform.universes",
    p_id: u.id,
    p_payload: { product_name: clean },
    p_actor: user?.email ?? "owner",
  });
  return { ok: true };
}

/** Step 8 is a real consent record, not a checkbox that goes nowhere. */
export async function acknowledgeRules(): Promise<{ ok: boolean; error?: string }> {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  const saved = await saveState({ rulesAcknowledged: true, step: 9 });
  if (!saved.ok) return saved;
  await supabase.schema("system").rpc("emit_event", {
    p_org: ORG_ID,
    p_type: "onboarding.rules_acknowledged",
    p_table: null,
    p_id: null,
    p_payload: {
      rules: [
        "no legal advice",
        "no guarantees or score jump promises",
        "never claim removal of accurate information",
        "no character poses as a real customer",
        "AI disclosure on every post",
      ],
    },
    p_actor: user?.email ?? "owner",
  });
  return { ok: true };
}

/**
 * Step 4. Boss taps the candidate that is them; that image becomes the canonical front
 * reference the turnaround, expression sheets and LoRA all derive from.
 *
 * The picked candidate is marked chosen and the rest rejected rather than deleted. DECISIONS
 * keeps both rejected identity rounds on the Uncle Cred row for exactly this reason: knowing
 * what was turned down is how you avoid regenerating it.
 */
export async function pickFace(
  characterCode: string,
  slot: number,
): Promise<{ ok: boolean; error?: string }> {
  const supabase = await createClient();
  const { data: row, error: readErr } = await supabase
    .schema("studio")
    .from("visual_characters")
    .select("id, name, reference_assets")
    .eq("character_code", characterCode)
    .single();
  if (readErr || !row) return { ok: false, error: "That character is not in canon." };

  const ra = row.reference_assets as Record<string, unknown>;
  const candidates = Array.isArray(ra?.face_candidates)
    ? (ra.face_candidates as Array<Record<string, unknown>>)
    : [];
  const chosen = candidates.find((c) => Number(c.slot) === slot);
  if (!chosen) return { ok: false, error: "That candidate is no longer there. Reload." };

  const next = {
    ...ra,
    face_master: chosen.path,
    face_master_sha256: chosen.sha256 ?? null,
    face_master_picked_at: new Date().toISOString(),
    face_candidates: candidates.map((c) => ({
      ...c,
      status: Number(c.slot) === slot ? "chosen" : "rejected",
    })),
  };

  const { data: upd, error: updErr } = await supabase
    .schema("studio")
    .from("visual_characters")
    .update({ reference_assets: next })
    .eq("id", row.id)
    .select("id");
  if (updErr) {
    console.error("pickFace write failed:", updErr.message);
    return { ok: false, error: "Could not save that pick." };
  }
  if (!updated1(upd)) return { ok: false, error: "Nothing saved. Check your access." };

  const { data: { user } } = await supabase.auth.getUser();
  await supabase.schema("system").rpc("emit_event", {
    p_org: ORG_ID,
    p_type: "canon.face_master.picked",
    p_table: "studio.visual_characters",
    p_id: row.id,
    p_payload: { character_code: characterCode, slot, path: chosen.path },
    p_actor: user?.email ?? "owner",
  });

  revalidatePath("/onboarding");
  return { ok: true };
}

function updated1(rows: unknown): boolean {
  return Array.isArray(rows) && rows.length === 1;
}
