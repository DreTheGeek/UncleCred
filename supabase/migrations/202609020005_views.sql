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
create view studio.format_performance_summary as
 SELECT f.organization_id,
    f.id AS format_id,
    f.format_code,
    f.name AS format_name,
    count(DISTINCT e.id) AS episodes,
    count(DISTINCT pp.id) FILTER (WHERE ((pp.status)::text = 'published'::text)) AS published_posts,
    (COALESCE(sum(cm.views), (0)::numeric))::bigint AS views,
    (COALESCE(sum(cm.likes), (0)::numeric))::bigint AS likes,
    (COALESCE(sum(cm.comments), (0)::numeric))::bigint AS comments,
    (COALESCE(sum(cm.shares), (0)::numeric))::bigint AS shares,
    (COALESCE(sum(cm.saves), (0)::numeric))::bigint AS saves,
    (COALESCE(sum(cm.leads), (0)::numeric))::bigint AS leads,
    (COALESCE(sum(cm.customers), (0)::numeric))::bigint AS customers,
    COALESCE(sum(cm.revenue), (0)::numeric) AS revenue,
    avg(cm.avg_percentage_viewed) AS avg_percentage_viewed,
    avg(cm.completion_rate) AS avg_completion_rate,
    avg(cm.audience_quality_score) AS avg_audience_quality_score,
    max(cm.observed_at) AS last_metric_at
   FROM (((studio.content_formats f
     LEFT JOIN studio.episodes e ON ((e.format_id = f.id)))
     LEFT JOIN studio.platform_posts pp ON ((pp.episode_id = e.id)))
     LEFT JOIN studio.content_metrics cm ON ((cm.platform_post_id = pp.id)))
  GROUP BY f.organization_id, f.id, f.format_code, f.name;
create view studio.production_os_readiness as
 SELECT organization_id,
    id AS episode_id,
    episode_code,
    working_title,
    production_state,
    ( SELECT count(*) AS count
           FROM studio.packaging_hypotheses p
          WHERE (p.episode_id = e.id)) AS packaging_hypotheses,
    ( SELECT count(*) AS count
           FROM studio.claim_ledger c
          WHERE ((c.episode_id = e.id) AND (c.verification_status = ANY (ARRAY['unverified'::text, 'rejected'::text])))) AS unresolved_claims,
    ( SELECT count(*) AS count
           FROM studio.production_requirements r
          WHERE ((r.episode_id = e.id) AND r.required AND (r.status <> ALL (ARRAY['ready'::text, 'captured'::text, 'waived'::text])))) AS unresolved_requirements,
    (EXISTS ( SELECT 1
           FROM studio.scripts s
          WHERE ((s.episode_id = e.id) AND (s.status = ANY (ARRAY['ready'::platform.work_status, 'approved'::platform.work_status]))))) AS has_script,
    (EXISTS ( SELECT 1
           FROM studio.edit_decision_specs x
          WHERE (x.episode_id = e.id))) AS has_edit_spec,
    (EXISTS ( SELECT 1
           FROM studio.production_postmortems pm
          WHERE ((pm.episode_id = e.id) AND (pm.status = ANY (ARRAY['complete'::text, 'approved'::text]))))) AS has_postmortem,
    updated_at
   FROM studio.episodes e;
