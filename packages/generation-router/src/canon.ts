// Build a character prompt FROM canon. Never by hand.
//
// This exists because of a real failure on 2026-09-03. Uncle Cred renders kept coming back
// wearing glasses. The LoRA was fine; the prompt was wrong. Prompts were being hand written
// from the identity board in DECISIONS.md, which describes identity v1.0, a synthetic 45 to 52
// year old in gold frames and a cream quarter zip polo. Identity v2.0 superseded all of that
// when Uncle Cred became LaSean himself, and the character row already said so:
//
//   physical_traits.eyewear   "never. He does not wear glasses."
//   metadata.negative_prompt  "glasses, eyeglasses, spectacles, eyewear, sunglasses,
//                              polo shirt, collar, cardigan, hat, cap, beard drift, older man"
//
// Both the glasses and the polo were already banned in canon. A document said one thing, the
// database said another, and a person hand carrying values between them picked the wrong one.
// So no caller writes a character prompt again: it is assembled from the row, and the row's
// negative_prompt is always applied.

import { z } from "zod";

export const CharacterRow = z.object({
  character_code: z.string(),
  name: z.string(),
  description: z.string().nullable().default(null),
  wardrobe: z.record(z.string(), z.unknown()).default({}),
  physical_traits: z.record(z.string(), z.unknown()).default({}),
  generation_notes: z.string().nullable().default(null),
  prohibited_changes: z.array(z.string()).default([]),
  metadata: z.record(z.string(), z.unknown()).default({}),
});
export type CharacterRow = z.infer<typeof CharacterRow>;

export type CharacterPrompt = {
  prompt: string;
  negativePrompt: string;
  triggerWord: string | null;
  loraUrl: string | null;
  /** Traits actually used, so a bad render can be traced to the row that produced it. */
  usedTraits: Record<string, string>;
};

const str = (v: unknown): string | null =>
  typeof v === "string" && v.trim() ? v.trim() : null;

/**
 * Traits that describe the person. Ordered so identity-critical features land early in the
 * prompt, where the model weights them most.
 */
const TRAIT_ORDER = [
  "skin",
  "hair",
  "hairline",
  "beard",
  "build",
  "height",
  "vibe",
] as const;

/**
 * Keys that are notes to humans, not prompt material. Feeding these to an image model produces
 * literal renders of the instruction, which is its own class of bug.
 */
const NOT_PROMPTABLE = new Set([
  "note",
  "source",
  "palette",
  "alt_looks",
  "look_locked_by",
  "current_look_locked",
  "face_master_001",
  "reference_video",
  "age_range",
  "eyewear",
  "default_shirt",
]);

export function buildCharacterPrompt(
  raw: unknown,
  scene: { action?: string; location?: string; shot?: string; wardrobeKey?: string } = {},
): CharacterPrompt {
  const c = CharacterRow.parse(raw);
  const pt = c.physical_traits as Record<string, unknown>;
  const used: Record<string, string> = {};

  const age = typeof pt.age === "number" ? `${pt.age} years old` : null;
  if (age) used.age = String(pt.age);

  const traits: string[] = [];
  for (const key of TRAIT_ORDER) {
    const v = str(pt[key]);
    if (v && !NOT_PROMPTABLE.has(key)) {
      traits.push(`${key}: ${v}`);
      used[key] = v;
    }
  }

  // Wardrobe is an asset, not an adjective. Resolve the named item rather than describing it.
  const wardrobe = c.wardrobe as { items?: Record<string, string>; default?: string };
  const wardrobeKey = scene.wardrobeKey ?? wardrobe.default ?? null;
  const wardrobeItem = wardrobeKey ? str(wardrobe.items?.[wardrobeKey]) : null;
  if (wardrobeItem) used.wardrobe = `${wardrobeKey}: ${wardrobeItem}`;

  // Accessories that are part of the person, not the outfit.
  const accessories = ["chain", "watch", "earrings"]
    .map((k) => (str(pt[k]) ? `${str(pt[k])}` : null))
    .filter((x): x is string => Boolean(x));
  if (accessories.length) used.accessories = accessories.join("; ");

  const lora = c.metadata.lora as { id?: string; url?: string } | undefined;

  const parts = [
    lora?.id ?? null,
    "photorealistic",
    scene.shot ?? "portrait",
    "of a Black man",
    age,
    traits.join(", ") || null,
    wardrobeItem ? `wearing ${wardrobeItem}` : null,
    accessories.length ? accessories.join(", ") : null,
    scene.location ?? null,
    scene.action ?? null,
    "real human skin with visible texture and pores, natural facial asymmetry",
    "85mm lens, shallow depth of field, no retouching, no plastic skin, no CGI look, no text, no watermark",
  ].filter((p): p is string => Boolean(p));

  // The row's own negative prompt is not optional. It is where the character's hard "never"
  // rules live, and it is the thing that was being skipped.
  const canonNegative = str(c.metadata.negative_prompt) ?? "";
  const eyewear = str(pt.eyewear);
  const eyewearNegative =
    eyewear && /never|no\b|does not/i.test(eyewear)
      ? "glasses, eyeglasses, spectacles, eyewear, sunglasses"
      : "";

  const negativePrompt = [canonNegative, eyewearNegative]
    .filter(Boolean)
    .join(", ")
    .split(",")
    .map((s) => s.trim())
    .filter((s, i, a) => s && a.indexOf(s) === i)
    .join(", ");

  return {
    prompt: parts.join(", "),
    negativePrompt,
    triggerWord: lora?.id ?? null,
    loraUrl: lora?.url ?? null,
    usedTraits: used,
  };
}
