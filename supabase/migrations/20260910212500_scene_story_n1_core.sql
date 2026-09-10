-- Scene N1 generalized narrative state on the shared UncleCred backend.
-- Reuses platform.organizations, platform.organization_members, platform.universes,
-- platform.set_updated_at, and system.system_events. Does not duplicate those systems.

DO $$ BEGIN CREATE TYPE story.story_node_status AS ENUM ('planned','active','completed','superseded','cancelled'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE story.scene_status AS ENUM ('draft','planned','generated','evaluating','approved','canonical','superseded','rejected'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE story.fact_status AS ENUM ('established','planned','proposed','inferred','unknown','disputed','superseded','rejected'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE story.knowledge_state AS ENUM ('unknown','suspects','believes','knows','disbelieves'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE story.reveal_status AS ENUM ('planned','eligible','revealed','superseded','cancelled'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE story.obligation_kind AS ENUM ('setup','payoff','red_herring','future_hook','open_question'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE story.scheduling_mode AS ENUM ('exact','windowed','ordered','optional','emergent'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE story.production_mode AS ENUM ('cinematic','anime','stylized_3d','cartoon','comic','stick_figure'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE story.guidance_mode AS ENUM ('follow_closely','build_with_me','take_the_wheel'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE platform.universes ADD CONSTRAINT universes_id_org_unique UNIQUE (id, organization_id);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS story.shows (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES platform.organizations(id) ON DELETE CASCADE,
  universe_id uuid,
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  title text NOT NULL,
  initial_request text NOT NULL,
  format text,
  production_mode story.production_mode NOT NULL DEFAULT 'cinematic',
  guidance_mode story.guidance_mode NOT NULL DEFAULT 'take_the_wheel',
  creator_input_state jsonb NOT NULL DEFAULT '{}'::jsonb,
  status story.story_node_status NOT NULL DEFAULT 'active',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (id, organization_id),
  FOREIGN KEY (universe_id, organization_id) REFERENCES platform.universes(id, organization_id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS story.seasons (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES platform.organizations(id) ON DELETE CASCADE,
  show_id uuid NOT NULL,
  season_number integer NOT NULL CHECK (season_number > 0),
  title text,
  status story.story_node_status NOT NULL DEFAULT 'planned',
  target_episode_count integer CHECK (target_episode_count IS NULL OR target_episode_count > 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (show_id, season_number),
  UNIQUE (id, show_id, organization_id),
  FOREIGN KEY (show_id, organization_id) REFERENCES story.shows(id, organization_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS story.story_arcs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES platform.organizations(id) ON DELETE CASCADE,
  show_id uuid NOT NULL,
  season_id uuid,
  arc_key text NOT NULL,
  title text NOT NULL,
  summary text,
  status story.story_node_status NOT NULL DEFAULT 'planned',
  start_episode_hint integer CHECK (start_episode_hint IS NULL OR start_episode_hint > 0),
  end_episode_hint integer CHECK (end_episode_hint IS NULL OR end_episode_hint > 0),
  priority integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (show_id, arc_key),
  UNIQUE (id, show_id, organization_id),
  FOREIGN KEY (show_id, organization_id) REFERENCES story.shows(id, organization_id) ON DELETE CASCADE,
  FOREIGN KEY (season_id, show_id, organization_id) REFERENCES story.seasons(id, show_id, organization_id) ON DELETE SET NULL,
  CHECK (start_episode_hint IS NULL OR end_episode_hint IS NULL OR end_episode_hint >= start_episode_hint)
);

CREATE TABLE IF NOT EXISTS story.story_blocks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES platform.organizations(id) ON DELETE CASCADE,
  show_id uuid NOT NULL,
  season_id uuid,
  arc_id uuid,
  position integer NOT NULL CHECK (position > 0),
  title text,
  objective text NOT NULL,
  episode_window_start integer CHECK (episode_window_start IS NULL OR episode_window_start > 0),
  episode_window_end integer CHECK (episode_window_end IS NULL OR episode_window_end > 0),
  exit_conditions jsonb NOT NULL DEFAULT '[]'::jsonb,
  status story.story_node_status NOT NULL DEFAULT 'planned',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (show_id, season_id, position),
  UNIQUE (id, show_id, organization_id),
  FOREIGN KEY (show_id, organization_id) REFERENCES story.shows(id, organization_id) ON DELETE CASCADE,
  FOREIGN KEY (season_id, show_id, organization_id) REFERENCES story.seasons(id, show_id, organization_id) ON DELETE SET NULL,
  FOREIGN KEY (arc_id, show_id, organization_id) REFERENCES story.story_arcs(id, show_id, organization_id) ON DELETE SET NULL,
  CHECK (episode_window_start IS NULL OR episode_window_end IS NULL OR episode_window_end >= episode_window_start)
);

CREATE TABLE IF NOT EXISTS story.episodes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES platform.organizations(id) ON DELETE CASCADE,
  show_id uuid NOT NULL,
  season_id uuid,
  story_block_id uuid,
  episode_number integer NOT NULL CHECK (episode_number > 0),
  title text,
  logline text,
  objective text,
  status story.story_node_status NOT NULL DEFAULT 'planned',
  production_order bigint,
  release_order bigint,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (show_id, season_id, episode_number),
  UNIQUE (id, show_id, organization_id),
  FOREIGN KEY (show_id, organization_id) REFERENCES story.shows(id, organization_id) ON DELETE CASCADE,
  FOREIGN KEY (season_id, show_id, organization_id) REFERENCES story.seasons(id, show_id, organization_id) ON DELETE SET NULL,
  FOREIGN KEY (story_block_id, show_id, organization_id) REFERENCES story.story_blocks(id, show_id, organization_id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS story.scenes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES platform.organizations(id) ON DELETE CASCADE,
  show_id uuid NOT NULL,
  episode_id uuid,
  scene_number integer NOT NULL CHECK (scene_number > 0),
  story_order numeric(20,6) NOT NULL,
  production_order bigint,
  release_order bigint,
  title text,
  purpose text,
  status story.scene_status NOT NULL DEFAULT 'draft',
  runtime_target_seconds integer CHECK (runtime_target_seconds IS NULL OR runtime_target_seconds > 0),
  canonical_version integer NOT NULL DEFAULT 0 CHECK (canonical_version >= 0),
  canonicalized_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (show_id, story_order),
  UNIQUE (episode_id, scene_number),
  UNIQUE (id, show_id, organization_id),
  FOREIGN KEY (show_id, organization_id) REFERENCES story.shows(id, organization_id) ON DELETE CASCADE,
  FOREIGN KEY (episode_id, show_id, organization_id) REFERENCES story.episodes(id, show_id, organization_id) ON DELETE SET NULL,
  CHECK ((status = 'canonical' AND canonicalized_at IS NOT NULL) OR status <> 'canonical')
);

CREATE TABLE IF NOT EXISTS story.beats (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES platform.organizations(id) ON DELETE CASCADE,
  show_id uuid NOT NULL,
  scene_id uuid NOT NULL,
  position integer NOT NULL CHECK (position > 0),
  beat_type text,
  description text NOT NULL,
  required boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (scene_id, position),
  FOREIGN KEY (show_id, organization_id) REFERENCES story.shows(id, organization_id) ON DELETE CASCADE,
  FOREIGN KEY (scene_id, show_id, organization_id) REFERENCES story.scenes(id, show_id, organization_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS story.characters (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES platform.organizations(id) ON DELETE CASCADE,
  show_id uuid NOT NULL,
  character_key text NOT NULL,
  name text NOT NULL,
  narrative_role text,
  description text,
  base_traits jsonb NOT NULL DEFAULT '{}'::jsonb,
  current_state jsonb NOT NULL DEFAULT '{}'::jsonb,
  status story.story_node_status NOT NULL DEFAULT 'active',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (show_id, character_key),
  UNIQUE (id, show_id, organization_id),
  FOREIGN KEY (show_id, organization_id) REFERENCES story.shows(id, organization_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS story.locations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES platform.organizations(id) ON DELETE CASCADE,
  show_id uuid NOT NULL,
  location_key text NOT NULL,
  name text NOT NULL,
  description text,
  location_type text,
  topology jsonb NOT NULL DEFAULT '{}'::jsonb,
  base_traits jsonb NOT NULL DEFAULT '{}'::jsonb,
  current_state jsonb NOT NULL DEFAULT '{}'::jsonb,
  status story.story_node_status NOT NULL DEFAULT 'active',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (show_id, location_key),
  UNIQUE (id, show_id, organization_id),
  FOREIGN KEY (show_id, organization_id) REFERENCES story.shows(id, organization_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS story.props (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES platform.organizations(id) ON DELETE CASCADE,
  show_id uuid NOT NULL,
  prop_key text NOT NULL,
  name text NOT NULL,
  description text,
  prop_type text,
  base_traits jsonb NOT NULL DEFAULT '{}'::jsonb,
  current_state jsonb NOT NULL DEFAULT '{}'::jsonb,
  owner_character_id uuid,
  current_location_id uuid,
  status story.story_node_status NOT NULL DEFAULT 'active',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (show_id, prop_key),
  UNIQUE (id, show_id, organization_id),
  FOREIGN KEY (show_id, organization_id) REFERENCES story.shows(id, organization_id) ON DELETE CASCADE,
  FOREIGN KEY (owner_character_id, show_id, organization_id) REFERENCES story.characters(id, show_id, organization_id) ON DELETE SET NULL,
  FOREIGN KEY (current_location_id, show_id, organization_id) REFERENCES story.locations(id, show_id, organization_id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS story.relationships (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES platform.organizations(id) ON DELETE CASCADE,
  show_id uuid NOT NULL,
  character_a_id uuid NOT NULL,
  character_b_id uuid NOT NULL,
  relationship_type text,
  dimensions jsonb NOT NULL DEFAULT '{}'::jsonb,
  current_state jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (show_id, character_a_id, character_b_id),
  UNIQUE (id, show_id, organization_id),
  CHECK (character_a_id <> character_b_id),
  FOREIGN KEY (show_id, organization_id) REFERENCES story.shows(id, organization_id) ON DELETE CASCADE,
  FOREIGN KEY (character_a_id, show_id, organization_id) REFERENCES story.characters(id, show_id, organization_id) ON DELETE CASCADE,
  FOREIGN KEY (character_b_id, show_id, organization_id) REFERENCES story.characters(id, show_id, organization_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS story.scene_characters (
  scene_id uuid NOT NULL,
  show_id uuid NOT NULL,
  organization_id uuid NOT NULL,
  character_id uuid NOT NULL,
  participation_role text NOT NULL DEFAULT 'present',
  entry_state jsonb NOT NULL DEFAULT '{}'::jsonb,
  exit_state jsonb NOT NULL DEFAULT '{}'::jsonb,
  PRIMARY KEY (scene_id, character_id),
  FOREIGN KEY (scene_id, show_id, organization_id) REFERENCES story.scenes(id, show_id, organization_id) ON DELETE CASCADE,
  FOREIGN KEY (character_id, show_id, organization_id) REFERENCES story.characters(id, show_id, organization_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS story.scene_locations (
  scene_id uuid NOT NULL,
  show_id uuid NOT NULL,
  organization_id uuid NOT NULL,
  location_id uuid NOT NULL,
  scene_role text NOT NULL DEFAULT 'primary',
  entry_state jsonb NOT NULL DEFAULT '{}'::jsonb,
  exit_state jsonb NOT NULL DEFAULT '{}'::jsonb,
  PRIMARY KEY (scene_id, location_id),
  FOREIGN KEY (scene_id, show_id, organization_id) REFERENCES story.scenes(id, show_id, organization_id) ON DELETE CASCADE,
  FOREIGN KEY (location_id, show_id, organization_id) REFERENCES story.locations(id, show_id, organization_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS story.scene_props (
  scene_id uuid NOT NULL,
  show_id uuid NOT NULL,
  organization_id uuid NOT NULL,
  prop_id uuid NOT NULL,
  scene_role text NOT NULL DEFAULT 'present',
  entry_state jsonb NOT NULL DEFAULT '{}'::jsonb,
  exit_state jsonb NOT NULL DEFAULT '{}'::jsonb,
  PRIMARY KEY (scene_id, prop_id),
  FOREIGN KEY (scene_id, show_id, organization_id) REFERENCES story.scenes(id, show_id, organization_id) ON DELETE CASCADE,
  FOREIGN KEY (prop_id, show_id, organization_id) REFERENCES story.props(id, show_id, organization_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS story.final_state_contracts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES platform.organizations(id) ON DELETE CASCADE,
  show_id uuid NOT NULL,
  scope_type text NOT NULL CHECK (scope_type IN ('show','season','arc','block')),
  scope_id uuid,
  locked boolean NOT NULL DEFAULT false,
  contract jsonb NOT NULL DEFAULT '{}'::jsonb,
  version integer NOT NULL DEFAULT 1 CHECK (version > 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (show_id, scope_type, scope_id, version),
  FOREIGN KEY (show_id, organization_id) REFERENCES story.shows(id, organization_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS story.future_story_nodes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES platform.organizations(id) ON DELETE CASCADE,
  show_id uuid NOT NULL,
  season_id uuid,
  arc_id uuid,
  node_key text NOT NULL,
  node_type text NOT NULL,
  title text NOT NULL,
  description text,
  status story.fact_status NOT NULL DEFAULT 'planned',
  scheduling_mode story.scheduling_mode NOT NULL DEFAULT 'windowed',
  earliest_episode integer CHECK (earliest_episode IS NULL OR earliest_episode > 0),
  latest_episode integer CHECK (latest_episode IS NULL OR latest_episode > 0),
  exact_episode integer CHECK (exact_episode IS NULL OR exact_episode > 0),
  priority integer NOT NULL DEFAULT 0,
  locked boolean NOT NULL DEFAULT false,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (show_id, node_key),
  UNIQUE (id, show_id, organization_id),
  FOREIGN KEY (show_id, organization_id) REFERENCES story.shows(id, organization_id) ON DELETE CASCADE,
  FOREIGN KEY (season_id, show_id, organization_id) REFERENCES story.seasons(id, show_id, organization_id) ON DELETE SET NULL,
  FOREIGN KEY (arc_id, show_id, organization_id) REFERENCES story.story_arcs(id, show_id, organization_id) ON DELETE SET NULL,
  CHECK (earliest_episode IS NULL OR latest_episode IS NULL OR latest_episode >= earliest_episode),
  CHECK (scheduling_mode <> 'exact' OR exact_episode IS NOT NULL)
);

CREATE TABLE IF NOT EXISTS story.future_story_dependencies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES platform.organizations(id) ON DELETE CASCADE,
  show_id uuid NOT NULL,
  predecessor_node_id uuid NOT NULL,
  successor_node_id uuid NOT NULL,
  dependency_type text NOT NULL CHECK (dependency_type IN ('requires','after','before','excludes','enables')),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (predecessor_node_id, successor_node_id, dependency_type),
  CHECK (predecessor_node_id <> successor_node_id),
  FOREIGN KEY (show_id, organization_id) REFERENCES story.shows(id, organization_id) ON DELETE CASCADE,
  FOREIGN KEY (predecessor_node_id, show_id, organization_id) REFERENCES story.future_story_nodes(id, show_id, organization_id) ON DELETE CASCADE,
  FOREIGN KEY (successor_node_id, show_id, organization_id) REFERENCES story.future_story_nodes(id, show_id, organization_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS story.canon_facts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES platform.organizations(id) ON DELETE CASCADE,
  show_id uuid NOT NULL,
  subject_type text NOT NULL,
  subject_id uuid,
  predicate text NOT NULL,
  object_value jsonb NOT NULL,
  status story.fact_status NOT NULL DEFAULT 'established',
  authority text NOT NULL DEFAULT 'approved_canon',
  source_scene_id uuid,
  valid_from_story_order numeric(20,6),
  valid_to_story_order numeric(20,6),
  supersedes_fact_id uuid REFERENCES story.canon_facts(id) ON DELETE SET NULL,
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (show_id, organization_id) REFERENCES story.shows(id, organization_id) ON DELETE CASCADE,
  FOREIGN KEY (source_scene_id, show_id, organization_id) REFERENCES story.scenes(id, show_id, organization_id) ON DELETE SET NULL,
  CHECK (valid_to_story_order IS NULL OR valid_from_story_order IS NULL OR valid_to_story_order >= valid_from_story_order)
);

CREATE TABLE IF NOT EXISTS story.story_event_proposals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES platform.organizations(id) ON DELETE CASCADE,
  show_id uuid NOT NULL,
  scene_id uuid NOT NULL,
  event_sequence integer NOT NULL CHECK (event_sequence > 0),
  event_type text NOT NULL,
  subject_type text,
  subject_id uuid,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (scene_id, event_sequence),
  FOREIGN KEY (show_id, organization_id) REFERENCES story.shows(id, organization_id) ON DELETE CASCADE,
  FOREIGN KEY (scene_id, show_id, organization_id) REFERENCES story.scenes(id, show_id, organization_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS story.story_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES platform.organizations(id) ON DELETE CASCADE,
  show_id uuid NOT NULL,
  scene_id uuid NOT NULL,
  story_order numeric(20,6) NOT NULL,
  event_sequence integer NOT NULL CHECK (event_sequence > 0),
  event_type text NOT NULL,
  subject_type text,
  subject_id uuid,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  committed_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  committed_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (scene_id, event_sequence),
  FOREIGN KEY (show_id, organization_id) REFERENCES story.shows(id, organization_id) ON DELETE CASCADE,
  FOREIGN KEY (scene_id, show_id, organization_id) REFERENCES story.scenes(id, show_id, organization_id) ON DELETE RESTRICT
);

CREATE TABLE IF NOT EXISTS story.state_snapshots (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES platform.organizations(id) ON DELETE CASCADE,
  show_id uuid NOT NULL,
  through_scene_id uuid NOT NULL,
  through_story_order numeric(20,6) NOT NULL,
  snapshot_version integer NOT NULL CHECK (snapshot_version > 0),
  world_state jsonb NOT NULL DEFAULT '{}'::jsonb,
  relationship_state jsonb NOT NULL DEFAULT '{}'::jsonb,
  knowledge_state jsonb NOT NULL DEFAULT '{}'::jsonb,
  obligation_state jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (show_id, snapshot_version),
  UNIQUE (show_id, through_story_order),
  FOREIGN KEY (show_id, organization_id) REFERENCES story.shows(id, organization_id) ON DELETE CASCADE,
  FOREIGN KEY (through_scene_id, show_id, organization_id) REFERENCES story.scenes(id, show_id, organization_id) ON DELETE RESTRICT
);

CREATE TABLE IF NOT EXISTS story.character_knowledge (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES platform.organizations(id) ON DELETE CASCADE,
  show_id uuid NOT NULL,
  character_id uuid NOT NULL,
  fact_id uuid NOT NULL,
  state story.knowledge_state NOT NULL DEFAULT 'unknown',
  confidence numeric(4,3) CHECK (confidence IS NULL OR (confidence >= 0 AND confidence <= 1)),
  source text,
  belief_value jsonb,
  learned_scene_id uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (character_id, fact_id),
  FOREIGN KEY (show_id, organization_id) REFERENCES story.shows(id, organization_id) ON DELETE CASCADE,
  FOREIGN KEY (character_id, show_id, organization_id) REFERENCES story.characters(id, show_id, organization_id) ON DELETE CASCADE,
  FOREIGN KEY (fact_id) REFERENCES story.canon_facts(id) ON DELETE CASCADE,
  FOREIGN KEY (learned_scene_id, show_id, organization_id) REFERENCES story.scenes(id, show_id, organization_id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS story.audience_knowledge (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES platform.organizations(id) ON DELETE CASCADE,
  show_id uuid NOT NULL,
  fact_id uuid NOT NULL,
  state story.knowledge_state NOT NULL DEFAULT 'unknown',
  confidence numeric(4,3) CHECK (confidence IS NULL OR (confidence >= 0 AND confidence <= 1)),
  evidence jsonb NOT NULL DEFAULT '{}'::jsonb,
  learned_scene_id uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (show_id, fact_id),
  FOREIGN KEY (show_id, organization_id) REFERENCES story.shows(id, organization_id) ON DELETE CASCADE,
  FOREIGN KEY (fact_id) REFERENCES story.canon_facts(id) ON DELETE CASCADE,
  FOREIGN KEY (learned_scene_id, show_id, organization_id) REFERENCES story.scenes(id, show_id, organization_id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS story.reveals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES platform.organizations(id) ON DELETE CASCADE,
  show_id uuid NOT NULL,
  fact_id uuid NOT NULL REFERENCES story.canon_facts(id) ON DELETE CASCADE,
  status story.reveal_status NOT NULL DEFAULT 'planned',
  earliest_story_order numeric(20,6),
  latest_story_order numeric(20,6),
  prohibited_before_story_order numeric(20,6),
  revealed_scene_id uuid,
  targets_audience boolean NOT NULL DEFAULT true,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (show_id, organization_id) REFERENCES story.shows(id, organization_id) ON DELETE CASCADE,
  FOREIGN KEY (revealed_scene_id, show_id, organization_id) REFERENCES story.scenes(id, show_id, organization_id) ON DELETE SET NULL,
  CHECK (earliest_story_order IS NULL OR latest_story_order IS NULL OR latest_story_order >= earliest_story_order)
);

CREATE TABLE IF NOT EXISTS story.reveal_targets (
  reveal_id uuid NOT NULL REFERENCES story.reveals(id) ON DELETE CASCADE,
  character_id uuid,
  target_audience boolean NOT NULL DEFAULT false,
  PRIMARY KEY (reveal_id, character_id, target_audience),
  CHECK (character_id IS NOT NULL OR target_audience = true)
);

CREATE TABLE IF NOT EXISTS story.reveal_prerequisites (
  reveal_id uuid NOT NULL REFERENCES story.reveals(id) ON DELETE CASCADE,
  prerequisite_reveal_id uuid NOT NULL REFERENCES story.reveals(id) ON DELETE CASCADE,
  PRIMARY KEY (reveal_id, prerequisite_reveal_id),
  CHECK (reveal_id <> prerequisite_reveal_id)
);

CREATE TABLE IF NOT EXISTS story.narrative_obligations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES platform.organizations(id) ON DELETE CASCADE,
  show_id uuid NOT NULL,
  kind story.obligation_kind NOT NULL,
  obligation_key text,
  title text NOT NULL,
  description text,
  importance integer NOT NULL DEFAULT 0,
  status story.story_node_status NOT NULL DEFAULT 'planned',
  created_scene_id uuid,
  intended_payoff_scene_id uuid,
  intended_payoff_node_id uuid,
  resolved_scene_id uuid,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (show_id, obligation_key),
  FOREIGN KEY (show_id, organization_id) REFERENCES story.shows(id, organization_id) ON DELETE CASCADE,
  FOREIGN KEY (created_scene_id, show_id, organization_id) REFERENCES story.scenes(id, show_id, organization_id) ON DELETE SET NULL,
  FOREIGN KEY (intended_payoff_scene_id, show_id, organization_id) REFERENCES story.scenes(id, show_id, organization_id) ON DELETE SET NULL,
  FOREIGN KEY (intended_payoff_node_id, show_id, organization_id) REFERENCES story.future_story_nodes(id, show_id, organization_id) ON DELETE SET NULL,
  FOREIGN KEY (resolved_scene_id, show_id, organization_id) REFERENCES story.scenes(id, show_id, organization_id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS story.show_blueprints (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES platform.organizations(id) ON DELETE CASCADE,
  show_id uuid NOT NULL,
  version integer NOT NULL CHECK (version > 0),
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('draft','active','superseded','rejected')),
  blueprint jsonb NOT NULL,
  model_provider text,
  model_name text,
  provider_request_id text,
  input_hash text NOT NULL,
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (show_id, version),
  FOREIGN KEY (show_id, organization_id) REFERENCES story.shows(id, organization_id) ON DELETE CASCADE
);
CREATE UNIQUE INDEX IF NOT EXISTS show_blueprints_one_active ON story.show_blueprints(show_id) WHERE status = 'active';

CREATE INDEX IF NOT EXISTS scenes_show_story_order_idx ON story.scenes(show_id, story_order);
CREATE INDEX IF NOT EXISTS story_events_show_order_idx ON story.story_events(show_id, story_order, event_sequence);
CREATE INDEX IF NOT EXISTS canon_facts_show_subject_idx ON story.canon_facts(show_id, subject_type, subject_id, predicate);
CREATE INDEX IF NOT EXISTS future_story_nodes_show_status_idx ON story.future_story_nodes(show_id, status, priority DESC);
CREATE INDEX IF NOT EXISTS obligations_show_status_idx ON story.narrative_obligations(show_id, status, importance DESC);

CREATE OR REPLACE FUNCTION story.reject_story_event_mutation()
RETURNS trigger LANGUAGE plpgsql SET search_path = 'pg_catalog' AS $$
BEGIN
  RAISE EXCEPTION 'canonical story events are immutable';
END $$;
DROP TRIGGER IF EXISTS story_events_immutable ON story.story_events;
CREATE TRIGGER story_events_immutable BEFORE UPDATE OR DELETE ON story.story_events FOR EACH ROW EXECUTE FUNCTION story.reject_story_event_mutation();

ALTER TABLE story.shows ENABLE ROW LEVEL SECURITY;
ALTER TABLE story.seasons ENABLE ROW LEVEL SECURITY;
ALTER TABLE story.story_arcs ENABLE ROW LEVEL SECURITY;
ALTER TABLE story.story_blocks ENABLE ROW LEVEL SECURITY;
ALTER TABLE story.episodes ENABLE ROW LEVEL SECURITY;
ALTER TABLE story.scenes ENABLE ROW LEVEL SECURITY;
ALTER TABLE story.beats ENABLE ROW LEVEL SECURITY;
ALTER TABLE story.characters ENABLE ROW LEVEL SECURITY;
ALTER TABLE story.locations ENABLE ROW LEVEL SECURITY;
ALTER TABLE story.props ENABLE ROW LEVEL SECURITY;
ALTER TABLE story.relationships ENABLE ROW LEVEL SECURITY;
ALTER TABLE story.scene_characters ENABLE ROW LEVEL SECURITY;
ALTER TABLE story.scene_locations ENABLE ROW LEVEL SECURITY;
ALTER TABLE story.scene_props ENABLE ROW LEVEL SECURITY;
ALTER TABLE story.final_state_contracts ENABLE ROW LEVEL SECURITY;
ALTER TABLE story.future_story_nodes ENABLE ROW LEVEL SECURITY;
ALTER TABLE story.future_story_dependencies ENABLE ROW LEVEL SECURITY;
ALTER TABLE story.canon_facts ENABLE ROW LEVEL SECURITY;
ALTER TABLE story.story_event_proposals ENABLE ROW LEVEL SECURITY;
ALTER TABLE story.story_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE story.state_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE story.character_knowledge ENABLE ROW LEVEL SECURITY;
ALTER TABLE story.audience_knowledge ENABLE ROW LEVEL SECURITY;
ALTER TABLE story.reveals ENABLE ROW LEVEL SECURITY;
ALTER TABLE story.reveal_targets ENABLE ROW LEVEL SECURITY;
ALTER TABLE story.reveal_prerequisites ENABLE ROW LEVEL SECURITY;
ALTER TABLE story.narrative_obligations ENABLE ROW LEVEL SECURITY;
ALTER TABLE story.show_blueprints ENABLE ROW LEVEL SECURITY;

DO $$ DECLARE t text; BEGIN
  FOREACH t IN ARRAY ARRAY['shows','seasons','story_arcs','story_blocks','episodes','scenes','beats','characters','locations','props','relationships','scene_characters','scene_locations','scene_props','final_state_contracts','future_story_nodes','future_story_dependencies','canon_facts','story_event_proposals','story_events','state_snapshots','character_knowledge','audience_knowledge','reveals','narrative_obligations','show_blueprints']
  LOOP
    EXECUTE format('CREATE POLICY %I ON story.%I FOR SELECT TO authenticated USING (platform.is_org_member(organization_id))', 'story_members_read_'||t, t);
    EXECUTE format('CREATE POLICY %I ON story.%I FOR ALL TO authenticated USING (platform.is_org_admin(organization_id)) WITH CHECK (platform.is_org_admin(organization_id))', 'story_admins_write_'||t, t);
  END LOOP;
END $$;

CREATE POLICY story_members_read_reveal_targets ON story.reveal_targets FOR SELECT TO authenticated USING (
  EXISTS (SELECT 1 FROM story.reveals r WHERE r.id = reveal_targets.reveal_id AND platform.is_org_member(r.organization_id))
);
CREATE POLICY story_admins_write_reveal_targets ON story.reveal_targets FOR ALL TO authenticated USING (
  EXISTS (SELECT 1 FROM story.reveals r WHERE r.id = reveal_targets.reveal_id AND platform.is_org_admin(r.organization_id))
) WITH CHECK (
  EXISTS (SELECT 1 FROM story.reveals r WHERE r.id = reveal_targets.reveal_id AND platform.is_org_admin(r.organization_id))
);
CREATE POLICY story_members_read_reveal_prereqs ON story.reveal_prerequisites FOR SELECT TO authenticated USING (
  EXISTS (SELECT 1 FROM story.reveals r WHERE r.id = reveal_prerequisites.reveal_id AND platform.is_org_member(r.organization_id))
);
CREATE POLICY story_admins_write_reveal_prereqs ON story.reveal_prerequisites FOR ALL TO authenticated USING (
  EXISTS (SELECT 1 FROM story.reveals r WHERE r.id = reveal_prerequisites.reveal_id AND platform.is_org_admin(r.organization_id))
) WITH CHECK (
  EXISTS (SELECT 1 FROM story.reveals r WHERE r.id = reveal_prerequisites.reveal_id AND platform.is_org_admin(r.organization_id))
);

REVOKE UPDATE, DELETE ON story.story_events FROM authenticated, anon;

DO $$ DECLARE t text; BEGIN
  FOREACH t IN ARRAY ARRAY['shows','seasons','story_arcs','story_blocks','episodes','scenes','characters','locations','props','relationships','final_state_contracts','future_story_nodes','narrative_obligations','reveals']
  LOOP
    EXECUTE format('CREATE TRIGGER trg_story_updated_at BEFORE UPDATE ON story.%I FOR EACH ROW EXECUTE FUNCTION platform.set_updated_at()', t);
  END LOOP;
END $$;
