# Migrations

Ported 2026-09-02 from the LaSeanPickens project (ref mbahmbszfbttnctcfzar) schemas dre_core, dre_media, dre_intelligence, dre_research, dre_knowledge, dre_graph, dre_system, dre_ai into the studio split:

| Source | Target |
|---|---|
| dre_core | platform |
| dre_media | studio (production and publishing tables split out in Phase 04 and 05) |
| dre_intelligence | intelligence |
| dre_research | research (kept separate: table names collide with intelligence) |
| dre_knowledge, dre_graph | knowledge |
| dre_system, dre_ai | system |

Not ported: dre_api, dre_app, dre_audit, dre_ops (cortex, Boss's personal OS), public.lp_*, df_*, fitness, openreply. They stay in LaSeanPickens.

Apply in order with `supabase db push` or `psql` against the studio project. RLS is enabled on every table (146 ported plus 5 new). Only 29 policies existed at the source, so most tables are service_role only until Phase 01 step 4 writes owner policies against platform.organization_members.

Source function bodies referencing unported schemas land in the needs_review file as comments. As of this port that file is empty, meaning every function body cleared the schema map.
