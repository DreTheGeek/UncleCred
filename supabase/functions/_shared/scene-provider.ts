import "jsr:@supabase/functions-js/edge-runtime.d.ts";

export type SceneProviderMessage = {
  role: "system" | "user" | "assistant";
  content: string;
};

export type SceneCompletionInput = {
  messages: SceneProviderMessage[];
  model?: string;
  temperature?: number;
  maxTokens?: number;
  responseFormat?: Record<string, unknown>;
};

export type SceneCompletionResult = {
  provider: "openrouter";
  model: string;
  providerRequestId: string | null;
  content: string;
  usage: unknown;
};

function boundedNumber(value: unknown, fallback: number, min: number, max: number): number {
  const n = Number(value);
  return Number.isFinite(n) ? Math.max(min, Math.min(max, n)) : fallback;
}

export function sceneStoryModel(): string {
  return Deno.env.get("SCENE_STORY_MODEL")?.trim() || "openrouter/auto";
}

export async function sceneOpenRouterCompletion(input: SceneCompletionInput): Promise<SceneCompletionResult> {
  const apiKey = Deno.env.get("OPENROUTER_API_KEY")?.trim();
  if (!apiKey) throw new Error("provider_secret_missing:OPENROUTER_API_KEY");
  if (!Array.isArray(input.messages) || input.messages.length < 1 || input.messages.length > 20) {
    throw new Error("invalid_messages");
  }

  const model = input.model?.trim() || sceneStoryModel();
  const response = await fetch("https://openrouter.ai/api/v1/chat/completions", {
    method: "POST",
    headers: {
      authorization: `Bearer ${apiKey}`,
      "content-type": "application/json",
      "x-openrouter-title": "Scene",
    },
    body: JSON.stringify({
      model,
      messages: input.messages,
      temperature: boundedNumber(input.temperature, 0.55, 0, 1.5),
      max_tokens: Math.floor(boundedNumber(input.maxTokens, 12000, 256, 16000)),
      ...(input.responseFormat ? { response_format: input.responseFormat } : {}),
    }),
  });

  if (!response.ok) {
    const body = await response.text().catch(() => "");
    throw new Error(`openrouter_request_failed:${response.status}:${body.slice(0, 300)}`);
  }

  const payload = await response.json() as Record<string, unknown>;
  const choices = Array.isArray(payload.choices) ? payload.choices as Array<Record<string, unknown>> : [];
  const message = choices[0]?.message as Record<string, unknown> | undefined;
  const content = typeof message?.content === "string" ? message.content.trim() : "";
  if (!content) throw new Error("openrouter_empty_response");

  return {
    provider: "openrouter",
    model: typeof payload.model === "string" && payload.model.trim() ? payload.model : model,
    providerRequestId: typeof payload.id === "string" && payload.id.trim() ? payload.id : null,
    content,
    usage: payload.usage ?? null,
  };
}
