import { createClient } from "@/lib/supabase/server";
import { getMembership } from "@/lib/membership";
import { NoMembershipState, ErrorState } from "@/components/EmptyState";
import { readState } from "./actions";
import { OnboardingFlow, type CastMember, type StudioFacts } from "./OnboardingFlow";

export const dynamic = "force-dynamic";

export default async function OnboardingPage() {
  const membership = await getMembership();
  if (membership.state !== "member") {
    return (
      <>
        <h1 className="disp mb-5 text-[28px] leading-none">WELCOME</h1>
        {membership.state === "not_member" ? <NoMembershipState /> : <ErrorState what="your membership" />}
      </>
    );
  }

  const supabase = await createClient();
  const state = await readState();

  const { data: cast } = await supabase
    .schema("studio")
    .from("visual_characters")
    .select("character_code, name, description, prohibited_changes, metadata, reference_assets")
    .order("character_code");

  const members: CastMember[] = await Promise.all((cast ?? []).map(async (c) => {
    const meta = (c.metadata ?? {}) as Record<string, unknown>;
    const lora = meta.lora as { id?: string } | undefined;
    const voice = meta.voice as { voice_id?: string } | undefined;
    const ra = (c.reference_assets ?? {}) as Record<string, unknown>;
    const raw = Array.isArray(ra.face_candidates)
      ? (ra.face_candidates as Array<Record<string, unknown>>)
      : [];

    const candidates = await Promise.all(
      raw.map(async (cand) => {
        const full = String(cand.path ?? "");
        const key = full.startsWith("canon/") ? full.slice("canon/".length) : full;
        const { data: signed } = await supabase.storage.from("canon").createSignedUrl(key, 3600);
        return {
          slot: Number(cand.slot),
          url: signed?.signedUrl ?? null,
          status: String(cand.status ?? "candidate"),
        };
      }),
    );

    return {
      code: c.character_code as string,
      name: c.name as string,
      role: (meta.role as string) ?? "",
      description: (c.description as string) ?? "",
      prohibited: (c.prohibited_changes as string[]) ?? [],
      loraId: lora?.id ?? null,
      voiceId: voice?.voice_id ?? null,
      faceMaster: (ra.face_master as string) ?? null,
      candidates,
    };
  }));

  const head = { count: "exact" as const, head: true };
  const [chunks, embedded, episodes] = await Promise.all([
    supabase.schema("knowledge").from("document_chunks").select("id", head),
    supabase.schema("knowledge").from("document_chunks").select("id", head).not("embedding", "is", null),
    supabase.schema("studio").from("episodes").select("id", head),
  ]);

  const { data: universe } = await supabase
    .schema("platform")
    .from("universes")
    .select("name, premise, metadata")
    .eq("code", "uncle_cred")
    .maybeSingle();

  const facts: StudioFacts = {
    universeName: (universe?.name as string) ?? "Uncle Cred",
    premise: (universe?.premise as string) ?? "",
    chunks: chunks.count ?? 0,
    embedded: embedded.count ?? 0,
    episodes: episodes.count ?? 0,
  };

  return <OnboardingFlow initialState={state} cast={members} facts={facts} />;
}
