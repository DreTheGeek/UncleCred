#!/usr/bin/env node
// Identity sweep: generate one canonical prompt across N seeds and lay the results out for a
// verdict. This is the measurement that every claim about a LoRA has to survive.
//
// Usage: node --env-file=.env.local scripts/identity-sweep.mjs [character] [count] [outDir]
//
// Why it exists: on 2026-09-03 three separate claims that identity was "solved" were made and
// all three were wrong, because they rested on looking at a handful of renders rather than
// measuring a rate. A properly trained character LoRA is documented at 85 to 92 percent view
// consistency. The only honest way to know where a LoRA sits is to hold the prompt still, vary
// only the seed, and count.
//
// The verdict is never this script's to make. It prints an index and a scoring template; a
// human who knows the face fills it in. Later the identity QA gate takes that job, and this
// harness is what calibrates its threshold.

import { createClient } from "@supabase/supabase-js";
import { mkdirSync, writeFileSync } from "node:fs";
import { GenerationRouter, buildCharacterPrompt } from "../packages/generation-router/index.ts";

const character = process.argv[2] ?? "uncle_cred";
const count = Number(process.argv[3] ?? 8);
const outDir = process.argv[4] ?? `refs/${character}/sweeps/${new Date().toISOString().slice(0, 10)}`;
const ORG = "00000000-0000-0000-0000-000000000001";

for (const k of ["SUPABASE_URL", "SUPABASE_SERVICE_ROLE_KEY", "FAL_KEY"]) {
  if (!process.env[k]) throw new Error(`${k} missing`);
}

const sb = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
});
const router = new GenerationRouter(sb, { falKey: process.env.FAL_KEY });

const { data: row, error } = await sb
  .schema("studio")
  .from("visual_characters")
  .select(
    "character_code, name, description, wardrobe, physical_traits, generation_notes, prohibited_changes, metadata",
  )
  .eq("character_code", character)
  .single();
if (error) throw error;

// The canonical scene. Held identical across every seed so the seed is the only variable.
const scene = {
  shot: "chest up portrait",
  location: "in a warm wood home office, soft desk lamp key light",
  action: "calm direct expression, eyes to camera",
};
const built = buildCharacterPrompt(row, scene);
if (!built.loraUrl) throw new Error(`${character} has no LoRA in canon`);

console.log(`character : ${row.name} (${character})`);
console.log(`lora      : ${built.triggerWord}`);
console.log(`seeds     : ${count}`);
console.log(`out       : ${outDir}\n`);

mkdirSync(outDir, { recursive: true });

// Fixed seed list so two sweeps of the same LoRA are comparable, and so a sweep of a NEW LoRA
// is comparable to the old one. Changing these makes the numbers meaningless.
const SEEDS = [20260903, 909090, 70707, 128512, 101, 2024, 33333, 4815162, 555001, 8811, 31415, 271828];
const seeds = SEEDS.slice(0, count);

const results = [];
let spend = 0;
for (const seed of seeds) {
  try {
    const r = await router.generate(
      {
        capability: "image",
        prompt: built.prompt,
        negativePrompt: built.negativePrompt,
        loras: [{ path: built.loraUrl, scale: 1 }],
        imageSize: "portrait_4_3",
        numImages: 1,
        steps: 28,
        seed,
      },
      {
        organizationId: ORG,
        purpose: `identity.sweep.${built.triggerWord}`,
        characterCode: character,
        traceId: `sweep-${built.triggerWord}`,
      },
      { modelId: "fal-ai/flux-general" },
    );
    const url = r.assets[0].url;
    const file = `${outDir}/seed_${seed}.png`;
    const buf = Buffer.from(await (await fetch(url)).arrayBuffer());
    writeFileSync(file, buf);
    results.push({ seed, file, url });
    spend += r.costUsd;
    console.log(`  seed ${String(seed).padEnd(9)} ok   ${file}`);
  } catch (e) {
    console.log(`  seed ${String(seed).padEnd(9)} FAILED  ${String(e.message).slice(0, 100)}`);
    results.push({ seed, file: null, error: String(e.message).slice(0, 200) });
  }
}

// A scoring sheet, not a verdict. Whoever knows the face marks each seed.
const sheet = {
  character,
  lora: built.triggerWord,
  lora_url: built.loraUrl,
  prompt: built.prompt,
  negative_prompt: built.negativePrompt,
  scene,
  generated_at: new Date().toISOString(),
  spend_usd: Number(spend.toFixed(4)),
  instructions:
    "Set verdict to 'yes' or 'no' for each seed: is this the person? Then hit_rate is yes over total. " +
    "A properly trained character LoRA sits at 85 to 92 percent. Below that, the LoRA is the problem, not the prompt.",
  seeds: results.map((r) => ({ seed: r.seed, file: r.file, verdict: null, note: null })),
};
writeFileSync(`${outDir}/scoresheet.json`, JSON.stringify(sheet, null, 2), "utf8");

console.log(`\n${results.filter((r) => r.file).length} of ${seeds.length} generated, $${spend.toFixed(4)}`);
console.log(`scoresheet: ${outDir}/scoresheet.json`);
