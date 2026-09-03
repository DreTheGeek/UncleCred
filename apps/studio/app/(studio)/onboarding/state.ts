import { z } from "zod";

// Kept out of actions.ts on purpose: a "use server" module may only export async functions,
// so the schema and its type live here and both the server actions and the client import it.

export const OnboardingState = z.object({
  step: z.number().int().min(1).max(9).default(1),
  completed: z.boolean().default(false),
  productName: z.string().default(""),
  castConfirmed: z.array(z.string()).default([]),
  platforms: z
    .object({
      tiktok: z.boolean().default(true),
      reels: z.boolean().default(true),
      shorts: z.boolean().default(true),
      facebook: z.boolean().default(true),
      linkedin: z.boolean().default(true),
    })
    .default({ tiktok: true, reels: true, shorts: true, facebook: true, linkedin: true }),
  cadencePerDay: z.number().int().min(1).max(3).default(1),
  rulesAcknowledged: z.boolean().default(false),
  storyApproved: z.boolean().default(false),
  completedAt: z.string().nullable().default(null),
});
export type OnboardingState = z.infer<typeof OnboardingState>;
