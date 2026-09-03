#!/usr/bin/env node
// Train UNCLECRED_V1 on fal from a folder of real photos, then lock the LoRA into canon.
// Usage: node --env-file=.env.local scripts/train-lora.mjs ./refs/uncle_cred/final uncle_cred UNCLECRED_V1
// TODO: metadata merge here is a read-modify-write, two round trips, last writer wins. Safe for a
// one-shot manual run, not for concurrent writers. When the LoRA write moves into the pipeline
// worker, collapse it to a single statement inside the stage: metadata = metadata || $1::jsonb.
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { createClient } from "@supabase/supabase-js";
import { fal } from "@fal-ai/client";
import JSZip from "jszip";

const [dir, character = "uncle_cred", trigger = "UNCLECRED_V1"] = process.argv.slice(2);
if (!dir) throw new Error("folder required");
for (const k of ["FAL_KEY", "SUPABASE_URL", "SUPABASE_SERVICE_ROLE_KEY"]) if (!process.env[k]) throw new Error(`${k} missing`);
fal.config({ credentials: process.env.FAL_KEY });
const ORG = "00000000-0000-0000-0000-000000000001";

// Prove the canon row exists BEFORE spending fal credits.
const sb = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });
const { data: row, error: readErr } = await sb.schema("studio").from("visual_characters").select("id, metadata").eq("character_code", character).single();
if (readErr || !row) throw new Error(`canon row for ${character} not found: ${readErr?.message ?? "no row"}`);

const files = readdirSync(dir).filter((f) => /\.(jpe?g|png|webp)$/i.test(f)).sort();
if (files.length < 15) console.warn(`only ${files.length} images; 15 to 30 clean frames recommended`);
const zip = new JSZip();
for (const f of files) zip.file(f, readFileSync(join(dir, f)));
const blob = new Blob([await zip.generateAsync({ type: "uint8array" })], { type: "application/zip" });
const zipUrl = await fal.storage.upload(blob);
console.log("uploaded", files.length, "images");

const result = await fal.subscribe("fal-ai/flux-lora-fast-training", {
  input: { images_data_url: zipUrl, trigger_word: trigger, steps: 1000, create_masks: true, is_style: false },
  logs: true,
  onQueueUpdate: (u) => u.status === "IN_PROGRESS" && u.logs?.forEach((l) => console.log(l.message)),
});
const loraUrl = result.data?.diffusers_lora_file?.url;
if (!loraUrl) throw new Error("no lora url in result");
console.log("lora", loraUrl);

// Merge, never overwrite: read-modify-write on the jsonb so voice, consent, identity_version survive.
const lora = { id: trigger, url: loraUrl, trainer: "fal-ai/flux-lora-fast-training", steps: 1000, images: files.length, trained_at: new Date().toISOString(), locked: true };

// Retraining must never silently drop the LoRA it replaces. A v3 that turns out worse than v1
// should be a rollback, not another training run, and that is only possible if the old artifact
// is still addressable. The outgoing lora is appended to lora_history, never overwritten.
const prior = row.metadata?.lora ?? null;
const priorHistory = Array.isArray(row.metadata?.lora_history) ? row.metadata.lora_history : [];
const lora_history = prior && prior.url !== loraUrl
  ? [...priorHistory, { ...prior, superseded_at: lora.trained_at, superseded_by: trigger }]
  : priorHistory;

const merged = { ...(row.metadata ?? {}), lora, lora_history };
const { data: updated, error: updErr } = await sb.schema("studio").from("visual_characters").update({ metadata: merged }).eq("id", row.id).select("id, character_code, metadata->lora");
if (updErr) throw updErr;
if (!updated || updated.length !== 1) throw new Error(`expected 1 row updated, got ${updated?.length ?? 0}`);

const { data: eventId, error: evErr } = await sb.schema("system").rpc("emit_event", { p_org: ORG, p_type: "canon.lora.trained", p_table: "studio.visual_characters", p_id: row.id, p_payload: { character, trigger, images: files.length, url: loraUrl }, p_actor: "script" });
if (evErr) throw evErr;
console.log("locked into canon", { row: row.id, event: eventId });
