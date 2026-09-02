// Phase 01 gate task: proves Trigger.dev, Supabase, and R2 round trip from one run.
import { task, wait, logger } from "@trigger.dev/sdk/v3";
import { createClient } from "@supabase/supabase-js";
import { putObject } from "../lib/r2.js";

export const hello = task({
  id: "fds.hello",
  run: async (payload: { note?: string }) => {
    const sb = createClient(process.env.SUPABASE_URL!, process.env.SUPABASE_SERVICE_ROLE_KEY!);
    const { data: eventId, error } = await sb.schema("system").rpc("emit_event", { p_org: null, p_type: "worker.hello", p_table: null, p_id: null, p_payload: { note: payload.note ?? "" }, p_actor: "trigger" });
    if (error) throw error;
    await wait.for({ seconds: 6 });
    const key = `proof/hello-${eventId}.txt`;
    await putObject(key, `event ${eventId} at ${new Date().toISOString()}`, "text/plain");
    logger.info("round trip complete", { eventId, key });
    return { eventId, key };
  },
});
