import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { READY_FOR_LASEAN } from "@/lib/constants";

// The click law: home is the Review Room when anything is waiting on Boss,
// the Command Center otherwise. He never picks.
export default async function Home() {
  const supabase = await createClient();
  const { count, error } = await supabase
    .schema("studio")
    .from("episodes")
    .select("id", { count: "exact", head: true })
    .eq("status", READY_FOR_LASEAN);

  // On error, send him to the Command Center. It degrades to a readable screen;
  // the Review Room would look broken.
  if (error) {
    console.error("home routing count failed", error);
    redirect("/command-center");
  }
  redirect((count ?? 0) > 0 ? "/review" : "/command-center");
}
