# packages/generation-router

The one seam every vendor call goes through. KICKOFF law: "No vendor call outside the
GenerationRouter." A caller states what it wants; the router decides which model serves it,
validates what comes back, and records what it cost.

## Why it exists

DECISIONS D4 and D5 are explicitly expected to change once the benchmark lab has data:
Kling versus Seedance for action, Hedra versus HeyGen for talking head. If model ids live in
callers, that ruling becomes a refactor. Here it is a row update in `system.ai_models`.

## Shape

    router.generate(request, context, filter?)

    request   discriminated union on capability, validated with Zod
    context   organizationId, purpose, episodeId, characterCode, traceId
    filter    optional pin: modelId, provider, requires[], allowCandidate

Every call, success or failure, writes one row to `system.ai_cost_ledger`. Successes also
emit `generation.<capability>.completed` to the immutable ledger.

## Identity safety

Passing a LoRA to an endpoint that cannot use one silently produces an off model character.
The fal adapter refuses that combination instead, because DECISIONS locks identity at 0.95
and a silently ignored LoRA is the failure that gets past a QA gate looking at the wrong
thing.

## Source

Ported in spirit from DreTheGeek/laseanpickens generation calls, rebuilt around the registry.
Model rows seeded from `.planning/RESEARCH.md`.

## Wired today

| Capability     | Provider | Status |
|---|---|---|
| image          | fal      | working, proven with UNCLECRED_V1 |
| transcription  | fal      | implemented, not yet exercised |
| voice          | elevenlabs | not wired, needs ELEVENLABS_API_KEY |
| video          | fal      | not wired |
| talking_head   | hedra / heygen | not wired |
