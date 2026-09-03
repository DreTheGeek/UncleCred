import { createClient } from "@/lib/supabase/server";
import { ORG_ID } from "@/lib/constants";

// Ask the question directly instead of inferring it.
//
// The first version guessed: if every count came back zero, assume no membership. That was
// wrong in a way that mattered. On 2026-09-03 RLS was recursing (is_org_member was SECURITY
// INVOKER and the policy on organization_members called it, so every authenticated query
// died with stack depth exceeded). Zero counts looked identical to no membership, so the app
// blamed the user for a database fault. A zero count and a broken read are different facts
// and must be reported differently.
export type Membership =
  | { state: "member"; role: string }
  | { state: "not_member" }
  | { state: "unreadable"; error: string };

export async function getMembership(): Promise<Membership> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return { state: "not_member" };

  const { data, error } = await supabase
    .schema("platform")
    .from("organization_members")
    .select("role, status")
    .eq("organization_id", ORG_ID)
    .eq("user_id", user.id)
    .eq("status", "active")
    .maybeSingle();

  if (error) {
    console.error("membership read failed:", error.message);
    return { state: "unreadable", error: error.message };
  }
  return data ? { state: "member", role: data.role } : { state: "not_member" };
}
