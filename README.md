# Uncle Cred

Autonomous AI animated studio. The Uncle Cred universe: Uncle Cred, Auntie APR, Repo Reggie, Mr. Denied, Funding Frank. Owner: Kaldr Business Group LLC.

Built under kaldr-build-system v6.4. Spine and organs come from DreTheGeek/kaldr-core and DreTheGeek/laseanpickens (the DRE content engine). See .planning/HARVEST-MAP.md for what gets pulled from where and .planning/KICKOFF.md to start the build in Claude Code.

## Laws
- AI can generate anything. Nothing becomes production truth until it passes the gate (images, video, scripts, claims, memory, canon, publish).
- Every external model is replaceable labor. The studio owns canon, memory, recipes, QA, and learning.
- Compliance guardrails (CROA, FTC testimonials rule, AI disclosure) are code, not prose.
- Zero em dashes anywhere, code comments included.
- Human approval on every episode until the QA data earns auto-approve.

## Layout (target)
- apps/studio: Next.js command center (Vercel)
- workers/: Trigger.dev tasks plus Railway containers for FFmpeg and Remotion
- packages/: canon, generation-router, qa-gate, publisher, knowledge, memory, money
- supabase/: migrations on the 7 schema split, edge functions
- .planning/: research, decisions, state, phases, kickoff
