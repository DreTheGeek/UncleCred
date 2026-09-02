-- Functions and views referencing unported schemas. As of 2026-09-02 one item: system.health_summary reads dre_api.api_clients (cortex). Rewrite against system.api_keys before applying.
/*
create view system.health_summary as
 SELECT now() AS checked_at,
    ( SELECT count(*) AS count
           FROM platform.organizations) AS organizations,
    ( SELECT count(*) AS count
           FROM platform.organization_members) AS organization_members,
    ( SELECT count(*) AS count
           FROM platform.people) AS people,
    ( SELECT count(*) AS count
           FROM platform.companies) AS companies,
    ( SELECT count(*) AS count
           FROM platform.products) AS products,
    ( SELECT count(*) AS count
           FROM platform.projects) AS projects,
    ( SELECT count(*) AS count
           FROM knowledge.documents) AS documents,
    ( SELECT count(*) AS count
           FROM knowledge.document_chunks) AS document_chunks,
    ( SELECT count(*) AS count
           FROM knowledge.document_chunks
          WHERE (document_chunks.embedding IS NOT NULL)) AS embedded_chunks,
    ( SELECT count(*) AS count
           FROM knowledge.memories) AS memories,
    ( SELECT count(*) AS count
           FROM knowledge.entities) AS graph_entities,
    ( SELECT count(*) AS count
           FROM knowledge.relations) AS graph_relations,
    ( SELECT count(*) AS count
           FROM knowledge.claims) AS graph_claims,
    ( SELECT count(*) AS count
           FROM studio.production_days) AS production_days,
    ( SELECT count(*) AS count
           FROM studio.episodes) AS episodes,
    ( SELECT count(*) AS count
           FROM studio.episode_cues) AS episode_cues,
    ( SELECT count(*) AS count
           FROM studio.content_learnings) AS content_learnings,
    ( SELECT count(*) AS count
           FROM research.creator_profiles) AS creator_profiles,
    ( SELECT count(*) AS count
           FROM research.creator_mechanisms) AS creator_mechanisms,
    ( SELECT count(*) AS count
           FROM dre_api.api_clients
          WHERE ((api_clients.active = true) AND ((api_clients.expires_at IS NULL) OR (api_clients.expires_at > now())))) AS active_api_clients,
    ( SELECT count(*) AS count
           FROM dre_api.request_log) AS gateway_requests;
*/
