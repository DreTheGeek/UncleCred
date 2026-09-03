#!/usr/bin/env node
// Train UNCLECRED_V1 on fal from a folder of real photos, then lock the LoRA into canon.
// Usage: FAL_KEY=... SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... node scripts/train-lora.mjs ./refs/uncle_cred
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";
import { createClient } from "@supabase/supabase-js";
import { fal } from "@fal-ai/client";
import JSZip from "jszip";

const dir = process.argv[2];
const character = process.argv[3] ?? "uncle_cred";
const trigger = process.argv[4] ?? "UNCLECRED_V1";
if (!dir) throw new Error("folder required");
fal.config({ credentials: process.env.FAL_KEY });

const files = readdirSync(dir).filter((f) => /\.(jpe?g|png|webp)$/i.test(f));
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

const sb = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);
const { error } = await sb.schema("studio").from("visual_characters")
  .update({ metadata: { lora: { id: `${trigger}`, url: loraUrl, trainer: "fal-ai/flux-lora-fast-training", steps: 1000, images: files.length, trained_at: new Date().toISOString(), locked: true } } })
  .eq("character_code", character);
if (error) throw error;
await sb.schema("system").rpc("emit_event", { p_org: "00000000-0000-0000-0000-000000000001", p_type: "canon.lora.trained", p_table: "studio.visual_characters", p_id: null, p_payload: { character, trigger, images: files.length }, p_actor: "script" });
console.log("locked into canon");
