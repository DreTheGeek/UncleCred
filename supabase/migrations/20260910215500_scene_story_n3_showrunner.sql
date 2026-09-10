-- Scene N3 deterministic Showrunner persistence.
-- AI proposes a typed package. This transaction validates ownership/references and persists the plan atomically.

ALTER TABLE story.story_blocks ADD COLUMN IF NOT EXISTS planning jsonb NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE story.episodes ADD COLUMN IF NOT EXISTS planning jsonb NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE story.scenes ADD COLUMN IF NOT EXISTS planning jsonb NOT NULL DEFAULT '{}'::jsonb;

CREATE TABLE IF NOT EXISTS story.character_destinations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES platform.organizations(id) ON DELETE CASCADE,
  show_id uuid NOT NULL,
  blueprint_id uuid NOT NULL REFERENCES story.show_blueprints(id) ON DELETE CASCADE,
  character_id uuid NOT NULL,
  start_state jsonb NOT NULL DEFAULT '{}'::jsonb,
  final_state jsonb NOT NULL DEFAULT '{}'::jsonb,
  transformation text,
  non_negotiables jsonb NOT NULL DEFAULT '[]'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (blueprint_id, character_id),
  FOREIGN KEY (show_id, organization_id) REFERENCES story.shows(id, organization_id) ON DELETE CASCADE,
  FOREIGN KEY (character_id, show_id, organization_id) REFERENCES story.characters(id, show_id, organization_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS story.relationship_destinations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES platform.organizations(id) ON DELETE CASCADE,
  show_id uuid NOT NULL,
  blueprint_id uuid NOT NULL REFERENCES story.show_blueprints(id) ON DELETE CASCADE,
  relationship_id uuid NOT NULL,
  start_state jsonb NOT NULL DEFAULT '{}'::jsonb,
  final_state jsonb NOT NULL DEFAULT '{}'::jsonb,
  required_turns jsonb NOT NULL DEFAULT '[]'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (blueprint_id, relationship_id),
  FOREIGN KEY (show_id, organization_id) REFERENCES story.shows(id, organization_id) ON DELETE CASCADE,
  FOREIGN KEY (relationship_id, show_id, organization_id) REFERENCES story.relationships(id, show_id, organization_id) ON DELETE CASCADE
);

ALTER TABLE story.character_destinations ENABLE ROW LEVEL SECURITY;
ALTER TABLE story.relationship_destinations ENABLE ROW LEVEL SECURITY;
CREATE POLICY story_members_read_character_destinations ON story.character_destinations FOR SELECT TO authenticated USING (platform.is_org_member(organization_id));
CREATE POLICY story_admins_write_character_destinations ON story.character_destinations FOR ALL TO authenticated USING (platform.is_org_admin(organization_id)) WITH CHECK (platform.is_org_admin(organization_id));
CREATE POLICY story_members_read_relationship_destinations ON story.relationship_destinations FOR SELECT TO authenticated USING (platform.is_org_member(organization_id));
CREATE POLICY story_admins_write_relationship_destinations ON story.relationship_destinations FOR ALL TO authenticated USING (platform.is_org_admin(organization_id)) WITH CHECK (platform.is_org_admin(organization_id));

CREATE UNIQUE INDEX IF NOT EXISTS story_blocks_show_position_no_season
  ON story.story_blocks(show_id,position) WHERE season_id IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS story_episodes_show_number_no_season
  ON story.episodes(show_id,episode_number) WHERE season_id IS NULL;

CREATE OR REPLACE FUNCTION story.persist_showrunner_package(
  p_organization_id uuid,
  p_show_id uuid,
  p_actor_user_id uuid,
  p_package jsonb,
  p_model_provider text,
  p_model_name text,
  p_provider_request_id text,
  p_input_hash text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'pg_catalog', 'auth', 'platform', 'story', 'system'
AS $$
DECLARE
  v_show story.shows%ROWTYPE;
  v_blueprint jsonb := p_package->'blueprint';
  v_existing story.show_blueprints%ROWTYPE;
  v_blueprint_id uuid;
  v_version integer;
  v_season_id uuid;
  v_arc_id uuid;
  v_block_id uuid;
  v_episode_id uuid;
  v_scene_id uuid;
  v_character jsonb;
  v_relationship jsonb;
  v_destination jsonb;
  v_node jsonb;
  v_dependency jsonb;
  v_character_id uuid;
  v_character_a_id uuid;
  v_character_b_id uuid;
  v_relationship_id uuid;
  v_node_id uuid;
  v_pred_id uuid;
  v_succ_id uuid;
  v_initial_arc jsonb := p_package->'initialArc';
  v_initial_block jsonb := p_package->'initialBlock';
  v_initial_episode jsonb := p_package->'initialEpisode';
  v_initial_scene jsonb := p_package->'initialScene';
  v_final_state jsonb;
BEGIN
  IF p_package IS NULL OR jsonb_typeof(p_package) <> 'object' THEN RAISE EXCEPTION 'showrunner_package_required'; END IF;
  IF v_blueprint IS NULL OR jsonb_typeof(v_blueprint) <> 'object' THEN RAISE EXCEPTION 'showrunner_blueprint_required'; END IF;
  IF NULLIF(p_input_hash,'') IS NULL THEN RAISE EXCEPTION 'showrunner_input_hash_required'; END IF;

  SELECT * INTO v_show FROM story.shows
  WHERE id=p_show_id AND organization_id=p_organization_id
  FOR UPDATE;
  IF v_show.id IS NULL THEN RAISE EXCEPTION 'show_not_found'; END IF;

  IF auth.uid() IS NOT NULL AND auth.uid() <> p_actor_user_id THEN RAISE EXCEPTION 'actor_mismatch'; END IF;
  IF auth.uid() IS NOT NULL AND NOT platform.is_org_admin(p_organization_id) THEN RAISE EXCEPTION 'forbidden'; END IF;

  IF EXISTS (SELECT 1 FROM story.scenes WHERE show_id=p_show_id AND status='canonical'::story.scene_status) THEN
    RAISE EXCEPTION 'blueprint_rebuild_requires_impact_analysis';
  END IF;

  SELECT * INTO v_existing FROM story.show_blueprints
  WHERE show_id=p_show_id AND status='active'
  ORDER BY version DESC LIMIT 1;
  IF v_existing.id IS NOT NULL THEN
    IF v_existing.input_hash = p_input_hash THEN
      RETURN jsonb_build_object('status','already_persisted','blueprint_id',v_existing.id,'version',v_existing.version);
    END IF;
    RAISE EXCEPTION 'active_blueprint_exists';
  END IF;

  IF jsonb_array_length(COALESCE(p_package->'characters','[]'::jsonb)) = 0 THEN RAISE EXCEPTION 'showrunner_characters_required'; END IF;
  IF NULLIF(v_initial_arc->>'key','') IS NULL THEN RAISE EXCEPTION 'initial_arc_key_required'; END IF;
  IF NULLIF(v_initial_scene->>'purpose','') IS NULL THEN RAISE EXCEPTION 'initial_scene_purpose_required'; END IF;

  SELECT COALESCE(max(version),0)+1 INTO v_version FROM story.show_blueprints WHERE show_id=p_show_id;
  INSERT INTO story.show_blueprints(organization_id,show_id,version,status,blueprint,model_provider,model_name,provider_request_id,input_hash,created_by)
  VALUES(p_organization_id,p_show_id,v_version,'active',v_blueprint,p_model_provider,p_model_name,p_provider_request_id,p_input_hash,p_actor_user_id)
  RETURNING id INTO v_blueprint_id;

  INSERT INTO story.seasons(organization_id,show_id,season_number,title,status)
  VALUES(p_organization_id,p_show_id,1,'Season 1','active')
  ON CONFLICT(show_id,season_number) DO UPDATE SET updated_at=now()
  RETURNING id INTO v_season_id;

  FOR v_character IN SELECT value FROM jsonb_array_elements(COALESCE(p_package->'characters','[]'::jsonb)) LOOP
    IF NULLIF(v_character->>'key','') IS NULL OR NULLIF(v_character->>'name','') IS NULL THEN RAISE EXCEPTION 'invalid_character_plan'; END IF;
    INSERT INTO story.characters(organization_id,show_id,character_key,name,narrative_role,description,base_traits,current_state,status)
    VALUES(p_organization_id,p_show_id,v_character->>'key',v_character->>'name',v_character->>'narrativeRole',v_character->>'description',COALESCE(v_character->'baseTraits','{}'::jsonb),COALESCE(v_character->'startState','{}'::jsonb),'active')
    ON CONFLICT(show_id,character_key) DO UPDATE SET name=excluded.name,narrative_role=excluded.narrative_role,description=excluded.description,base_traits=excluded.base_traits,current_state=excluded.current_state,updated_at=now();
  END LOOP;

  FOR v_relationship IN SELECT value FROM jsonb_array_elements(COALESCE(p_package->'relationships','[]'::jsonb)) LOOP
    SELECT id INTO v_character_a_id FROM story.characters WHERE show_id=p_show_id AND character_key=v_relationship->>'characterAKey';
    SELECT id INTO v_character_b_id FROM story.characters WHERE show_id=p_show_id AND character_key=v_relationship->>'characterBKey';
    IF v_character_a_id IS NULL OR v_character_b_id IS NULL OR v_character_a_id=v_character_b_id THEN RAISE EXCEPTION 'relationship_character_reference_invalid'; END IF;
    INSERT INTO story.relationships(organization_id,show_id,character_a_id,character_b_id,relationship_type,dimensions,current_state)
    VALUES(p_organization_id,p_show_id,v_character_a_id,v_character_b_id,v_relationship->>'relationshipType',COALESCE(v_relationship->'dimensions','{}'::jsonb),COALESCE(v_relationship->'startState','{}'::jsonb))
    ON CONFLICT(show_id,character_a_id,character_b_id) DO UPDATE SET relationship_type=excluded.relationship_type,dimensions=excluded.dimensions,current_state=excluded.current_state,updated_at=now();
  END LOOP;

  v_final_state := COALESCE(v_blueprint->'finalState','{}'::jsonb);
  INSERT INTO story.final_state_contracts(organization_id,show_id,scope_type,scope_id,locked,contract,version)
  VALUES(p_organization_id,p_show_id,'show',p_show_id,false,v_final_state,v_version);

  FOR v_node IN SELECT value FROM jsonb_array_elements(COALESCE(v_blueprint->'futureNodes','[]'::jsonb)) LOOP
    IF NULLIF(v_node->>'key','') IS NULL THEN RAISE EXCEPTION 'future_node_key_required'; END IF;
    INSERT INTO story.future_story_nodes(organization_id,show_id,season_id,node_key,node_type,title,description,status,scheduling_mode,earliest_episode,latest_episode,exact_episode,priority,locked,payload)
    VALUES(
      p_organization_id,p_show_id,v_season_id,v_node->>'key',COALESCE(NULLIF(v_node->>'nodeType',''),'story_event'),COALESCE(NULLIF(v_node->>'title',''),v_node->>'key'),v_node->>'description','planned',
      COALESCE(NULLIF(v_node->>'schedulingMode','')::story.scheduling_mode,'windowed'::story.scheduling_mode),
      NULLIF(v_node->>'earliestEpisode','')::integer,NULLIF(v_node->>'latestEpisode','')::integer,NULLIF(v_node->>'exactEpisode','')::integer,
      COALESCE(NULLIF(v_node->>'priority','')::integer,0),COALESCE((v_node->>'locked')::boolean,false),COALESCE(v_node->'payload','{}'::jsonb)
    );
  END LOOP;

  FOR v_dependency IN SELECT value FROM jsonb_array_elements(COALESCE(v_blueprint->'dependencies','[]'::jsonb)) LOOP
    SELECT id INTO v_pred_id FROM story.future_story_nodes WHERE show_id=p_show_id AND node_key=v_dependency->>'predecessorKey';
    SELECT id INTO v_succ_id FROM story.future_story_nodes WHERE show_id=p_show_id AND node_key=v_dependency->>'successorKey';
    IF v_pred_id IS NULL OR v_succ_id IS NULL OR v_pred_id=v_succ_id THEN RAISE EXCEPTION 'future_dependency_reference_invalid'; END IF;
    INSERT INTO story.future_story_dependencies(organization_id,show_id,predecessor_node_id,successor_node_id,dependency_type)
    VALUES(p_organization_id,p_show_id,v_pred_id,v_succ_id,COALESCE(NULLIF(v_dependency->>'type',''),'requires'));
  END LOOP;

  INSERT INTO story.story_arcs(organization_id,show_id,season_id,arc_key,title,summary,status,start_episode_hint,end_episode_hint,priority)
  VALUES(p_organization_id,p_show_id,v_season_id,v_initial_arc->>'key',v_initial_arc->>'title',v_initial_arc->>'summary','active',NULLIF(v_initial_arc->>'startEpisodeHint','')::integer,NULLIF(v_initial_arc->>'endEpisodeHint','')::integer,COALESCE(NULLIF(v_initial_arc->>'priority','')::integer,0))
  RETURNING id INTO v_arc_id;

  INSERT INTO story.story_blocks(organization_id,show_id,season_id,arc_id,position,title,objective,episode_window_start,episode_window_end,exit_conditions,status,planning)
  VALUES(p_organization_id,p_show_id,v_season_id,v_arc_id,COALESCE(NULLIF(v_initial_block->>'position','')::integer,1),'Opening Story Block',v_initial_block->>'objective',NULLIF(v_initial_block#>>'{episodeWindow,start}','')::integer,NULLIF(v_initial_block#>>'{episodeWindow,end}','')::integer,COALESCE(v_initial_block->'exitConditions','[]'::jsonb),'active',v_initial_block)
  RETURNING id INTO v_block_id;

  INSERT INTO story.episodes(organization_id,show_id,season_id,story_block_id,episode_number,title,objective,status,planning)
  VALUES(p_organization_id,p_show_id,v_season_id,v_block_id,COALESCE(NULLIF(v_initial_episode->>'episodeNumber','')::integer,1),'Episode 1',v_initial_episode->>'objective','planned',v_initial_episode)
  RETURNING id INTO v_episode_id;

  INSERT INTO story.scenes(organization_id,show_id,episode_id,scene_number,story_order,title,purpose,status,runtime_target_seconds,planning)
  VALUES(p_organization_id,p_show_id,v_episode_id,1,1.000000,'Scene 1',v_initial_scene->>'purpose','planned',COALESCE(NULLIF(v_initial_scene->>'runtimeTargetSeconds','')::integer,90),v_initial_scene)
  RETURNING id INTO v_scene_id;

  FOR v_destination IN SELECT value FROM jsonb_array_elements(COALESCE(v_blueprint->'characterDestinations','[]'::jsonb)) LOOP
    SELECT id INTO v_character_id FROM story.characters WHERE show_id=p_show_id AND character_key=v_destination->>'characterKey';
    IF v_character_id IS NULL THEN RAISE EXCEPTION 'character_destination_reference_invalid'; END IF;
    INSERT INTO story.character_destinations(organization_id,show_id,blueprint_id,character_id,start_state,final_state,transformation,non_negotiables)
    VALUES(p_organization_id,p_show_id,v_blueprint_id,v_character_id,COALESCE(v_destination->'startState','{}'::jsonb),COALESCE(v_destination->'finalState','{}'::jsonb),v_destination->>'transformation',COALESCE(v_destination->'nonNegotiables','[]'::jsonb));
  END LOOP;

  FOR v_destination IN SELECT value FROM jsonb_array_elements(COALESCE(v_blueprint->'relationshipDestinations','[]'::jsonb)) LOOP
    SELECT id INTO v_character_a_id FROM story.characters WHERE show_id=p_show_id AND character_key=v_destination->>'characterAKey';
    SELECT id INTO v_character_b_id FROM story.characters WHERE show_id=p_show_id AND character_key=v_destination->>'characterBKey';
    SELECT id INTO v_relationship_id FROM story.relationships WHERE show_id=p_show_id AND character_a_id=v_character_a_id AND character_b_id=v_character_b_id;
    IF v_relationship_id IS NULL THEN
      INSERT INTO story.relationships(organization_id,show_id,character_a_id,character_b_id,relationship_type,dimensions,current_state)
      VALUES(p_organization_id,p_show_id,v_character_a_id,v_character_b_id,'planned','{}'::jsonb,COALESCE(v_destination->'startState','{}'::jsonb))
      RETURNING id INTO v_relationship_id;
    END IF;
    INSERT INTO story.relationship_destinations(organization_id,show_id,blueprint_id,relationship_id,start_state,final_state,required_turns)
    VALUES(p_organization_id,p_show_id,v_blueprint_id,v_relationship_id,COALESCE(v_destination->'startState','{}'::jsonb),COALESCE(v_destination->'finalState','{}'::jsonb),COALESCE(v_destination->'requiredTurns','[]'::jsonb));
  END LOOP;

  INSERT INTO story.scene_characters(scene_id,show_id,organization_id,character_id,participation_role)
  SELECT v_scene_id,p_show_id,p_organization_id,c.id,
    CASE WHEN (v_initial_scene->'focalCharacterKeys') ? c.character_key THEN 'focal' ELSE 'present' END
  FROM story.characters c
  WHERE c.show_id=p_show_id AND (
    (v_initial_scene->'requiredCharacterKeys') ? c.character_key OR
    (v_initial_scene->'focalCharacterKeys') ? c.character_key
  )
  ON CONFLICT DO NOTHING;

  PERFORM system.emit_event(
    p_organization_id,'scene.showrunner.blueprint_persisted','story.show_blueprints',v_blueprint_id,
    jsonb_build_object('show_id',p_show_id,'version',v_version,'season_id',v_season_id,'arc_id',v_arc_id,'block_id',v_block_id,'episode_id',v_episode_id,'scene_id',v_scene_id,'model_provider',p_model_provider,'model_name',p_model_name),
    'scene-showrunner'
  );

  RETURN jsonb_build_object(
    'status','persisted','blueprint_id',v_blueprint_id,'version',v_version,
    'season_id',v_season_id,'arc_id',v_arc_id,'block_id',v_block_id,'episode_id',v_episode_id,'scene_id',v_scene_id
  );
END;
$$;

REVOKE ALL ON FUNCTION story.persist_showrunner_package(uuid,uuid,uuid,jsonb,text,text,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION story.persist_showrunner_package(uuid,uuid,uuid,jsonb,text,text,text,text) TO authenticated, service_role;
