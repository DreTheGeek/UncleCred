# KICKOFF (paste into Claude Code at the repo root)

You are building Financial District Studios under kaldr-build-system v6.4. Read in this order before writing any code:
1. .planning/STATE.md
2. .planning/DECISIONS.md (locked, do not reopen)
3. .planning/RESEARCH.md
4. .planning/HARVEST-MAP.md
5. .planning/phases/PHASES.md
Then load the skills: kaldr-build-system, fable-mode, kb-design (before any UI), kb-smart-systems (before any schema), kb-prompting (before any prompt), kaldr-tenant-factory (before tenancy or queues), kb-credit-repair (before any credit content), lesson-loop (any lesson learned).

Sources you can read directly: DreTheGeek/laseanpickens (the DRE content engine) and DreTheGeek/kaldr-core (doctrine, knowledge, harvest). Copy nothing verbatim into packages/; port it and cite the source path in each package README.

Session 1 = Phase 01 Spine. Start with the STATE CHECK, write .planning/DISCOVERY.md from DECISIONS.md, then execute Phase 01 to its gate. Stop at the gate and report VERIFICATION.md evidence, not claims.

Laws: JSON schemas on every AI output (Zod). No vendor call outside the GenerationRouter. No API key in code, prompts, or DB. Every destructive route uses confirm-destructive. Zero em dashes. Env names in .env.example only.
