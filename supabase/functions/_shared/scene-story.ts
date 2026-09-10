import { z } from "npm:zod@3.25.76";
import { admin, type Principal } from "./api.ts";
import { sceneOpenRouterCompletion } from "./scene-provider.ts";

const keySchema = z.string().trim().min(1).max(80).regex(/^[a-z0-9][a-z0-9_-]*$/);
const jsonRecord = z.record(z.unknown());
const guidanceModeSchema = z.enum(["follow_closely", "build_with_me", "take_the_wheel"]);
const castArchitectureSchema = z.enum(["central_protagonist", "dual_lead", "ensemble", "rotating_focus", "anthology", "shared_universe"]);
const schedulingModeSchema = z.enum(["exact", "windowed", "ordered", "optional", "emergent"]);
const dependencyTypeSchema = z.enum(["requires", "after", "before", "excludes", "enables"]);

const runtimeRangeSchema = z.object({
  min: z.number().int().positive(),
  preferred: z.number().int().positive(),
  max: z.number().int().positive(),
}).refine((v) => v.min <= v.preferred && v.preferred <= v.max, "runtime range must satisfy min <= preferred <= max");

const finalStateSchema = z.object({
  plot: jsonRecord.default({}),
  characters: jsonRecord.default({}),
  relationships: jsonRecord.default({}),
  information: jsonRecord.default({}),
  emotional: jsonRecord.default({}),
  physical: jsonRecord.default({}),
  world: jsonRecord.default({}),
  futureHooks: z.array(z.unknown()).default([]),
});

const futureNodeSchema = z.object({
  key: keySchema,
  nodeType: z.string().trim().min(1).max(120),
  title: z.string().trim().min(1).max(240),
  description: z.string().max(4000).default(""),
  schedulingMode: schedulingModeSchema,
  earliestEpisode: z.number().int().positive().nullable().default(null),
  latestEpisode: z.number().int().positive().nullable().default(null),
  exactEpisode: z.number().int().positive().nullable().default(null),
  priority: z.number().int().min(-100).max(100).default(0),
  locked: z.boolean().default(false),
  payload: jsonRecord.default({}),
}).superRefine((v, ctx) => {
  if (v.earliestEpisode && v.latestEpisode && v.latestEpisode < v.earliestEpisode) {
    ctx.addIssue({ code: z.ZodIssueCode.custom, message: "latestEpisode cannot precede earliestEpisode" });
  }
  if (v.schedulingMode === "exact" && v.exactEpisode == null) {
    ctx.addIssue({ code: z.ZodIssueCode.custom, message: "exact scheduling requires exactEpisode" });
  }
});

const showrunnerPackageSchema = z.object({
  blueprint: z.object({
    version: z.number().int().positive().default(1),
    series: z.object({
      premise: z.string().trim().min(1),
      format: z.string().trim().min(1),
      tone: z.array(z.string()).default([]),
      genre: z.array(z.string()).default([]),
      castArchitecture: castArchitectureSchema,
      episodeRuntimeTargetSeconds: runtimeRangeSchema,
      sceneRuntimeTargetSeconds: runtimeRangeSchema,
      worldRules: z.array(z.string()).default([]),
      storyPromises: z.array(z.string()).default([]),
      contentBoundaries: jsonRecord.default({}),
      visualLanguage: jsonRecord.default({}),
      guidanceMode: guidanceModeSchema,
    }),
    finalState: finalStateSchema,
    characterDestinations: z.array(z.object({
      characterKey: keySchema,
      startState: jsonRecord.default({}),
      finalState: jsonRecord.default({}),
      transformation: z.string().default(""),
      nonNegotiables: z.array(z.string()).default([]),
    })).default([]),
    relationshipDestinations: z.array(z.object({
      characterAKey: keySchema,
      characterBKey: keySchema,
      startState: jsonRecord.default({}),
      finalState: jsonRecord.default({}),
      requiredTurns: z.array(z.string()).default([]),
    })).default([]),
    futureNodes: z.array(futureNodeSchema).default([]),
    dependencies: z.array(z.object({
      predecessorKey: keySchema,
      successorKey: keySchema,
      type: dependencyTypeSchema,
    })).default([]),
    unresolvedQuestions: z.array(z.string()).default([]),
  }),
  characters: z.array(z.object({
    key: keySchema,
    name: z.string().trim().min(1).max(120),
    narrativeRole: z.string().trim().min(1).max(120),
    description: z.string().trim().min(1).max(2000),
    baseTraits: jsonRecord.default({}),
    startState: jsonRecord.default({}),
  })).min(1).max(30),
  relationships: z.array(z.object({
    characterAKey: keySchema,
    characterBKey: keySchema,
    relationshipType: z.string().trim().min(1).max(120),
    dimensions: jsonRecord.default({}),
    startState: jsonRecord.default({}),
  })).max(100).default([]),
  initialArc: z.object({
    key: keySchema,
    title: z.string().trim().min(1).max(200),
    summary: z.string().trim().min(1).max(4000),
    startEpisodeHint: z.number().int().positive().nullable().default(null),
    endEpisodeHint: z.number().int().positive().nullable().default(null),
    priority: z.number().int().min(-100).max(100).default(0),
  }),
  initialBlock: z.object({
    position: z.number().int().positive(),
    objective: z.string().trim().min(1),
    episodeWindow: z.object({ start: z.number().int().positive(), end: z.number().int().positive() }),
    activeArcKeys: z.array(keySchema).default([]),
    requiredNodeKeys: z.array(keySchema).default([]),
    optionalNodeKeys: z.array(keySchema).default([]),
    exitConditions: z.array(z.string()).default([]),
  }),
  initialEpisode: z.object({
    episodeNumber: z.number().int().positive(),
    objective: z.string().trim().min(1),
    focalCharacterKeys: z.array(keySchema).default([]),
    activeArcKeys: z.array(keySchema).default([]),
    requiredNodeKeys: z.array(keySchema).default([]),
    informationChange: z.array(z.string()).default([]),
    relationshipChange: z.array(z.string()).default([]),
    setupKeys: z.array(z.string()).default([]),
    payoffKeys: z.array(z.string()).default([]),
    endingPressureType: z.string().nullable().default(null),
    productionDifficulty: z.number().min(0).max(1).default(0.5),
  }),
  initialScene: z.object({
    purpose: z.string().trim().min(1),
    focalCharacterKeys: z.array(keySchema).default([]),
    requiredCharacterKeys: z.array(keySchema).default([]),
    requiredLocationKeys: z.array(keySchema).default([]),
    requiredPropKeys: z.array(keySchema).default([]),
    requiredNodeKeys: z.array(keySchema).default([]),
    informationChange: z.array(z.string()).default([]),
    relationshipChange: z.array(z.string()).default([]),
    setupKeys: z.array(z.string()).default([]),
    payoffKeys: z.array(z.string()).default([]),
    endingPressureType: z.string().nullable().default(null),
    runtimeTargetSeconds: z.number().int().positive(),
    productionDifficulty: z.number().min(0).max(1).default(0.5),
  }),
}).superRefine((value, ctx) => {
  const characters = new Set(value.characters.map((c) => c.key));
  const nodes = new Set(value.blueprint.futureNodes.map((n) => n.key));
  if (characters.size !== value.characters.length) ctx.addIssue({ code: z.ZodIssueCode.custom, message: "character keys must be unique" });
  if (nodes.size !== value.blueprint.futureNodes.length) ctx.addIssue({ code: z.ZodIssueCode.custom, message: "future node keys must be unique" });

  const characterRefs = [
    ...value.blueprint.characterDestinations.map((x) => x.characterKey),
    ...value.blueprint.relationshipDestinations.flatMap((x) => [x.characterAKey, x.characterBKey]),
    ...value.relationships.flatMap((x) => [x.characterAKey, x.characterBKey]),
    ...value.initialEpisode.focalCharacterKeys,
    ...value.initialScene.focalCharacterKeys,
    ...value.initialScene.requiredCharacterKeys,
  ];
  for (const key of characterRefs) if (!characters.has(key)) ctx.addIssue({ code: z.ZodIssueCode.custom, message: `unknown character key: ${key}` });

  const nodeRefs = [
    ...value.blueprint.dependencies.flatMap((x) => [x.predecessorKey, x.successorKey]),
    ...value.initialBlock.requiredNodeKeys,
    ...value.initialBlock.optionalNodeKeys,
    ...value.initialEpisode.requiredNodeKeys,
    ...value.initialScene.requiredNodeKeys,
  ];
  for (const key of nodeRefs) if (!nodes.has(key)) ctx.addIssue({ code: z.ZodIssueCode.custom, message: `unknown future node key: ${key}` });

  if (value.initialBlock.episodeWindow.end < value.initialBlock.episodeWindow.start) {
    ctx.addIssue({ code: z.ZodIssueCode.custom, message: "story block episode window is reversed" });
  }
  if (value.initialArc.startEpisodeHint && value.initialArc.endEpisodeHint && value.initialArc.endEpisodeHint < value.initialArc.startEpisodeHint) {
    ctx.addIssue({ code: z.ZodIssueCode.custom, message: "arc episode window is reversed" });
  }
});

export type ShowrunnerPackage = z.infer<typeof showrunnerPackageSchema>;

export async function principalCanUseOrganization(principal: Principal, organizationId: string): Promise<boolean> {
  if (!organizationId) return false;
  if (principal.kind === "api_key") return principal.organizationId === organizationId;
  const { data, error } = await admin().schema("platform").from("organization_members")
    .select("organization_id").eq("organization_id", organizationId).eq("user_id", principal.id).eq("status", "active").maybeSingle();
  return !error && Boolean(data);
}

export async function listSceneShows(principal: Principal, organizationId: string) {
  if (!(await principalCanUseOrganization(principal, organizationId))) throw new Error("forbidden");
  const { data, error } = await admin().schema("story").from("shows")
    .select("id,organization_id,universe_id,created_by,title,initial_request,format,production_mode,guidance_mode,status,created_at,updated_at")
    .eq("organization_id", organizationId).order("updated_at", { ascending: false });
  if (error) throw new Error(`show_list_failed:${error.message}`);
  return data ?? [];
}

export async function getSceneShow(principal: Principal, organizationId: string, showId: string) {
  if (!(await principalCanUseOrganization(principal, organizationId))) throw new Error("forbidden");
  const { data, error } = await admin().schema("story").from("shows")
    .select("id,organization_id,universe_id,created_by,title,initial_request,format,production_mode,guidance_mode,creator_input_state,status,created_at,updated_at")
    .eq("organization_id", organizationId).eq("id", showId).maybeSingle();
  if (error) throw new Error(`show_read_failed:${error.message}`);
  return data ?? null;
}

export async function createSceneShow(principal: Principal, organizationId: string, input: {
  title: string;
  initialRequest: string;
  format?: string | null;
  productionMode?: "cinematic" | "anime" | "stylized_3d" | "cartoon" | "comic" | "stick_figure";
  guidanceMode?: "follow_closely" | "build_with_me" | "take_the_wheel";
  universeId?: string | null;
  creatorInputState?: Record<string, unknown>;
}) {
  if (!(await principalCanUseOrganization(principal, organizationId))) throw new Error("forbidden");
  const actor = principal.kind === "user" ? principal.id : null;
  const { data, error } = await admin().schema("story").from("shows").insert({
    organization_id: organizationId,
    universe_id: input.universeId ?? null,
    created_by: actor,
    title: input.title.trim(),
    initial_request: input.initialRequest.trim(),
    format: input.format?.trim() || null,
    production_mode: input.productionMode ?? "cinematic",
    guidance_mode: input.guidanceMode ?? "take_the_wheel",
    creator_input_state: input.creatorInputState ?? {},
    status: "active",
  }).select("*").single();
  if (error) throw new Error(`show_create_failed:${error.message}`);
  return data;
}

function systemPrompt() {
  return [
    "You are Scene's Showrunner Engine.",
    "Return exactly one JSON object. No markdown.",
    "Plan backward from a clear intended final state while keeping future story adaptable.",
    "Use progressive planning: destination, first arc, first Story Block, first episode opportunity, first scene objective.",
    "Do not force a main character. Choose the cast architecture that fits the premise.",
    "Keep world truth, character perspective, audience knowledge, and planned truth separate.",
    "The opening scene must materially advance the story and establish useful state for continuation.",
    "Use stable lowercase slug keys made from letters, numbers, underscores, or hyphens.",
    "Do not use copyrighted existing characters or franchises unless the creator explicitly supplied rights-cleared material.",
  ].join("\n");
}

function userPrompt(show: Record<string, unknown>) {
  return JSON.stringify({
    task: "Create the initial persistent story blueprint and executable opening plan.",
    show: {
      title: show.title,
      initialRequest: show.initial_request,
      format: show.format,
      productionMode: show.production_mode,
      creatorInputState: show.creator_input_state,
      guidanceMode: show.guidance_mode,
    },
    requiredOutput: {
      blueprint: {
        version: 1,
        series: {
          premise: "string", format: "string", tone: ["string"], genre: ["string"],
          castArchitecture: "central_protagonist | dual_lead | ensemble | rotating_focus | anthology | shared_universe",
          episodeRuntimeTargetSeconds: { min: 60, preferred: 180, max: 3600 },
          sceneRuntimeTargetSeconds: { min: 20, preferred: 90, max: 300 },
          worldRules: ["string"], storyPromises: ["string"], contentBoundaries: {}, visualLanguage: {},
          guidanceMode: show.guidance_mode,
        },
        finalState: { plot: {}, characters: {}, relationships: {}, information: {}, emotional: {}, physical: {}, world: {}, futureHooks: [] },
        characterDestinations: [{ characterKey: "slug", startState: {}, finalState: {}, transformation: "string", nonNegotiables: ["string"] }],
        relationshipDestinations: [{ characterAKey: "slug", characterBKey: "slug", startState: {}, finalState: {}, requiredTurns: ["string"] }],
        futureNodes: [{ key: "slug", nodeType: "string", title: "string", description: "string", schedulingMode: "exact | windowed | ordered | optional | emergent", earliestEpisode: null, latestEpisode: null, exactEpisode: null, priority: 0, locked: false, payload: {} }],
        dependencies: [{ predecessorKey: "slug", successorKey: "slug", type: "requires | after | before | excludes | enables" }],
        unresolvedQuestions: ["string"],
      },
      characters: [{ key: "slug", name: "string", narrativeRole: "string", description: "string", baseTraits: {}, startState: {} }],
      relationships: [{ characterAKey: "slug", characterBKey: "slug", relationshipType: "string", dimensions: {}, startState: {} }],
      initialArc: { key: "slug", title: "string", summary: "string", startEpisodeHint: 1, endEpisodeHint: null, priority: 1 },
      initialBlock: { position: 1, objective: "string", episodeWindow: { start: 1, end: 10 }, activeArcKeys: ["slug"], requiredNodeKeys: ["slug"], optionalNodeKeys: ["slug"], exitConditions: ["string"] },
      initialEpisode: { episodeNumber: 1, objective: "string", focalCharacterKeys: ["slug"], activeArcKeys: ["slug"], requiredNodeKeys: ["slug"], informationChange: ["string"], relationshipChange: ["string"], setupKeys: ["string"], payoffKeys: ["string"], endingPressureType: null, productionDifficulty: 0.5 },
      initialScene: { purpose: "string", focalCharacterKeys: ["slug"], requiredCharacterKeys: ["slug"], requiredLocationKeys: [], requiredPropKeys: [], requiredNodeKeys: ["slug"], informationChange: ["string"], relationshipChange: ["string"], setupKeys: ["string"], payoffKeys: ["string"], endingPressureType: null, runtimeTargetSeconds: 90, productionDifficulty: 0.5 },
    },
  });
}

function parseJsonObject(content: string): unknown {
  const value = content.trim();
  if (!value.startsWith("```")) return JSON.parse(value);
  const first = value.indexOf("\n");
  const last = value.lastIndexOf("```");
  if (first < 0 || last <= first) throw new Error("showrunner_invalid_json");
  return JSON.parse(value.slice(first + 1, last).trim());
}

function validateGraph(pkg: ShowrunnerPackage) {
  const keys = new Set(pkg.blueprint.futureNodes.map((n) => n.key));
  const adjacency = new Map<string, string[]>();
  for (const dep of pkg.blueprint.dependencies) {
    if (!keys.has(dep.predecessorKey) || !keys.has(dep.successorKey)) throw new Error("showrunner_graph_missing_node");
    if (dep.predecessorKey === dep.successorKey) throw new Error("showrunner_graph_self_dependency");
    if (dep.type === "excludes") continue;
    adjacency.set(dep.predecessorKey, [...(adjacency.get(dep.predecessorKey) ?? []), dep.successorKey]);
  }
  const visiting = new Set<string>();
  const visited = new Set<string>();
  const visit = (key: string): boolean => {
    if (visiting.has(key)) return true;
    if (visited.has(key)) return false;
    visiting.add(key);
    for (const next of adjacency.get(key) ?? []) if (visit(next)) return true;
    visiting.delete(key);
    visited.add(key);
    return false;
  };
  for (const key of keys) if (visit(key)) throw new Error("showrunner_graph_cycle");
}

async function sha256(text: string) {
  const bytes = new TextEncoder().encode(text);
  const hash = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(hash)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

export async function getActiveSceneBlueprint(principal: Principal, organizationId: string, showId: string) {
  if (!(await principalCanUseOrganization(principal, organizationId))) throw new Error("forbidden");
  const { data, error } = await admin().schema("story").from("show_blueprints")
    .select("id,organization_id,show_id,version,status,blueprint,model_provider,model_name,provider_request_id,input_hash,created_by,created_at")
    .eq("organization_id", organizationId).eq("show_id", showId).eq("status", "active")
    .order("version", { ascending: false }).limit(1).maybeSingle();
  if (error) throw new Error(`show_blueprint_read_failed:${error.message}`);
  return data ?? null;
}

export async function buildInitialSceneBlueprint(principal: Principal, organizationId: string, showId: string) {
  const show = await getSceneShow(principal, organizationId, showId);
  if (!show) throw new Error("show_not_found");

  const prompt = userPrompt(show as Record<string, unknown>);
  const inputHash = await sha256(prompt);
  const startedAt = Date.now();
  const actorUserId = principal.kind === "user" ? principal.id : null;

  const { data: aiRun, error: aiRunError } = await admin().schema("system").from("ai_runs").insert({
    organization_id: organizationId,
    run_type: "scene.showrunner.initial_blueprint",
    provider: "openrouter",
    model: Deno.env.get("SCENE_STORY_MODEL")?.trim() || "openrouter/auto",
    prompt_version: "scene-showrunner-v1",
    actor_type: principal.kind,
    actor_id: principal.id,
    input_summary: `Initial blueprint for show ${showId}`,
    input_payload: { show_id: showId, input_hash: inputHash },
    status: "started",
  }).select("id").single();
  if (aiRunError) throw new Error(`ai_run_create_failed:${aiRunError.message}`);

  try {
    const completion = await sceneOpenRouterCompletion({
      messages: [{ role: "system", content: systemPrompt() }, { role: "user", content: prompt }],
      temperature: 0.55,
      maxTokens: 12000,
      responseFormat: { type: "json_object" },
    });

    let raw: unknown;
    try { raw = parseJsonObject(completion.content); } catch { throw new Error("showrunner_invalid_json"); }
    const parsed = showrunnerPackageSchema.safeParse(raw);
    if (!parsed.success) throw new Error(`showrunner_contract_failed:${parsed.error.issues.map((x) => x.message).join("|")}`);
    validateGraph(parsed.data);

    const { data: persistence, error: persistError } = await admin().schema("story").rpc("persist_showrunner_package", {
      p_organization_id: organizationId,
      p_show_id: showId,
      p_actor_user_id: actorUserId,
      p_package: parsed.data,
      p_model_provider: completion.provider,
      p_model_name: completion.model,
      p_provider_request_id: completion.providerRequestId,
      p_input_hash: inputHash,
    });
    if (persistError) throw new Error(`showrunner_persist_failed:${persistError.message}`);

    const usage = completion.usage as Record<string, unknown> | null;
    await admin().schema("system").from("ai_runs").update({
      provider: completion.provider,
      model: completion.model,
      request_id: completion.providerRequestId,
      output_payload: { persistence },
      status: "completed",
      input_tokens: typeof usage?.prompt_tokens === "number" ? usage.prompt_tokens : null,
      output_tokens: typeof usage?.completion_tokens === "number" ? usage.completion_tokens : null,
      latency_ms: Date.now() - startedAt,
      completed_at: new Date().toISOString(),
    }).eq("id", aiRun.id);

    return { package: parsed.data, persistence, provider: completion.provider, model: completion.model, providerRequestId: completion.providerRequestId, usage: completion.usage };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    await admin().schema("system").from("ai_runs").update({
      status: "failed",
      error: message.slice(0, 4000),
      latency_ms: Date.now() - startedAt,
      completed_at: new Date().toISOString(),
    }).eq("id", aiRun.id);
    throw error;
  }
}
