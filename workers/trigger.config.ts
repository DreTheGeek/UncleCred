import { defineConfig } from "@trigger.dev/sdk/v3";

export default defineConfig({
  project: process.env.TRIGGER_PROJECT_ID ?? "proj_replace_me",
  dirs: ["./src/tasks"],
  maxDuration: 3600,
  retries: { enabledInDev: false, default: { maxAttempts: 3, factor: 2, minTimeoutInMs: 2000, maxTimeoutInMs: 60000 } },
});
