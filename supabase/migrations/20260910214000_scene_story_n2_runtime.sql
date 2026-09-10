-- Scene N2 narrative runtime on the shared UncleCred backend.
-- Canonical truth is committed atomically from staged proposals.
-- MVP safety: scenes must canonicalize in story_order so current_state cannot leak future-story state.

CREATE OR REPLACE FUNCTION story.jsonb_deep_merge(base jsonb, patch jsonb)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
SET search_path = 'pg_catalog'
AS $$
  SELECT CASE
    WHEN jsonb_typeof(base) = 'object' AND jsonb_typeof(patch) = 'object' THEN (
      SELECT jsonb_object_agg(k, v)
      FROM (
        SELECT key AS k,
          CASE
            WHEN base ? key AND patch ? key THEN story.jsonb_deep_merge(base->key, patch->key)
            WHEN patch ? key THEN patch->key
            ELSE base->key
          END AS v
        FROM (
          SELECT jsonb_object_keys(base) AS key
          UNION
          SELECT jsonb_object_keys(patch) AS key
        ) keys
      ) merged
    )
    ELSE patch
  END;
$$;

CREATE OR REPLACE FUNCTION story.guard_scene_canonical_transition()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = 'pg_catalog', 'story'
AS $$
BEGIN
  IF NEW.status = 'canonical'::story.scene_status
     AND OLD.status IS DISTINCT FROM 'canonical'::story.scene_status
     AND COALESCE(current_setting('scene_story.commit_authorized', true), 'false') <> 'true' THEN
    RAISE EXCEPTION 'scene_canonical_transition_requires_commit_function';
  END IF;

  IF OLD.status = 'canonical'::story.scene_status
     AND NEW.status IS DISTINCT FROM OLD.status THEN
    RAISE EXCEPTION 'canonical_scene_status_is_immutable';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS scenes_guard_canonical_transition ON story.scenes;
CREATE TRIGGER scenes_guard_canonical_transition
  BEFORE UPDATE OF status ON story.scenes
  FOR EACH ROW EXECUTE FUNCTION story.guard_scene_canonical_transition();

CREATE OR REPLACE FUNCTION story.commit_approved_scene(
  p_scene_id uuid,
  p_expected_canonical_version integer DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'pg_catalog', 'auth', 'platform', 'story', 'system'
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_scene story.scenes%ROWTYPE;
  v_event story.story_event_proposals%ROWTYPE;
  v_event_count integer := 0;
  v_patch jsonb;
  v_character_id uuid;
  v_fact_id uuid;
  v_state story.knowledge_state;
  v_confidence numeric(4,3);
  v_reveal_id uuid;
  v_previous_story_order numeric(20,6);
  v_snapshot_version integer;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;

  SELECT * INTO v_scene FROM story.scenes WHERE id = p_scene_id FOR UPDATE;
  IF v_scene.id IS NULL THEN RETURN jsonb_build_object('status','not_found'); END IF;
  IF NOT platform.is_org_member(v_scene.organization_id) THEN RETURN jsonb_build_object('status','not_found'); END IF;

  IF v_scene.status = 'canonical'::story.scene_status THEN
    RETURN jsonb_build_object('status','already_canonical','scene_id',v_scene.id,'canonical_version',v_scene.canonical_version);
  END IF;
  IF v_scene.status <> 'approved'::story.scene_status THEN
    RETURN jsonb_build_object('status','not_approved','scene_status',v_scene.status);
  END IF;
  IF v_scene.canonical_version <> p_expected_canonical_version THEN
    RETURN jsonb_build_object('status','version_conflict','expected',p_expected_canonical_version,'actual',v_scene.canonical_version);
  END IF;

  SELECT max(story_order) INTO v_previous_story_order
  FROM story.scenes
  WHERE show_id = v_scene.show_id AND status = 'canonical'::story.scene_status;

  IF v_previous_story_order IS NOT NULL AND v_scene.story_order < v_previous_story_order THEN
    RETURN jsonb_build_object(
      'status','story_order_conflict',
      'message','MVP sequential-canon guard blocks canonicalizing earlier story time after later canon',
      'latest_canonical_story_order',v_previous_story_order,
      'requested_story_order',v_scene.story_order
    );
  END IF;

  FOR v_event IN
    SELECT * FROM story.story_event_proposals
    WHERE scene_id = v_scene.id
    ORDER BY event_sequence, created_at, id
    FOR UPDATE
  LOOP
    v_event_count := v_event_count + 1;

    IF v_event.event_type = 'character.state_patch' THEN
      IF v_event.subject_id IS NULL THEN RAISE EXCEPTION 'character_state_patch_missing_subject'; END IF;
      v_patch := COALESCE(v_event.payload->'patch','{}'::jsonb);
      UPDATE story.characters SET current_state = story.jsonb_deep_merge(current_state,v_patch), updated_at = now()
      WHERE id=v_event.subject_id AND show_id=v_scene.show_id AND organization_id=v_scene.organization_id;
      IF NOT FOUND THEN RAISE EXCEPTION 'character_state_patch_subject_not_found'; END IF;

    ELSIF v_event.event_type = 'location.state_patch' THEN
      IF v_event.subject_id IS NULL THEN RAISE EXCEPTION 'location_state_patch_missing_subject'; END IF;
      v_patch := COALESCE(v_event.payload->'patch','{}'::jsonb);
      UPDATE story.locations SET current_state = story.jsonb_deep_merge(current_state,v_patch), updated_at = now()
      WHERE id=v_event.subject_id AND show_id=v_scene.show_id AND organization_id=v_scene.organization_id;
      IF NOT FOUND THEN RAISE EXCEPTION 'location_state_patch_subject_not_found'; END IF;

    ELSIF v_event.event_type = 'prop.state_patch' THEN
      IF v_event.subject_id IS NULL THEN RAISE EXCEPTION 'prop_state_patch_missing_subject'; END IF;
      v_patch := COALESCE(v_event.payload->'patch','{}'::jsonb);
      UPDATE story.props SET current_state = story.jsonb_deep_merge(current_state,v_patch), updated_at = now()
      WHERE id=v_event.subject_id AND show_id=v_scene.show_id AND organization_id=v_scene.organization_id;
      IF NOT FOUND THEN RAISE EXCEPTION 'prop_state_patch_subject_not_found'; END IF;

    ELSIF v_event.event_type = 'prop.transfer' THEN
      IF v_event.subject_id IS NULL THEN RAISE EXCEPTION 'prop_transfer_missing_subject'; END IF;
      UPDATE story.props
      SET owner_character_id = CASE WHEN v_event.payload ? 'owner_character_id' THEN NULLIF(v_event.payload->>'owner_character_id','')::uuid ELSE owner_character_id END,
          current_location_id = CASE WHEN v_event.payload ? 'location_id' THEN NULLIF(v_event.payload->>'location_id','')::uuid ELSE current_location_id END,
          current_state = story.jsonb_deep_merge(current_state,COALESCE(v_event.payload->'state_patch','{}'::jsonb)),
          updated_at = now()
      WHERE id=v_event.subject_id AND show_id=v_scene.show_id AND organization_id=v_scene.organization_id;
      IF NOT FOUND THEN RAISE EXCEPTION 'prop_transfer_subject_not_found'; END IF;

    ELSIF v_event.event_type = 'relationship.state_patch' THEN
      IF v_event.subject_id IS NULL THEN RAISE EXCEPTION 'relationship_state_patch_missing_subject'; END IF;
      v_patch := COALESCE(v_event.payload->'patch','{}'::jsonb);
      UPDATE story.relationships SET current_state = story.jsonb_deep_merge(current_state,v_patch), updated_at = now()
      WHERE id=v_event.subject_id AND show_id=v_scene.show_id AND organization_id=v_scene.organization_id;
      IF NOT FOUND THEN RAISE EXCEPTION 'relationship_state_patch_subject_not_found'; END IF;

    ELSIF v_event.event_type = 'knowledge.character.set' THEN
      v_character_id := NULLIF(v_event.payload->>'character_id','')::uuid;
      v_fact_id := NULLIF(v_event.payload->>'fact_id','')::uuid;
      v_state := COALESCE(NULLIF(v_event.payload->>'state','')::story.knowledge_state,'knows'::story.knowledge_state);
      v_confidence := NULLIF(v_event.payload->>'confidence','')::numeric;
      IF v_character_id IS NULL OR v_fact_id IS NULL THEN RAISE EXCEPTION 'character_knowledge_missing_character_or_fact'; END IF;
      IF NOT EXISTS (SELECT 1 FROM story.characters c WHERE c.id=v_character_id AND c.show_id=v_scene.show_id AND c.organization_id=v_scene.organization_id) THEN RAISE EXCEPTION 'character_knowledge_character_not_found'; END IF;
      IF NOT EXISTS (SELECT 1 FROM story.canon_facts f WHERE f.id=v_fact_id AND f.show_id=v_scene.show_id AND f.organization_id=v_scene.organization_id) THEN RAISE EXCEPTION 'character_knowledge_fact_not_found'; END IF;
      INSERT INTO story.character_knowledge(organization_id,show_id,character_id,fact_id,state,confidence,source,belief_value,learned_scene_id)
      VALUES(v_scene.organization_id,v_scene.show_id,v_character_id,v_fact_id,v_state,v_confidence,NULLIF(v_event.payload->>'source',''),v_event.payload->'belief_value',v_scene.id)
      ON CONFLICT(character_id,fact_id) DO UPDATE SET state=excluded.state,confidence=excluded.confidence,source=excluded.source,belief_value=excluded.belief_value,learned_scene_id=excluded.learned_scene_id,updated_at=now();

    ELSIF v_event.event_type = 'knowledge.audience.set' THEN
      v_fact_id := NULLIF(v_event.payload->>'fact_id','')::uuid;
      v_state := COALESCE(NULLIF(v_event.payload->>'state','')::story.knowledge_state,'knows'::story.knowledge_state);
      v_confidence := NULLIF(v_event.payload->>'confidence','')::numeric;
      IF v_fact_id IS NULL THEN RAISE EXCEPTION 'audience_knowledge_missing_fact'; END IF;
      IF NOT EXISTS (SELECT 1 FROM story.canon_facts f WHERE f.id=v_fact_id AND f.show_id=v_scene.show_id AND f.organization_id=v_scene.organization_id) THEN RAISE EXCEPTION 'audience_knowledge_fact_not_found'; END IF;
      INSERT INTO story.audience_knowledge(organization_id,show_id,fact_id,state,confidence,evidence,learned_scene_id)
      VALUES(v_scene.organization_id,v_scene.show_id,v_fact_id,v_state,v_confidence,COALESCE(v_event.payload->'evidence','{}'::jsonb),v_scene.id)
      ON CONFLICT(show_id,fact_id) DO UPDATE SET state=excluded.state,confidence=excluded.confidence,evidence=excluded.evidence,learned_scene_id=excluded.learned_scene_id,updated_at=now();

    ELSIF v_event.event_type = 'canon.fact_set' THEN
      IF NULLIF(v_event.payload->>'predicate','') IS NULL THEN RAISE EXCEPTION 'canon_fact_set_missing_predicate'; END IF;
      INSERT INTO story.canon_facts(organization_id,show_id,subject_type,subject_id,predicate,object_value,status,authority,source_scene_id,valid_from_story_order,supersedes_fact_id,created_by)
      VALUES(
        v_scene.organization_id,v_scene.show_id,
        COALESCE(NULLIF(v_event.payload->>'subject_type',''),COALESCE(v_event.subject_type,'world')),
        COALESCE(NULLIF(v_event.payload->>'subject_id','')::uuid,v_event.subject_id),
        NULLIF(v_event.payload->>'predicate',''),
        COALESCE(v_event.payload->'object_value','null'::jsonb),
        COALESCE(NULLIF(v_event.payload->>'status','')::story.fact_status,'established'::story.fact_status),
        COALESCE(NULLIF(v_event.payload->>'authority',''),'approved_scene'),
        v_scene.id,v_scene.story_order,NULLIF(v_event.payload->>'supersedes_fact_id','')::uuid,v_user
      );

    ELSIF v_event.event_type = 'reveal.mark_revealed' THEN
      v_reveal_id := COALESCE(NULLIF(v_event.payload->>'reveal_id','')::uuid,v_event.subject_id);
      IF v_reveal_id IS NULL THEN RAISE EXCEPTION 'reveal_mark_revealed_missing_subject'; END IF;
      UPDATE story.reveals SET status='revealed'::story.reveal_status,revealed_scene_id=v_scene.id,updated_at=now()
      WHERE id=v_reveal_id AND show_id=v_scene.show_id AND organization_id=v_scene.organization_id;
      IF NOT FOUND THEN RAISE EXCEPTION 'reveal_not_found'; END IF;

    ELSIF v_event.event_type = 'obligation.resolve' THEN
      IF v_event.subject_id IS NULL THEN RAISE EXCEPTION 'obligation_resolve_missing_subject'; END IF;
      UPDATE story.narrative_obligations SET status='completed'::story.story_node_status,resolved_scene_id=v_scene.id,updated_at=now()
      WHERE id=v_event.subject_id AND show_id=v_scene.show_id AND organization_id=v_scene.organization_id;
      IF NOT FOUND THEN RAISE EXCEPTION 'obligation_not_found'; END IF;

    ELSE
      RAISE EXCEPTION 'unsupported_story_event_type:%',v_event.event_type;
    END IF;

    INSERT INTO story.story_events(organization_id,show_id,scene_id,story_order,event_sequence,event_type,subject_type,subject_id,payload,committed_by)
    VALUES(v_scene.organization_id,v_scene.show_id,v_scene.id,v_scene.story_order,v_event.event_sequence,v_event.event_type,v_event.subject_type,v_event.subject_id,v_event.payload,v_user);
  END LOOP;

  PERFORM set_config('scene_story.commit_authorized','true',true);
  UPDATE story.scenes
  SET status='canonical'::story.scene_status,
      canonical_version=canonical_version+1,
      canonicalized_at=now(),
      updated_at=now()
  WHERE id=v_scene.id;

  SELECT COALESCE(max(snapshot_version),0)+1 INTO v_snapshot_version FROM story.state_snapshots WHERE show_id=v_scene.show_id;
  INSERT INTO story.state_snapshots(organization_id,show_id,through_scene_id,through_story_order,snapshot_version,world_state,relationship_state,knowledge_state,obligation_state)
  VALUES(
    v_scene.organization_id,v_scene.show_id,v_scene.id,v_scene.story_order,v_snapshot_version,
    jsonb_build_object(
      'characters',(SELECT COALESCE(jsonb_object_agg(c.id::text,c.current_state),'{}'::jsonb) FROM story.characters c WHERE c.show_id=v_scene.show_id),
      'locations',(SELECT COALESCE(jsonb_object_agg(l.id::text,l.current_state),'{}'::jsonb) FROM story.locations l WHERE l.show_id=v_scene.show_id),
      'props',(SELECT COALESCE(jsonb_object_agg(p.id::text,jsonb_build_object('state',p.current_state,'owner_character_id',p.owner_character_id,'location_id',p.current_location_id)),'{}'::jsonb) FROM story.props p WHERE p.show_id=v_scene.show_id)
    ),
    (SELECT COALESCE(jsonb_object_agg(r.id::text,r.current_state),'{}'::jsonb) FROM story.relationships r WHERE r.show_id=v_scene.show_id),
    jsonb_build_object(
      'characters',(SELECT COALESCE(jsonb_agg(to_jsonb(ck)),'[]'::jsonb) FROM story.character_knowledge ck WHERE ck.show_id=v_scene.show_id),
      'audience',(SELECT COALESCE(jsonb_agg(to_jsonb(ak)),'[]'::jsonb) FROM story.audience_knowledge ak WHERE ak.show_id=v_scene.show_id)
    ),
    (SELECT COALESCE(jsonb_agg(to_jsonb(o)),'[]'::jsonb) FROM story.narrative_obligations o WHERE o.show_id=v_scene.show_id)
  );

  DELETE FROM story.story_event_proposals WHERE scene_id=v_scene.id;

  PERFORM system.emit_event(
    v_scene.organization_id,'scene.canon_committed','story.scenes',v_scene.id,
    jsonb_build_object('show_id',v_scene.show_id,'story_order',v_scene.story_order,'event_count',v_event_count,'canonical_version',v_scene.canonical_version+1),
    'scene-canon'
  );

  RETURN jsonb_build_object('status','committed','scene_id',v_scene.id,'show_id',v_scene.show_id,'story_order',v_scene.story_order,'event_count',v_event_count,'canonical_version',v_scene.canonical_version+1,'snapshot_version',v_snapshot_version);
END;
$$;

REVOKE ALL ON FUNCTION story.commit_approved_scene(uuid,integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION story.commit_approved_scene(uuid,integer) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION story.resolve_scene_context(p_scene_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'pg_catalog', 'auth', 'platform', 'story'
AS $$
DECLARE
  v_scene story.scenes%ROWTYPE;
  v_snapshot story.state_snapshots%ROWTYPE;
BEGIN
  SELECT * INTO v_scene FROM story.scenes WHERE id=p_scene_id;
  IF v_scene.id IS NULL THEN RETURN jsonb_build_object('status','not_found'); END IF;
  IF auth.uid() IS NOT NULL AND NOT platform.is_org_member(v_scene.organization_id) THEN RETURN jsonb_build_object('status','not_found'); END IF;

  SELECT * INTO v_snapshot
  FROM story.state_snapshots
  WHERE show_id=v_scene.show_id AND through_story_order <= v_scene.story_order
  ORDER BY through_story_order DESC
  LIMIT 1;

  RETURN jsonb_build_object(
    'status','ok',
    'context_version',2,
    'resolved_at',now(),
    'organization_id',v_scene.organization_id,
    'show_id',v_scene.show_id,
    'scene_id',v_scene.id,
    'story_position',jsonb_build_object(
      'story_order',v_scene.story_order,
      'episode_id',v_scene.episode_id,
      'scene_number',v_scene.scene_number,
      'scene_status',v_scene.status,
      'canonical_version',v_scene.canonical_version
    ),
    'scene',jsonb_build_object('title',v_scene.title,'purpose',v_scene.purpose,'runtime_target_seconds',v_scene.runtime_target_seconds),
    'snapshot',CASE WHEN v_snapshot.id IS NULL THEN NULL ELSE jsonb_build_object(
      'through_scene_id',v_snapshot.through_scene_id,
      'through_story_order',v_snapshot.through_story_order,
      'snapshot_version',v_snapshot.snapshot_version,
      'world_state',v_snapshot.world_state,
      'relationship_state',v_snapshot.relationship_state,
      'knowledge_state',v_snapshot.knowledge_state,
      'obligation_state',v_snapshot.obligation_state
    ) END,
    'characters',(SELECT COALESCE(jsonb_agg(jsonb_build_object('id',c.id,'name',c.name,'character_key',c.character_key,'narrative_role',c.narrative_role,'description',c.description,'base_traits',c.base_traits,'current_state',COALESCE(v_snapshot.world_state->'characters'->c.id::text,c.current_state),'participation_role',sc.participation_role,'scene_entry_state',sc.entry_state,'scene_exit_state',sc.exit_state)),'[]'::jsonb) FROM story.scene_characters sc JOIN story.characters c ON c.id=sc.character_id WHERE sc.scene_id=v_scene.id),
    'locations',(SELECT COALESCE(jsonb_agg(jsonb_build_object('id',l.id,'name',l.name,'location_key',l.location_key,'description',l.description,'location_type',l.location_type,'topology',l.topology,'base_traits',l.base_traits,'current_state',COALESCE(v_snapshot.world_state->'locations'->l.id::text,l.current_state),'scene_role',sl.scene_role,'scene_entry_state',sl.entry_state,'scene_exit_state',sl.exit_state)),'[]'::jsonb) FROM story.scene_locations sl JOIN story.locations l ON l.id=sl.location_id WHERE sl.scene_id=v_scene.id),
    'props',(SELECT COALESCE(jsonb_agg(jsonb_build_object('id',p.id,'name',p.name,'prop_key',p.prop_key,'description',p.description,'prop_type',p.prop_type,'base_traits',p.base_traits,'current_state',p.current_state,'owner_character_id',p.owner_character_id,'current_location_id',p.current_location_id,'scene_role',sp.scene_role,'scene_entry_state',sp.entry_state,'scene_exit_state',sp.exit_state)),'[]'::jsonb) FROM story.scene_props sp JOIN story.props p ON p.id=sp.prop_id WHERE sp.scene_id=v_scene.id),
    'canon_facts',(SELECT COALESCE(jsonb_agg(to_jsonb(f)),'[]'::jsonb) FROM story.canon_facts f WHERE f.show_id=v_scene.show_id AND f.status='established' AND (f.valid_from_story_order IS NULL OR f.valid_from_story_order <= v_scene.story_order) AND (f.valid_to_story_order IS NULL OR f.valid_to_story_order >= v_scene.story_order)),
    'character_knowledge',(SELECT COALESCE(jsonb_agg(to_jsonb(ck)),'[]'::jsonb) FROM story.character_knowledge ck WHERE ck.show_id=v_scene.show_id),
    'audience_knowledge',(SELECT COALESCE(jsonb_agg(to_jsonb(ak)),'[]'::jsonb) FROM story.audience_knowledge ak WHERE ak.show_id=v_scene.show_id),
    'relationships',(SELECT COALESCE(jsonb_agg(to_jsonb(r)),'[]'::jsonb) FROM story.relationships r WHERE r.show_id=v_scene.show_id),
    'permitted_reveals',(SELECT COALESCE(jsonb_agg(to_jsonb(r)),'[]'::jsonb) FROM story.reveals r WHERE r.show_id=v_scene.show_id AND r.status IN ('planned','eligible') AND (r.prohibited_before_story_order IS NULL OR v_scene.story_order >= r.prohibited_before_story_order) AND (r.earliest_story_order IS NULL OR v_scene.story_order >= r.earliest_story_order) AND (r.latest_story_order IS NULL OR v_scene.story_order <= r.latest_story_order) AND NOT EXISTS(SELECT 1 FROM story.reveal_prerequisites rp JOIN story.reveals prereq ON prereq.id=rp.prerequisite_reveal_id WHERE rp.reveal_id=r.id AND prereq.status <> 'revealed')),
    'forbidden_reveals',(SELECT COALESCE(jsonb_agg(to_jsonb(r)),'[]'::jsonb) FROM story.reveals r WHERE r.show_id=v_scene.show_id AND r.status <> 'revealed' AND ((r.prohibited_before_story_order IS NOT NULL AND v_scene.story_order < r.prohibited_before_story_order) OR EXISTS(SELECT 1 FROM story.reveal_prerequisites rp JOIN story.reveals prereq ON prereq.id=rp.prerequisite_reveal_id WHERE rp.reveal_id=r.id AND prereq.status <> 'revealed'))),
    'obligations',(SELECT COALESCE(jsonb_agg(to_jsonb(o)),'[]'::jsonb) FROM story.narrative_obligations o WHERE o.show_id=v_scene.show_id AND o.status IN ('planned','active')),
    'future_constraints',(SELECT COALESCE(jsonb_agg(to_jsonb(n)),'[]'::jsonb) FROM story.future_story_nodes n WHERE n.show_id=v_scene.show_id AND n.status IN ('planned','proposed')),
    'final_state_contracts',(SELECT COALESCE(jsonb_agg(to_jsonb(fsc)),'[]'::jsonb) FROM story.final_state_contracts fsc WHERE fsc.show_id=v_scene.show_id),
    'relevant_events',(SELECT COALESCE(jsonb_agg(to_jsonb(e) ORDER BY e.story_order DESC,e.event_sequence DESC),'[]'::jsonb) FROM (SELECT * FROM story.story_events WHERE show_id=v_scene.show_id AND story_order <= v_scene.story_order ORDER BY story_order DESC,event_sequence DESC LIMIT 100) e)
  );
END;
$$;

REVOKE ALL ON FUNCTION story.resolve_scene_context(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION story.resolve_scene_context(uuid) TO authenticated, service_role;
