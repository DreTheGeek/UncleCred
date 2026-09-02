-- RLS on every table. Default deny. Service role bypasses. Port of existing policies follows.
alter table system.agent_jobs enable row level security;
alter table system.ai_runs enable row level security;
alter table platform.companies enable row level security;
alter table platform.founder_intelligence enable row level security;
alter table platform.organization_members enable row level security;
alter table platform.organizations enable row level security;
alter table platform.people enable row level security;
alter table platform.products enable row level security;
alter table platform.projects enable row level security;
alter table knowledge.claims enable row level security;
alter table knowledge.entities enable row level security;
alter table knowledge.entity_aliases enable row level security;
alter table knowledge.relations enable row level security;
alter table intelligence.audience_segments enable row level security;
alter table intelligence.audience_simulations enable row level security;
alter table intelligence.content_feedback enable row level security;
alter table intelligence.content_request_runs enable row level security;
alter table intelligence.creator_mechanisms enable row level security;
alter table intelligence.creator_patterns enable row level security;
alter table intelligence.creator_profiles enable row level security;
alter table intelligence.creator_research_runs enable row level security;
alter table intelligence.creator_rules enable row level security;
alter table intelligence.creator_strengths_weaknesses enable row level security;
alter table intelligence.learning_queue enable row level security;
alter table intelligence.performance_hypotheses enable row level security;
alter table intelligence.performance_observations enable row level security;
alter table intelligence.planning_generation_events enable row level security;
alter table intelligence.preference_questions enable row level security;
alter table intelligence.preference_responses enable row level security;
alter table intelligence.preference_signals enable row level security;
alter table intelligence.revision_events enable row level security;
alter table intelligence.showrunner_constitutions enable row level security;
alter table intelligence.taste_events enable row level security;
alter table knowledge.document_chunks enable row level security;
alter table knowledge.documents enable row level security;
alter table knowledge.memories enable row level security;
alter table studio.approvals enable row level security;
alter table studio.asset_versions enable row level security;
alter table studio.assets enable row level security;
alter table studio.authority_franchises enable row level security;
alter table studio.beat_performance_observations enable row level security;
alter table studio.beat_time_ranges enable row level security;
alter table studio.broll_topic_queue enable row level security;
alter table studio.capture_checks enable row level security;
alter table studio.claim_ledger enable row level security;
alter table studio.clip_rotation_plans enable row level security;
alter table studio.clips enable row level security;
alter table studio.content_angle_templates enable row level security;
alter table studio.content_calendar enable row level security;
alter table studio.content_formats enable row level security;
alter table studio.content_freebies enable row level security;
alter table studio.content_funnel_mappings enable row level security;
alter table studio.content_idea_dimensions enable row level security;
alter table studio.content_idea_scores enable row level security;
alter table studio.content_ideas enable row level security;
alter table studio.content_learnings enable row level security;
alter table studio.content_lifecycle_events enable row level security;
alter table studio.content_metrics enable row level security;
alter table studio.content_offers enable row level security;
alter table studio.content_packages enable row level security;
alter table studio.content_programming_rules enable row level security;
alter table studio.content_series enable row level security;
alter table studio.content_slate_items enable row level security;
alter table studio.content_slates enable row level security;
alter table studio.content_state_events enable row level security;
alter table studio.content_value_dimensions enable row level security;
alter table studio.creative_evaluations enable row level security;
alter table studio.creative_experiment_variants enable row level security;
alter table studio.creative_experiments enable row level security;
alter table studio.creative_lineage enable row level security;
alter table studio.curricula enable row level security;
alter table studio.curriculum_lessons enable row level security;
alter table studio.curriculum_phases enable row level security;
alter table studio.distribution_packages enable row level security;
alter table studio.edit_decision_specs enable row level security;
alter table studio.episode_beats enable row level security;
alter table studio.episode_cues enable row level security;
alter table studio.episode_research_jobs enable row level security;
alter table studio.episode_reviews enable row level security;
alter table studio.episode_track_links enable row level security;
alter table studio.episodes enable row level security;
alter table studio.format_variants enable row level security;
alter table studio.hooks enable row level security;
alter table studio.lead_magnet_events enable row level security;
alter table studio.media_jobs enable row level security;
alter table studio.packaging_hypotheses enable row level security;
alter table studio.performance_observations enable row level security;
alter table studio.pipeline_events enable row level security;
alter table studio.pipeline_runs enable row level security;
alter table studio.pipeline_stages enable row level security;
alter table studio.platform_posts enable row level security;
alter table studio.production_blocks enable row level security;
alter table studio.production_days enable row level security;
alter table studio.production_postmortems enable row level security;
alter table studio.production_requirements enable row level security;
alter table studio.publishing_jobs enable row level security;
alter table studio.publishing_templates enable row level security;
alter table studio.rate_cards enable row level security;
alter table studio.retention_points enable row level security;
alter table studio.review_comments enable row level security;
alter table studio.scripts enable row level security;
alter table studio.series_tracks enable row level security;
alter table studio.slate_evaluations enable row level security;
alter table studio.sponsor_brands enable row level security;
alter table studio.sponsor_deals enable row level security;
alter table studio.sponsor_deliverables enable row level security;
alter table studio.sponsor_performance enable row level security;
alter table studio.stage_gate_evaluations enable row level security;
alter table studio.stage_gate_policies enable row level security;
alter table studio.takes enable row level security;
alter table studio.thumbnails enable row level security;
alter table studio.titles enable row level security;
alter table studio.trend_queue enable row level security;
alter table studio.visual_characters enable row level security;
alter table studio.visual_environments enable row level security;
alter table studio.visual_props enable row level security;
alter table studio.visual_styles enable row level security;
alter table studio.youtube_reach_daily enable row level security;
alter table research.creator_capabilities enable row level security;
alter table research.creator_channels enable row level security;
alter table research.creator_examples enable row level security;
alter table research.creator_experiments enable row level security;
alter table research.creator_formats enable row level security;
alter table research.creator_mechanisms enable row level security;
alter table research.creator_pattern_evidence enable row level security;
alter table research.creator_profile_capabilities enable row level security;
alter table research.creator_profiles enable row level security;
alter table research.creator_research_runs enable row level security;
alter table research.creator_sources enable row level security;
alter table research.research_jobs enable row level security;
alter table research.research_notes enable row level security;
alter table research.research_sources enable row level security;
alter table system.acceptance_runs enable row level security;
alter table system.automation_events enable row level security;
alter table system.automation_policies enable row level security;
alter table system.automation_runs enable row level security;
alter table system.deployments enable row level security;
alter table system.integrations enable row level security;
alter table system.mcp_access_tokens enable row level security;
alter table system.mcp_auth_codes enable row level security;
alter table system.mcp_oauth_clients enable row level security;
alter table system.production_compiler_acceptance_runs enable row level security;
alter table system.stage_gate_definitions enable row level security;
alter table system.workflow_definitions enable row level security;
alter table system.workflow_events enable row level security;
alter table system.workflow_runs enable row level security;
create policy "org admins write companies" on platform.companies as permissive for all to authenticated using (platform.is_org_admin(organization_id)) with check (platform.is_org_admin(organization_id));
create policy "org members read companies" on platform.companies as permissive for select to authenticated using (platform.is_org_member(organization_id));
create policy "admins manage memberships" on platform.organization_members as permissive for all to authenticated using (platform.is_org_admin(organization_id)) with check (platform.is_org_admin(organization_id));
create policy "members read memberships" on platform.organization_members as permissive for select to authenticated using (((user_id = ( SELECT auth.uid() AS uid)) OR platform.is_org_admin(organization_id)));
create policy "org members read organizations" on platform.organizations as permissive for select to authenticated using (platform.is_org_member(id));
create policy "org admins write people" on platform.people as permissive for all to authenticated using (platform.is_org_admin(organization_id)) with check (platform.is_org_admin(organization_id));
create policy "org members read people" on platform.people as permissive for select to authenticated using (platform.is_org_member(organization_id));
create policy "org admins write products" on platform.products as permissive for all to authenticated using (platform.is_org_admin(organization_id)) with check (platform.is_org_admin(organization_id));
create policy "org members read products" on platform.products as permissive for select to authenticated using (platform.is_org_member(organization_id));
create policy "org admins write projects" on platform.projects as permissive for all to authenticated using (platform.is_org_admin(organization_id)) with check (platform.is_org_admin(organization_id));
create policy "org members read projects" on platform.projects as permissive for select to authenticated using (platform.is_org_member(organization_id));
create policy "org admins write claims" on knowledge.claims as permissive for all to authenticated using (platform.is_org_admin(organization_id)) with check (platform.is_org_admin(organization_id));
create policy "org members read claims" on knowledge.claims as permissive for select to authenticated using (platform.is_org_member(organization_id));
create policy "org admins write entities" on knowledge.entities as permissive for all to authenticated using (platform.is_org_admin(organization_id)) with check (platform.is_org_admin(organization_id));
create policy "org members read entities" on knowledge.entities as permissive for select to authenticated using (platform.is_org_member(organization_id));
create policy "org admins write entity_aliases" on knowledge.entity_aliases as permissive for all to authenticated using ((EXISTS ( SELECT 1
   FROM knowledge.entities e
  WHERE ((e.id = entity_aliases.entity_id) AND platform.is_org_admin(e.organization_id))))) with check ((EXISTS ( SELECT 1
   FROM knowledge.entities e
  WHERE ((e.id = entity_aliases.entity_id) AND platform.is_org_admin(e.organization_id)))));
create policy "org members read entity_aliases" on knowledge.entity_aliases as permissive for select to authenticated using ((EXISTS ( SELECT 1
   FROM knowledge.entities e
  WHERE ((e.id = entity_aliases.entity_id) AND platform.is_org_member(e.organization_id)))));
create policy "org admins write relations" on knowledge.relations as permissive for all to authenticated using (platform.is_org_admin(organization_id)) with check (platform.is_org_admin(organization_id));
create policy "org members read relations" on knowledge.relations as permissive for select to authenticated using (platform.is_org_member(organization_id));
create policy "org admins write document_chunks" on knowledge.document_chunks as permissive for all to authenticated using (platform.is_org_admin(organization_id)) with check (platform.is_org_admin(organization_id));
create policy "org members read document_chunks" on knowledge.document_chunks as permissive for select to authenticated using (platform.is_org_member(organization_id));
create policy "org admins write documents" on knowledge.documents as permissive for all to authenticated using (platform.is_org_admin(organization_id)) with check (platform.is_org_admin(organization_id));
create policy "org members read documents" on knowledge.documents as permissive for select to authenticated using (platform.is_org_member(organization_id));
create policy "org admins write memories" on knowledge.memories as permissive for all to authenticated using (platform.is_org_admin(organization_id)) with check (platform.is_org_admin(organization_id));
create policy "org members read memories" on knowledge.memories as permissive for select to authenticated using (platform.is_org_member(organization_id));
create policy owner_content_freebies on studio.content_freebies as permissive for all to authenticated using ((EXISTS ( SELECT 1
   FROM platform.organization_members om
  WHERE ((om.organization_id = content_freebies.organization_id) AND (om.user_id = auth.uid()) AND (om.status = 'active'::text) AND (om.role = 'owner'::text))))) with check ((EXISTS ( SELECT 1
   FROM platform.organization_members om
  WHERE ((om.organization_id = content_freebies.organization_id) AND (om.user_id = auth.uid()) AND (om.status = 'active'::text) AND (om.role = 'owner'::text)))));
create policy owner_content_funnel_mappings on studio.content_funnel_mappings as permissive for all to authenticated using ((EXISTS ( SELECT 1
   FROM platform.organization_members om
  WHERE ((om.organization_id = content_funnel_mappings.organization_id) AND (om.user_id = auth.uid()) AND (om.status = 'active'::text) AND (om.role = 'owner'::text))))) with check ((EXISTS ( SELECT 1
   FROM platform.organization_members om
  WHERE ((om.organization_id = content_funnel_mappings.organization_id) AND (om.user_id = auth.uid()) AND (om.status = 'active'::text) AND (om.role = 'owner'::text)))));
create policy owner_content_offers on studio.content_offers as permissive for all to authenticated using ((EXISTS ( SELECT 1
   FROM platform.organization_members om
  WHERE ((om.organization_id = content_offers.organization_id) AND (om.user_id = auth.uid()) AND (om.status = 'active'::text) AND (om.role = 'owner'::text))))) with check ((EXISTS ( SELECT 1
   FROM platform.organization_members om
  WHERE ((om.organization_id = content_offers.organization_id) AND (om.user_id = auth.uid()) AND (om.status = 'active'::text) AND (om.role = 'owner'::text)))));
create policy owner_lead_magnet_events on studio.lead_magnet_events as permissive for select to authenticated using ((EXISTS ( SELECT 1
   FROM platform.organization_members om
  WHERE ((om.organization_id = lead_magnet_events.organization_id) AND (om.user_id = auth.uid()) AND (om.status = 'active'::text) AND (om.role = 'owner'::text)))));
